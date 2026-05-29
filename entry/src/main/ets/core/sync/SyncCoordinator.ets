import { RealtimeChannel } from './RealtimeChannel';
import { PersistentChannel } from './PersistentChannel';
import { ProgressAdapter } from './ProgressAdapter';
import type { RealtimePayloads, PersistentDomainKey } from './SyncDomain';
import type { PersistentConflict, ConflictListener } from './PersistentChannel';
import type { ReadingProgressDto } from '../../model/ReadingProgress';

/**
 * Syncfusion 统一对外 API。
 *
 * 用法：
 *   await SyncCoordinator.realtime.position.set({ bookId, chapterId, pageIdx, charOffset });
 *   const cur = await SyncCoordinator.realtime.position.get();
 *   const unsub = SyncCoordinator.realtime.position.observe((p) => updateUI(p));
 *
 *   await SyncCoordinator.persistent.progress.init();
 *   SyncCoordinator.persistent.progress.upsert(progressDto);
 *   await SyncCoordinator.persistent.progress.flush();
 *
 * P0-B.3 之后扩展 persistent.bookmark / .highlight / .bookshelf / .history / .session
 */

// ---------- Realtime handles ----------

interface RealtimeDomainHandle<TPayload> {
  set(value: TPayload): Promise<void>;
  get(): Promise<TPayload | null>;
  observe(listener: (value: TPayload) => void): () => void;
}

function makeRealtimeHandle<K extends keyof RealtimePayloads>(
  domain: K,
): RealtimeDomainHandle<RealtimePayloads[K]> {
  return {
    set: (v: RealtimePayloads[K]): Promise<void> => RealtimeChannel.set(domain, v),
    get: (): Promise<RealtimePayloads[K] | null> => RealtimeChannel.get(domain),
    observe: (cb: (v: RealtimePayloads[K]) => void): (() => void) =>
      RealtimeChannel.observe(domain, cb),
  };
}

// ---------- Persistent handles ----------

interface PersistentDomainHandle<TPayload> {
  init(): Promise<void>;
  upsert(payload: TPayload): void;
  delete(id: string): void;
  dropQueued(id: string): void;
  flush(): Promise<void>;
  pull(id: string): Promise<TPayload | null>;
  peek(id: string): TPayload | null;
  subscribeToConflicts(cb: ConflictListener<TPayload>): () => void;
  dispatchConflict(c: PersistentConflict<TPayload>): void;
  pendingCount(): number;
}

function makePersistentHandle<TKey extends PersistentDomainKey, TPayload>(
  channel: PersistentChannel<TKey, TPayload>,
): PersistentDomainHandle<TPayload> {
  return {
    init: (): Promise<void> => channel.init(),
    upsert: (p: TPayload): void => channel.upsert(p),
    delete: (id: string): void => channel.delete(id),
    dropQueued: (id: string): void => channel.dropQueued(id),
    flush: (): Promise<void> => channel.flush(),
    pull: (id: string): Promise<TPayload | null> => channel.pull(id),
    peek: (id: string): TPayload | null => channel.peek(id),
    subscribeToConflicts: (cb: ConflictListener<TPayload>): (() => void) =>
      channel.subscribeToConflicts(cb),
    dispatchConflict: (c: PersistentConflict<TPayload>): void => channel.dispatchConflict(c),
    pendingCount: (): number => channel.pendingCount(),
  };
}

// ---------- Channel instances ----------

const progressChannel: PersistentChannel<'progress', ReadingProgressDto> =
  new PersistentChannel<'progress', ReadingProgressDto>('progress', ProgressAdapter);

// ---------- Public API ----------

export const SyncCoordinator: {
  realtime: {
    position: RealtimeDomainHandle<RealtimePayloads['position']>;
    selection: RealtimeDomainHandle<RealtimePayloads['selection']>;
    device: RealtimeDomainHandle<RealtimePayloads['device']>;
  };
  persistent: {
    progress: PersistentDomainHandle<ReadingProgressDto>;
    // bookmark / highlight / bookshelf / history / session ← P0-B.3+
  };
} = {
  realtime: {
    position: makeRealtimeHandle('position'),
    selection: makeRealtimeHandle('selection'),
    device: makeRealtimeHandle('device'),
  },
  persistent: {
    progress: makePersistentHandle(progressChannel),
  },
};
