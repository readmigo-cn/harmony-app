import { ReadingApi } from '../../api/reading/ReadingApi';
import { ReadingProgressDto } from '../../model/ReadingProgress';
import { ReadingStore } from '../../store/ReadingStore';
import type { DomainAdapter } from './PersistentChannel';
import type { PersistentOp, PersistentDomainKey } from './SyncDomain';

/**
 * Progress 域适配器：把 PersistentChannel 与 ReadingApi 桥接。
 *
 * 行为对齐 ProgressSync W7-C6：
 *  - upsert → PATCH /reading/progress/:bookId（通过 ReadingApi.updateProgress）
 *  - pull   → GET   /reading/progress/:bookId
 *  - delete: 后端无对应 endpoint，no-op（进度只能更新不能"删除"）
 *  - afterPush: 设置 ReadingStore.setLastSyncedAt（保留旧 side-effect）
 */
export const ProgressAdapter: DomainAdapter<ReadingProgressDto> = {
  idOf(dto: ReadingProgressDto): string {
    return dto.bookId;
  },

  async push(op: PersistentOp<PersistentDomainKey, ReadingProgressDto>): Promise<void> {
    if (op.kind === 'upsert' && op.payload) {
      // ReadingApi.updateProgress 期望完整 DTO；与 ProgressSync 旧调用一致
      await ReadingApi.updateProgress(op.payload.bookId, op.payload);
      return;
    }
    // delete: progress 域无意义；静默 ack 使队列项被移除
  },

  async pull(id: string): Promise<ReadingProgressDto | null> {
    try {
      return await ReadingApi.getProgress(id);
    } catch (_e) {
      return null;
    }
  },

  afterPush(op: PersistentOp<PersistentDomainKey, ReadingProgressDto>): void {
    const bookId = op.payload?.bookId ?? op.id;
    ReadingStore.setLastSyncedAt(bookId, Date.now());
  },
};
