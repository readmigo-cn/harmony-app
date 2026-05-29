/**
 * ProgressSync.ets — W7-C6 阅读进度云端同步服务（P0-B.2 改造）
 *
 * 单例，public API 与改造前**字节兼容**——所有现有调用方（EntryAbility /
 * AudioAbility / Reader 等）零修改：
 *   - init()
 *   - subscribeToConflicts(cb)
 *   - queueUpdate(bookId, progress)
 *   - flush()
 *   - pull(bookId)
 *
 * 内部实现委托到 SyncCoordinator.persistent.progress（PersistentChannel）：
 *   - 队列 / debounce / 网络监听 / 退避全部由 Syncfusion 框架统一管理
 *   - 进度域特有的冲突检测逻辑（5% percent threshold + updatedAt 比较）
 *     保留在本层，因为它不属于 PersistentChannel 的通用职责
 *
 * 此文件是迁移过渡层；新代码应直接用 SyncCoordinator.persistent.progress。
 * 老调用方逐步迁移后可删除本 wrapper。
 */

import { ReadingProgressDto } from '../../../model/ReadingProgress';
import { ReadingStore } from '../../../store/ReadingStore';
import { SyncCoordinator } from '../../../core/sync';

/** 冲突回调结构（保留旧 shape，外部 import 此类型的调用方零破坏）。 */
export interface ProgressConflict {
  bookId: string;
  local: ReadingProgressDto;
  server: ReadingProgressDto;
  diffPercent: number;
}

export type ConflictCallback = (c: ProgressConflict) => void;

const CONFLICT_THRESHOLD = 5; // percent

class ProgressSyncImpl {
  private conflictListeners: ConflictCallback[] = [];
  private inited: boolean = false;

  /** 启动时调一次：底层 channel.init() 恢复持久化队列 + 注册网络监听。 */
  async init(): Promise<void> {
    if (this.inited) return;
    this.inited = true;
    await SyncCoordinator.persistent.progress.init();
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
    SyncCoordinator.persistent.progress.upsert(progress);
  }

  /** 立刻把队列中的所有更新推送到服务器（不等 debounce）。 */
  async flush(): Promise<void> {
    await SyncCoordinator.persistent.progress.flush();
  }

  /**
   * 拉取云端最新进度；本地 percent 偏差 > 5% 触发冲突回调。
   * server.updatedAt > local.updatedAt 时 server 胜（队列被 dropQueued）；
   * 否则本地胜（保留队列，返回 local）。
   */
  async pull(bookId: string): Promise<ReadingProgressDto | null> {
    if (!bookId) return null;
    const server = await SyncCoordinator.persistent.progress.pull(bookId);
    if (!server) return null;
    ReadingStore.setLastSyncedAt(bookId, Date.now());

    const queued = SyncCoordinator.persistent.progress.peek(bookId);
    const localProgress = queued ?? this.buildLocalDtoFromStore(bookId);
    if (localProgress) {
      const diff = Math.abs((localProgress.percent ?? 0) - (server.percent ?? 0));
      if (diff > CONFLICT_THRESHOLD) {
        const localTs = this.parseTs(localProgress.updatedAt) ?? 0;
        const serverTs = this.parseTs(server.updatedAt) ?? 0;
        const conflict: ProgressConflict = {
          bookId,
          local: localProgress,
          server,
          diffPercent: diff,
        };
        // 通知本层订阅者（旧 API）
        this.conflictListeners.forEach((cb) => {
          try { cb(conflict); } catch (_e) { /* ignore */ }
        });
        // 同时分发到 channel 订阅者（新 API；B.3+ 可能有别的订阅者）
        SyncCoordinator.persistent.progress.dispatchConflict({
          domain: 'progress',
          id: bookId,
          local: localProgress,
          server,
        });
        if (serverTs > localTs) {
          // server 胜：清队列（不入队 delete），返 server
          SyncCoordinator.persistent.progress.dropQueued(bookId);
          return server;
        }
        // 本地胜：保留队列，返 local
        return localProgress;
      }
    }
    return server;
  }

  // ---------- internals ----------

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
