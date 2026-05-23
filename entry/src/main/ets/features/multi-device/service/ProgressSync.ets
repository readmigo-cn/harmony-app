/**
 * ProgressSync.ets — W7-C6 阅读进度云端同步服务
 *
 * 单例。职责：
 *   - 维护内存队列 + 持久化备份队列（崩溃恢复）
 *   - 防抖 5s：同 bookId 的多次 update 合并，仅推送最新
 *   - 网络不可用时挂起，恢复后自动 flush
 *   - 推送失败指数退避：1s / 2s / 4s / 8s / 16s / 32s / 60s（封顶）
 *   - pull(bookId) 拉云端最新进度，与本地比较 lastUpdatedAt 解冲突
 *   - subscribeToConflicts：本地与云端 percent 偏差 > 5% 时回调
 *
 * 调用约束：
 *   - 调用方应在 EntryAbility.onCreate 调 init()
 *   - flush() 适合在 onForeground / onBackground / 退出登录时触发
 */

import connection from '@ohos.net.connection';
import { ReadingApi } from '../../../api/reading/ReadingApi';
import { ReadingProgressDto } from '../../../model/ReadingProgress';
import { PreferencesManager } from '../../../core/persistence/PreferencesManager';
import { StoreKeys } from '../../../store/StoreKeys';
import { ReadingStore } from '../../../store/ReadingStore';

/** 队列条目：用 bookId 作为去重 key，覆盖旧值。 */
interface QueueEntry {
  bookId: string;
  dto: ReadingProgressDto;
  /** 本地写入时间（ms） */
  localTs: number;
  /** 已重试次数 */
  retries: number;
}

/** 冲突回调：local + server 都给出，UI 自行决策。 */
export interface ProgressConflict {
  bookId: string;
  local: ReadingProgressDto;
  server: ReadingProgressDto;
  diffPercent: number;
}

export type ConflictCallback = (c: ProgressConflict) => void;

const DEBOUNCE_MS = 5_000;
const BACKOFF_MS = [1_000, 2_000, 4_000, 8_000, 16_000, 32_000, 60_000];
const CONFLICT_THRESHOLD = 5; // percent

class ProgressSyncImpl {
  /** 内存队列：bookId -> QueueEntry */
  private queue: Map<string, QueueEntry> = new Map();
  /** debounce 定时器 */
  private debounceTimer: number = -1;
  /** 推送失败的退避定时器 */
  private retryTimer: number = -1;
  /** 当前是否在线（默认乐观为 true） */
  private online: boolean = true;
  /** 网络监听句柄 */
  private netHandle: connection.NetConnection | null = null;
  /** 冲突订阅者 */
  private conflictListeners: ConflictCallback[] = [];
  /** 是否已 init */
  private inited: boolean = false;

  /** 启动时调一次：恢复持久化队列 + 注册网络监听。 */
  async init(): Promise<void> {
    if (this.inited) return;
    this.inited = true;
    // 恢复队列
    const raw = await PreferencesManager.getString(StoreKeys.READING_PROGRESS_QUEUE, '');
    if (raw.length > 0) {
      try {
        const list = JSON.parse(raw) as QueueEntry[];
        for (const e of list) {
          this.queue.set(e.bookId, e);
        }
      } catch (_) {
        // ignore corrupt blob
      }
    }
    // 注册网络监听（容错：模拟器/低权限可能失败）
    try {
      this.netHandle = connection.createNetConnection();
      this.netHandle.on('netAvailable', () => {
        this.online = true;
        this.flush();
      });
      this.netHandle.on('netUnavailable', () => {
        this.online = false;
      });
      this.netHandle.on('netLost', () => {
        this.online = false;
      });
      this.netHandle.register((err) => {
        if (err) {
          console.warn(`ProgressSync net register failed: ${err.message}`);
        }
      });
    } catch (e) {
      console.warn(`ProgressSync net listener init failed: ${(e as Error).message}`);
    }
    // 若启动时恢复出未推送项，尝试 flush 一次
    if (this.queue.size > 0) {
      this.scheduleDebounce();
    }
  }

  /** 注册冲突回调。返回反订阅函数。 */
  subscribeToConflicts(cb: ConflictCallback): () => void {
    this.conflictListeners.push(cb);
    return (): void => {
      const idx = this.conflictListeners.indexOf(cb);
      if (idx >= 0) this.conflictListeners.splice(idx, 1);
    };
  }

  /** 入队一次更新；同 bookId 合并到最新。debounce 5s 后真正 flush。 */
  queueUpdate(bookId: string, progress: ReadingProgressDto): void {
    if (!bookId) return;
    const existing = this.queue.get(bookId);
    const next: QueueEntry = {
      bookId,
      dto: progress,
      localTs: Date.now(),
      retries: existing?.retries ?? 0,
    };
    this.queue.set(bookId, next);
    this.persistQueue();
    this.scheduleDebounce();
  }

  /** 立刻把队列中的所有更新推送到服务器（不等 debounce）。 */
  async flush(): Promise<void> {
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    if (!this.online) {
      // 等网络恢复
      return;
    }
    if (this.queue.size === 0) return;

    const entries: QueueEntry[] = [];
    this.queue.forEach((v) => entries.push(v));

    let anyFailed = false;
    for (const e of entries) {
      try {
        await ReadingApi.updateProgress(e.bookId, e.dto);
        // 推送成功移除
        this.queue.delete(e.bookId);
        ReadingStore.setLastSyncedAt(e.bookId, Date.now());
      } catch (_err) {
        // 失败保留 + 累加重试
        e.retries += 1;
        anyFailed = true;
      }
    }
    this.persistQueue();

    if (anyFailed) {
      this.scheduleBackoffRetry();
    }
  }

  /**
   * 拉取云端最新进度。若本地有进度且 percent 偏差 > 5%，触发 conflict 回调，
   * 由 UI 决策（默认仅本地比 server 旧时返回 server）。
   */
  async pull(bookId: string): Promise<ReadingProgressDto | null> {
    if (!bookId) return null;
    let server: ReadingProgressDto | null = null;
    try {
      server = await ReadingApi.getProgress(bookId);
    } catch (_e) {
      return null;
    }
    if (!server) return null;
    ReadingStore.setLastSyncedAt(bookId, Date.now());

    // 与本地（队列内最新 / 兜底取 ReadingStore.getLastProgress）比较
    const queued = this.queue.get(bookId);
    const localProgress = queued?.dto ?? this.buildLocalDtoFromStore(bookId);
    if (localProgress) {
      const diff = Math.abs((localProgress.percent ?? 0) - (server.percent ?? 0));
      if (diff > CONFLICT_THRESHOLD) {
        // 冲突：本地更新还在队列里 / 没推上去；server 比本地大幅落后或超前
        const localTs = this.parseTs(localProgress.updatedAt) ?? queued?.localTs ?? 0;
        const serverTs = this.parseTs(server.updatedAt) ?? 0;
        const conflict: ProgressConflict = {
          bookId,
          local: localProgress,
          server,
          diffPercent: diff,
        };
        this.conflictListeners.forEach((cb) => {
          try { cb(conflict); } catch (_e) { /* ignore */ }
        });
        // server 更新（updatedAt 更晚）则 server 胜出，覆盖队列
        if (serverTs > localTs) {
          this.queue.delete(bookId);
          this.persistQueue();
          return server;
        }
        // 本地更新，保持队列；让调用方继续用本地
        return localProgress;
      }
    }
    return server;
  }

  // ─── internals ──────────────────────────────────────────────

  private scheduleDebounce(): void {
    if (this.debounceTimer !== -1) return;
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = -1;
      this.flush();
    }, DEBOUNCE_MS) as unknown as number;
  }

  private scheduleBackoffRetry(): void {
    // 取队列中最大 retries 决定退避档位
    let maxRetry = 0;
    this.queue.forEach((e) => {
      if (e.retries > maxRetry) maxRetry = e.retries;
    });
    const idx = Math.min(maxRetry, BACKOFF_MS.length - 1);
    const delay = BACKOFF_MS[idx];
    if (this.retryTimer !== -1) return;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1;
      this.flush();
    }, delay) as unknown as number;
  }

  /** 写持久化队列：dump 当前所有条目。 */
  private persistQueue(): void {
    const arr: QueueEntry[] = [];
    this.queue.forEach((v) => arr.push(v));
    PreferencesManager.setString(StoreKeys.READING_PROGRESS_QUEUE, JSON.stringify(arr));
  }

  /** 从 ReadingStore 拼一个 DTO 用于冲突比较（仅当本地无队列项时）。 */
  private buildLocalDtoFromStore(bookId: string): ReadingProgressDto | null {
    const local = ReadingStore.getLastProgress();
    if (!local || local.bookId !== bookId) return null;
    return {
      bookId: local.bookId,
      chapterIndex: parseInt(local.chapterId, 10) || 0,
      percent: local.percent,
      updatedAt: new Date(local.updatedAt).toISOString(),
    };
  }

  private parseTs(iso?: string): number | null {
    if (!iso) return null;
    const t = Date.parse(iso);
    return isNaN(t) ? null : t;
  }
}

/** 单例导出。 */
export const ProgressSync = new ProgressSyncImpl();
