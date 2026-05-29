import connection from '@ohos.net.connection';
import { PreferencesManager, NamespacedPreferences } from '../persistence/PreferencesManager';
import type { PersistentDomainKey, PersistentOp } from './SyncDomain';

/**
 * 通用同步队列（抽取自 ProgressSync W7-C6 实现）。
 *
 * 职责：
 *  - 内存 Map + 持久化磁盘（每 domain 一个 PreferencesManager namespace）
 *  - debounce 5s：同 id 多次 enqueue 合并到最新
 *  - 网络监听（NetMonitor 全局单例，所有 SyncQueue 共享）
 *  - 失败指数退避：1s / 2s / 4s / 8s / 16s / 32s / 60s（封顶）
 *  - flush()：立即推送（不等 debounce）
 *  - peek(id)：读当前队列项，不触发推送
 *  - drop(id)：从队列移除，不入队 DELETE op（用于"服务端胜"冲突解决后）
 *
 * 通过 push 回调与外部 push API 解耦：SyncQueue 不知道 ReadingApi 存在。
 */

const DEBOUNCE_MS = 5_000;
const BACKOFF_MS: number[] = [1_000, 2_000, 4_000, 8_000, 16_000, 32_000, 60_000];
const QUEUE_KEY = 'queue_v1';

export interface QueueEntry<TPayload> {
  op: PersistentOp<PersistentDomainKey, TPayload>;
  retries: number;
}

export type QueuePushFn<TPayload> =
  (op: PersistentOp<PersistentDomainKey, TPayload>) => Promise<void>;

export type QueueAfterPushFn<TPayload> =
  (op: PersistentOp<PersistentDomainKey, TPayload>) => void;

export class SyncQueue<TPayload> {
  private readonly domain: PersistentDomainKey;
  private readonly pushFn: QueuePushFn<TPayload>;
  private readonly afterPushFn: QueueAfterPushFn<TPayload> | null;
  private readonly ns: NamespacedPreferences;
  private items: Map<string, QueueEntry<TPayload>> = new Map();
  private debounceTimer: number = -1;
  private retryTimer: number = -1;
  private inited: boolean = false;
  private flushOnAvailUnsub: (() => void) | null = null;

  constructor(
    domain: PersistentDomainKey,
    pushFn: QueuePushFn<TPayload>,
    afterPushFn?: QueueAfterPushFn<TPayload>,
  ) {
    this.domain = domain;
    this.pushFn = pushFn;
    this.afterPushFn = afterPushFn ?? null;
    this.ns = PreferencesManager.createNamespace(`sync_queue_${domain}`);
  }

  async init(): Promise<void> {
    if (this.inited) return;
    this.inited = true;
    NetMonitor.ensure();
    const list = await this.ns.getArray<QueueEntry<TPayload>>(QUEUE_KEY, []);
    for (let i = 0; i < list.length; i++) {
      this.items.set(list[i].op.id, list[i]);
    }
    this.flushOnAvailUnsub = NetMonitor.onAvailable(() => { this.flush(); });
    if (this.items.size > 0) this.scheduleDebounce();
  }

  enqueue(op: PersistentOp<PersistentDomainKey, TPayload>): void {
    const existing = this.items.get(op.id);
    const entry: QueueEntry<TPayload> = {
      op,
      retries: existing ? existing.retries : 0,
    };
    this.items.set(op.id, entry);
    this.persist();
    this.scheduleDebounce();
  }

  /** 读队列当前项（不触发推送）。 */
  peek(id: string): TPayload | null {
    const e = this.items.get(id);
    return e && e.op.payload !== undefined ? e.op.payload : null;
  }

  /** 从队列移除项；不入队 DELETE op（与 enqueue(delete) 不同）。 */
  drop(id: string): void {
    if (this.items.delete(id)) this.persist();
  }

  async flush(): Promise<void> {
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    if (!NetMonitor.online) return;
    if (this.items.size === 0) return;

    const snapshot: QueueEntry<TPayload>[] = [];
    this.items.forEach((v) => snapshot.push(v));

    let anyFailed = false;
    for (let i = 0; i < snapshot.length; i++) {
      const e = snapshot[i];
      try {
        await this.pushFn(e.op);
        this.items.delete(e.op.id);
        if (this.afterPushFn) this.afterPushFn(e.op);
      } catch (_err) {
        e.retries += 1;
        anyFailed = true;
      }
    }
    this.persist();
    if (anyFailed) this.scheduleBackoff();
  }

  size(): number { return this.items.size; }

  dispose(): void {
    if (this.flushOnAvailUnsub) {
      this.flushOnAvailUnsub();
      this.flushOnAvailUnsub = null;
    }
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  // ---------- internals ----------

  private scheduleDebounce(): void {
    if (this.debounceTimer !== -1) return;
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = -1;
      this.flush();
    }, DEBOUNCE_MS) as unknown as number;
  }

  private scheduleBackoff(): void {
    let maxRetry = 0;
    this.items.forEach((e) => { if (e.retries > maxRetry) maxRetry = e.retries; });
    const idx = Math.min(maxRetry, BACKOFF_MS.length - 1);
    if (this.retryTimer !== -1) return;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1;
      this.flush();
    }, BACKOFF_MS[idx]) as unknown as number;
  }

  private persist(): void {
    const arr: QueueEntry<TPayload>[] = [];
    this.items.forEach((v) => arr.push(v));
    this.ns.setArray<QueueEntry<TPayload>>(QUEUE_KEY, arr);
  }
}

// ---------- 全局网络状态监控（多 SyncQueue 共享一个监听） ----------

class NetMonitorImpl {
  online: boolean = true;
  private inited: boolean = false;
  private handle: connection.NetConnection | null = null;
  private listeners: Array<() => void> = [];

  ensure(): void {
    if (this.inited) return;
    this.inited = true;
    try {
      this.handle = connection.createNetConnection();
      this.handle.on('netAvailable', () => {
        this.online = true;
        this.notify();
      });
      this.handle.on('netUnavailable', () => { this.online = false; });
      this.handle.on('netLost', () => { this.online = false; });
      this.handle.register((err) => {
        if (err) console.warn(`NetMonitor register failed: ${err.message}`);
      });
    } catch (e) {
      console.warn(`NetMonitor init failed: ${(e as Error).message}`);
    }
  }

  onAvailable(cb: () => void): () => void {
    this.listeners.push(cb);
    return (): void => {
      const i = this.listeners.indexOf(cb);
      if (i >= 0) this.listeners.splice(i, 1);
    };
  }

  private notify(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      try { this.listeners[i](); } catch (_e) { /* swallow */ }
    }
  }
}

export const NetMonitor = new NetMonitorImpl();
