/**
 * SyncEngine.ets — W10-C5 通用云同步引擎 (W5 Soul-wired)
 *
 * 是 W7 ProgressSync（仅 reading-progress 单 entity）的通用化版本。
 * 支持注册多个 EntitySyncer，按 entityType 共享同一套调度策略：
 *
 *   - 启动 init() 时全量 pull（若距上次 sync > IDLE_PULL_THRESHOLD 24h）
 *   - 数据变更 enqueue() → debounce 300ms → 批量 push（W5: 改为 300ms per mission）
 *   - 网络断开挂起，恢复后 flush
 *   - push 失败指数退避 1s/2s/4s/8s max 60s
 *   - 周期后台 sync 30 min（tick）
 *   - 冲突：默认 LWW（updatedAt 比较）；syncer 可覆盖 resolveConflict
 *   - W5 SoulBridge: flush() 同步向 SoulEngine.update() 广播；
 *     SoulEngine 远端变更事件驱动 pull（event-driven，不 debounce）
 *
 * 服务端协议（与 server-cn 待实现的 /api/v1/sync 对齐，本任务不动后端）：
 *   POST /api/v1/sync/pull  body { entityType, since? }   → { items: T[], serverNow }
 *   POST /api/v1/sync/push  body { entityType, items: T[] } → { accepted: T[], conflicts: ConflictItem[] }
 *
 * 与 W7 ProgressSync 的关系：
 *   - 不破坏：W7 现有调用方继续走 ProgressSync
 *   - 本任务的 ReadingProgressSyncer 提供等价能力，调用方可逐步迁移过来
 */

import connection from '@ohos.net.connection';
import { SoulEngine } from '../../../../core/distributed-soul/SoulEngine';
import { HttpClient } from '../../../../api/client/HttpClient';
import { PreferencesManager } from '../../../../core/persistence/PreferencesManager';

// ---------------------------------------------------------------------------
// 通用类型
// ---------------------------------------------------------------------------

/**
 * Entity 必须带 id + updatedAt，方便冲突解决与去重。
 * 客户端可在本地生成临时 id（uuid），服务端 push accept 时回传规范 id。
 */
export interface SyncableEntity {
  id: string;
  updatedAt: string;
  /** 软删除标记；push 时上报，server 据此回收 */
  deleted?: boolean;
}

export interface PushResult<T extends SyncableEntity> {
  accepted: T[];
  conflicts: ConflictItem<T>[];
}

export interface ConflictItem<T extends SyncableEntity> {
  local: T;
  server: T;
}

export interface SyncDelta<T extends SyncableEntity> {
  pulled: T[];
  pushed: T[];
  conflicts: ConflictItem<T>[];
}

export interface EntitySyncer<T extends SyncableEntity> {
  /** 必须唯一，作为路由 key + 持久化 namespace */
  entityType: string;
  /** 拉服务端增量 / 全量；since 不传时全量 */
  pull(since?: Date): Promise<T[]>;
  /** 推本地变更，返回 server accepted + 冲突列表 */
  push(items: T[]): Promise<PushResult<T>>;
  /**
   * 冲突解决：默认实现 LWW（updatedAt 大者胜）。
   * syncer 可覆盖做字段级合并（如 vocab-note.reviewCount 取 max）。
   */
  resolveConflict(local: T, server: T): T;
  /** 一次同步 round 完成回调（pulled/pushed/conflicts 都已应用） */
  onSync?: (delta: SyncDelta<T>) => void;
}

interface QueueEntry {
  entityType: string;
  /** 序列化后的 entity（避免泛型擦除带来的存储难题） */
  payload: string;
  retries: number;
  enqueuedAt: number;
}

// ---------------------------------------------------------------------------
// 调度参数
// ---------------------------------------------------------------------------

// W5: push debounce reduced to 300ms for tighter real-device sync; pull is event-driven.
const DEBOUNCE_MS = 300;
const BACKOFF_MS = [1_000, 2_000, 4_000, 8_000, 60_000];
const PERIODIC_TICK_MS = 30 * 60 * 1000; // 30 min
const IDLE_PULL_THRESHOLD_MS = 24 * 60 * 60 * 1000; // 24h
const QUEUE_PREF_KEY = 'sync_engine_queue_v1';
const LAST_PULL_PREF_KEY_PREFIX = 'sync_engine_last_pull_';

// ---------------------------------------------------------------------------
// SyncEngine
// ---------------------------------------------------------------------------

class SyncEngineImpl {
  // entityType -> syncer
  private syncers: Map<string, EntitySyncer<SyncableEntity>> = new Map();
  // entityType -> 待 push 队列（保留原始 entity，便于本地最新值合并）
  private queues: Map<string, Map<string, SyncableEntity>> = new Map();

  private debounceTimers: Map<string, number> = new Map();
  private retryTimers: Map<string, number> = new Map();
  private periodicTimer: number = -1;

  private online: boolean = true;
  private netHandle: connection.NetConnection | null = null;
  private inited: boolean = false;

  private conflictListeners: ((entityType: string, conflicts: ConflictItem<SyncableEntity>[]) => void)[] = [];
  /** SoulEngine subscription cleanup handles (one per registered syncer). */
  private soulUnsubscribers: Map<string, () => void> = new Map();

  // ─── 注册 ───────────────────────────────────────────────────────────────

  register<T extends SyncableEntity>(syncer: EntitySyncer<T>): void {
    this.syncers.set(syncer.entityType, syncer as unknown as EntitySyncer<SyncableEntity>);
    if (!this.queues.has(syncer.entityType)) {
      this.queues.set(syncer.entityType, new Map());
    }
  }

  /**
   * Wire this SyncEngine to a SoulEngine so that:
   *   1. Remote soul changes trigger event-driven pull (no debounce) for each domain.
   *   2. flush() additionally propagates pushed items into the soul for P2P broadcast.
   *
   * Call after register() and before init(). Safe to call multiple times (idempotent per entityType).
   * @since W5
   */
  connectSoul(engine: SoulEngine): void {
    this.syncers.forEach((_syncer, entityType) => {
      if (this.soulUnsubscribers.has(entityType)) return;
      const soulPath = `sync.${entityType}`;
      const unsub = engine.subscribe<SyncableEntity[]>(soulPath, (remoteItems) => {
        if (!Array.isArray(remoteItems) || remoteItems.length === 0) return;
        // Event-driven pull: remote soul change → write to syncer (if syncer supports onSync)
        const syncer = this.syncers.get(entityType);
        if (!syncer) return;
        syncer.onSync?.({ pulled: remoteItems, pushed: [], conflicts: [] });
      });
      this.soulUnsubscribers.set(entityType, unsub);
    });
  }

  // ─── 生命周期 ───────────────────────────────────────────────────────────

  async init(): Promise<void> {
    if (this.inited) return;
    this.inited = true;

    // 1. 恢复持久化队列
    await this.restoreQueue();

    // 2. 网络监听
    try {
      this.netHandle = connection.createNetConnection();
      this.netHandle.on('netAvailable', () => {
        this.online = true;
        this.flushAll();
      });
      this.netHandle.on('netUnavailable', () => { this.online = false; });
      this.netHandle.on('netLost', () => { this.online = false; });
      this.netHandle.register((err) => {
        if (err) console.warn(`SyncEngine net register failed: ${err.message}`);
      });
    } catch (e) {
      console.warn(`SyncEngine net listener init failed: ${(e as Error).message}`);
    }

    // 3. 周期 tick
    this.startPeriodicTick();

    // 4. 启动后对每个 syncer 判断是否需要全量 pull
    this.scheduleStartupPull();
  }

  /** 退出登录 / 切账号时清理：取消所有 timer，清空队列，清持久化。 */
  async reset(): Promise<void> {
    this.debounceTimers.forEach((t) => clearTimeout(t));
    this.debounceTimers.clear();
    this.retryTimers.forEach((t) => clearTimeout(t));
    this.retryTimers.clear();
    if (this.periodicTimer !== -1) {
      clearInterval(this.periodicTimer);
      this.periodicTimer = -1;
    }
    this.queues.forEach((m) => m.clear());
    // Clean up soul subscriptions.
    this.soulUnsubscribers.forEach((unsub) => { try { unsub(); } catch (_) { /* ignore */ } });
    this.soulUnsubscribers.clear();
    this.inited = false;
    await PreferencesManager.setString(QUEUE_PREF_KEY, '');
  }

  // ─── 客户端数据变更入口 ────────────────────────────────────────────────

  /**
   * 入队一条本地变更。同 (entityType, id) 合并，仅保留最新 entity。
   * debounce 5s 后真正 push。
   */
  enqueue<T extends SyncableEntity>(entityType: string, item: T): void {
    if (!this.syncers.has(entityType)) {
      console.warn(`SyncEngine.enqueue: unknown entityType ${entityType}`);
      return;
    }
    let q = this.queues.get(entityType);
    if (!q) {
      q = new Map();
      this.queues.set(entityType, q);
    }
    q.set(item.id, item);
    this.persistQueue();
    this.scheduleDebounce(entityType);
  }

  /** 立即推送某个 entity 类型的队列。 */
  async flush(entityType: string): Promise<void> {
    const t = this.debounceTimers.get(entityType);
    if (t !== undefined) {
      clearTimeout(t);
      this.debounceTimers.delete(entityType);
    }
    const rt = this.retryTimers.get(entityType);
    if (rt !== undefined) {
      clearTimeout(rt);
      this.retryTimers.delete(entityType);
    }

    if (!this.online) return;
    const q = this.queues.get(entityType);
    if (!q || q.size === 0) return;

    const syncer = this.syncers.get(entityType);
    if (!syncer) return;

    const items: SyncableEntity[] = [];
    q.forEach((v) => items.push(v));

    try {
      const result = await syncer.push(items);
      // accepted 移出队列
      for (const acc of result.accepted) {
        q.delete(acc.id);
      }
      // 冲突：调用 resolveConflict，把胜者更新本地 + 入队（如果是本地胜则重推）
      const resolvedDeltas: SyncableEntity[] = [];
      for (const c of result.conflicts) {
        const winner = syncer.resolveConflict(c.local, c.server);
        resolvedDeltas.push(winner);
        // 默认 LWW：如果服务端胜，移出队列；如果本地胜，保留入队下一轮
        if (winner.id === c.server.id && winner.updatedAt === c.server.updatedAt) {
          q.delete(c.local.id);
        }
      }
      if (result.conflicts.length > 0) {
        this.notifyConflicts(entityType, result.conflicts);
      }
      this.persistQueue();
      // W5 SoulBridge: broadcast accepted items to soul for P2P propagation.
      if (result.accepted.length > 0) {
        const engine = SoulEngine.getInstance();
        if (!engine.isFallbackMode) {
          engine.update(`sync.${entityType}`, result.accepted).catch(() => {/* best-effort */});
        }
      }
      syncer.onSync?.({
        pulled: [],
        pushed: result.accepted,
        conflicts: result.conflicts,
      });
    } catch (_err) {
      // 整批失败：对每个 entity 累加 retries，触发退避
      q.forEach((_v, _k) => { /* retries 不在 entity 内，只在 timer 计数中累加 */ });
      this.scheduleBackoffRetry(entityType);
    }
  }

  /** 推送所有 entity 类型的队列。 */
  async flushAll(): Promise<void> {
    const types: string[] = [];
    this.queues.forEach((_, k) => types.push(k));
    for (const t of types) {
      await this.flush(t);
    }
  }

  // ─── 拉取 ───────────────────────────────────────────────────────────────

  /**
   * 强制全量 / 增量 pull 单个 entity。
   * - since=null 全量
   * - since=Date 自该时间之后增量
   */
  async pull(entityType: string, since?: Date): Promise<SyncableEntity[]> {
    const syncer = this.syncers.get(entityType);
    if (!syncer) return [];
    if (!this.online) return [];

    try {
      const items = await syncer.pull(since);
      await PreferencesManager.setString(
        LAST_PULL_PREF_KEY_PREFIX + entityType,
        String(Date.now()),
      );
      syncer.onSync?.({ pulled: items, pushed: [], conflicts: [] });
      return items;
    } catch (e) {
      console.warn(`SyncEngine.pull(${entityType}) failed: ${(e as Error).message}`);
      return [];
    }
  }

  /** 全量 pull 所有 entity（应用启动 / 手动下拉刷新触发）。 */
  async pullAll(): Promise<void> {
    const types: string[] = [];
    this.syncers.forEach((_, k) => types.push(k));
    for (const t of types) {
      await this.pull(t);
    }
  }

  // ─── 冲突订阅 ───────────────────────────────────────────────────────────

  subscribeConflicts(
    cb: (entityType: string, conflicts: ConflictItem<SyncableEntity>[]) => void,
  ): () => void {
    this.conflictListeners.push(cb);
    return () => {
      const i = this.conflictListeners.indexOf(cb);
      if (i >= 0) this.conflictListeners.splice(i, 1);
    };
  }

  // ─── 调度内部 ──────────────────────────────────────────────────────────

  private scheduleDebounce(entityType: string): void {
    if (this.debounceTimers.has(entityType)) return;
    const t = setTimeout(() => {
      this.debounceTimers.delete(entityType);
      this.flush(entityType);
    }, DEBOUNCE_MS) as unknown as number;
    this.debounceTimers.set(entityType, t);
  }

  private scheduleBackoffRetry(entityType: string): void {
    if (this.retryTimers.has(entityType)) return;
    // 简化：用队列长度做指数挡位（更精细的 per-entity retries 可后续加）
    const q = this.queues.get(entityType);
    const attempt = q ? Math.min(q.size, BACKOFF_MS.length - 1) : 0;
    const delay = BACKOFF_MS[attempt];
    const t = setTimeout(() => {
      this.retryTimers.delete(entityType);
      this.flush(entityType);
    }, delay) as unknown as number;
    this.retryTimers.set(entityType, t);
  }

  private startPeriodicTick(): void {
    if (this.periodicTimer !== -1) return;
    this.periodicTimer = setInterval(() => {
      if (!this.online) return;
      // 每 tick：先 push 残留队列，再增量 pull 各 entity
      this.flushAll().then(() => this.pullAll());
    }, PERIODIC_TICK_MS) as unknown as number;
  }

  private async scheduleStartupPull(): Promise<void> {
    const now = Date.now();
    const types: string[] = [];
    this.syncers.forEach((_, k) => types.push(k));
    for (const t of types) {
      const lastRaw = await PreferencesManager.getString(LAST_PULL_PREF_KEY_PREFIX + t, '');
      const last = lastRaw ? parseInt(lastRaw, 10) : 0;
      if (now - last > IDLE_PULL_THRESHOLD_MS) {
        // 全量
        this.pull(t);
      } else {
        // 增量
        this.pull(t, new Date(last));
      }
    }
  }

  private notifyConflicts(entityType: string, conflicts: ConflictItem<SyncableEntity>[]): void {
    for (const cb of this.conflictListeners) {
      try { cb(entityType, conflicts); } catch (_) { /* ignore */ }
    }
  }

  // ─── 持久化 ────────────────────────────────────────────────────────────

  private persistQueue(): void {
    const arr: QueueEntry[] = [];
    this.queues.forEach((q, entityType) => {
      q.forEach((entity) => {
        arr.push({
          entityType,
          payload: JSON.stringify(entity),
          retries: 0,
          enqueuedAt: Date.now(),
        });
      });
    });
    PreferencesManager.setString(QUEUE_PREF_KEY, JSON.stringify(arr));
  }

  private async restoreQueue(): Promise<void> {
    const raw = await PreferencesManager.getString(QUEUE_PREF_KEY, '');
    if (!raw) return;
    try {
      const list = JSON.parse(raw) as QueueEntry[];
      for (const e of list) {
        const entity = JSON.parse(e.payload) as SyncableEntity;
        let q = this.queues.get(e.entityType);
        if (!q) {
          q = new Map();
          this.queues.set(e.entityType, q);
        }
        q.set(entity.id, entity);
      }
    } catch (_) {
      // ignore corrupt blob
    }
  }
}

// ---------------------------------------------------------------------------
// 默认 LWW 冲突解决：updatedAt 字符串 ISO 8601 时序比较
// ---------------------------------------------------------------------------

export function lastWriteWins<T extends SyncableEntity>(local: T, server: T): T {
  const lt = Date.parse(local.updatedAt) || 0;
  const st = Date.parse(server.updatedAt) || 0;
  return st > lt ? server : local;
}

/**
 * 通用 server-cn 同步 API（pull/push）。Syncer 实现按需调用。
 * 服务端 endpoint 待 W11+ 实现；本任务先用占位 path。
 */
export class SyncApi {
  static async pullEntity<T extends SyncableEntity>(
    entityType: string,
    since?: Date,
  ): Promise<T[]> {
    interface Resp { items: T[]; serverNow?: string; }
    const body: Record<string, unknown> = { entityType };
    if (since) body.since = since.toISOString();
    const res = await HttpClient.post<Resp>('/api/v1/sync/pull', body);
    return res.items ?? [];
  }

  static pushEntity<T extends SyncableEntity>(
    entityType: string,
    items: T[],
  ): Promise<PushResult<T>> {
    return HttpClient.post<PushResult<T>>('/api/v1/sync/push', { entityType, items });
  }
}

/** 单例 */
export const SyncEngine = new SyncEngineImpl();
