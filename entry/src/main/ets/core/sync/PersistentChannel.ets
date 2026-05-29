import { SyncQueue } from './SyncQueue';
import type { PersistentDomainKey, PersistentOp } from './SyncDomain';

/**
 * 域适配器：每个 persistent domain 实现一份，提供：
 *  - idOf: 队列去重 key（如 bookId、bookmarkId）
 *  - push: 云端写（CRUD by op.kind）
 *  - pull: 云端读单条（可选）
 *  - afterPush: 推送成功后的本地副作用（如 ReadingStore.setLastSyncedAt）
 *
 * Channel 不知道任何 API 细节；adapter 是桥。
 */
export interface DomainAdapter<TPayload> {
  idOf(payload: TPayload): string;
  push(op: PersistentOp<PersistentDomainKey, TPayload>): Promise<void>;
  pull?(id: string): Promise<TPayload | null>;
  afterPush?(op: PersistentOp<PersistentDomainKey, TPayload>): void;
}

/** 冲突描述（adapter 不主动检测；由 wrapper / 调用方决定何时触发）。 */
export interface PersistentConflict<TPayload> {
  domain: PersistentDomainKey;
  id: string;
  local: TPayload;
  server: TPayload;
}

export type ConflictListener<TPayload> = (c: PersistentConflict<TPayload>) => void;

/**
 * 持久同步通道：泛型化的 Whispersync-pattern。
 *
 * 用法（B.2 阶段 progress 实例化）：
 *   const channel = new PersistentChannel<'progress', ReadingProgressDto>(
 *     'progress', ProgressAdapter,
 *   );
 *   await channel.init();
 *   channel.upsert(progressDto);
 *   await channel.flush();
 *
 * 冲突检测：不在通道内做；由 wrapper（如 ProgressSync）调 peek + pull
 * 自行比较后调 dispatchConflict 触发监听器。
 */
export class PersistentChannel<TKey extends PersistentDomainKey, TPayload> {
  private readonly domain: TKey;
  private readonly adapter: DomainAdapter<TPayload>;
  private readonly queue: SyncQueue<TPayload>;
  private conflictListeners: Set<ConflictListener<TPayload>> = new Set<ConflictListener<TPayload>>();
  private inited: boolean = false;

  constructor(domain: TKey, adapter: DomainAdapter<TPayload>) {
    this.domain = domain;
    this.adapter = adapter;
    const afterPush = adapter.afterPush;
    this.queue = new SyncQueue<TPayload>(
      domain,
      (op) => adapter.push(op),
      afterPush ? (op) => afterPush(op) : undefined,
    );
  }

  async init(): Promise<void> {
    if (this.inited) return;
    this.inited = true;
    await this.queue.init();
  }

  /** 入队 upsert；payload.id 作为去重 key。 */
  upsert(payload: TPayload): void {
    const op: PersistentOp<TKey, TPayload> = {
      domain: this.domain,
      kind: 'upsert',
      id: this.adapter.idOf(payload),
      payload,
      localTs: Date.now(),
    };
    this.queue.enqueue(op);
  }

  /** 入队 delete op；服务端有对应 endpoint 时 push 会真删。 */
  delete(id: string): void {
    const op: PersistentOp<TKey, TPayload> = {
      domain: this.domain,
      kind: 'delete',
      id,
      localTs: Date.now(),
    };
    this.queue.enqueue(op);
  }

  /** 从队列移除项，不入队 delete op。"服务端胜"冲突解决后清理队列用。 */
  dropQueued(id: string): void {
    this.queue.drop(id);
  }

  async flush(): Promise<void> {
    return this.queue.flush();
  }

  async pull(id: string): Promise<TPayload | null> {
    if (!this.adapter.pull) return null;
    try {
      return await this.adapter.pull(id);
    } catch (_e) {
      return null;
    }
  }

  /** 读队列当前项，不触发推送。冲突检测用。 */
  peek(id: string): TPayload | null {
    return this.queue.peek(id);
  }

  subscribeToConflicts(cb: ConflictListener<TPayload>): () => void {
    this.conflictListeners.add(cb);
    return (): void => { this.conflictListeners.delete(cb); };
  }

  /** Wrapper 用：检测出冲突后调此方法分发。 */
  dispatchConflict(c: PersistentConflict<TPayload>): void {
    this.conflictListeners.forEach((cb) => {
      try { cb(c); } catch (_e) { /* swallow */ }
    });
  }

  pendingCount(): number {
    return this.queue.size();
  }
}
