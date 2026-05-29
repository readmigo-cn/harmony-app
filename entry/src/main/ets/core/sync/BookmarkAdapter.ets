import { BookmarkApi, BookmarkDto } from '../../api/reading/BookmarkApi';
import { Bookmark } from '../persistence/repositories/BookmarksRepository';
import type { DomainAdapter } from './PersistentChannel';
import type { PersistentOp, PersistentDomainKey } from './SyncDomain';

/**
 * Bookmark 域同步适配器：把 syncfusion PersistentChannel 与 BookmarkApi 桥接。
 *
 * 行为：
 *  - upsert → BookmarkApi.upsert（端点未就绪时 no-op 成功，本地 Repository 已落盘）
 *  - delete → BookmarkApi.delete
 *  - pull   → BookmarkApi.getById；server DTO 映射回 client Bookmark
 *
 * 当 BookmarkApi.ENDPOINT_AVAILABLE=false 时：push 静默 ack，队列正常清空；
 * P1-B 翻 true 后所有新写入立刻真实 sync。已存在的旧 bookmark 需走一次性
 * catch-up（在 P1-B 阶段实现 BookmarkSyncCatchupService）。
 */

function clientToDto(b: Bookmark): BookmarkDto {
  return {
    id: b.id,
    bookId: b.bookId,
    chapterId: b.chapterId,
    pageIdx: b.pageIdx,
    label: b.label === null ? undefined : b.label,
    createdAt: new Date(b.createdAt).toISOString(),
  };
}

function dtoToClient(dto: BookmarkDto): Bookmark {
  const ts = Date.parse(dto.createdAt);
  return {
    id: dto.id,
    userId: '',  // server 端 user 已通过 token 携带；本地 user_id 列保留空兼容旧 schema
    bookId: dto.bookId,
    chapterId: dto.chapterId,
    pageIdx: dto.pageIdx,
    label: dto.label === undefined ? null : dto.label,
    createdAt: isNaN(ts) ? Date.now() : ts,
  };
}

export const BookmarkAdapter: DomainAdapter<Bookmark> = {
  idOf(b: Bookmark): string {
    return b.id;
  },

  async push(op: PersistentOp<PersistentDomainKey, Bookmark>): Promise<void> {
    if (op.kind === 'upsert' && op.payload) {
      await BookmarkApi.upsert(clientToDto(op.payload));
      return;
    }
    if (op.kind === 'delete') {
      await BookmarkApi.delete(op.id);
      return;
    }
  },

  async pull(id: string): Promise<Bookmark | null> {
    const dto = await BookmarkApi.getById(id);
    return dto ? dtoToClient(dto) : null;
  },
};
