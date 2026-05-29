import { RealtimeChannel } from './RealtimeChannel';
import type { RealtimePayloads } from './SyncDomain';

/**
 * Syncfusion 统一对外 API。
 *
 * 用法：
 *   await SyncCoordinator.realtime.position.set({ bookId, chapterId, pageIdx, charOffset });
 *   const cur = await SyncCoordinator.realtime.position.get();
 *   const unsub = SyncCoordinator.realtime.position.observe((p) => updateUI(p));
 *
 * P0-B.2 之后扩展：
 *   await SyncCoordinator.persistent.progress.queue(bookId, dto);
 *   await SyncCoordinator.persistent.bookmark.upsert(bm);
 *
 * 与现有 ReadingSoul / ProgressSync 并存；新代码优先用 Coordinator，
 * 老调用方按需迁移，不强制一次性替换。
 */

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

export const SyncCoordinator: {
  realtime: {
    position: RealtimeDomainHandle<RealtimePayloads['position']>;
    selection: RealtimeDomainHandle<RealtimePayloads['selection']>;
    device: RealtimeDomainHandle<RealtimePayloads['device']>;
  };
  // persistent: { progress, bookmark, highlight, bookshelf, history, session }  ← P0-B.2 填充
} = {
  realtime: {
    position: makeRealtimeHandle('position'),
    selection: makeRealtimeHandle('selection'),
    device: makeRealtimeHandle('device'),
  },
};
