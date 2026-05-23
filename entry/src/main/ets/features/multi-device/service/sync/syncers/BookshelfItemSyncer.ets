/**
 * BookshelfItemSyncer.ets — 书架 entity 同步器
 *
 * 走 ReadingApi.listShelf / addToShelf / updateShelfStatus。
 * 服务端没有 delete 接口（书架不可删，仅 status='archived'），所以 deleted 映射为 status update。
 *
 * 冲突：status 字段以 LWW 解决；unread/reading/finished 不强制合并。
 */

import { EntitySyncer, PushResult, SyncableEntity, lastWriteWins } from '../SyncEngine';
import { ReadingApi } from '../../../../../api/reading/ReadingApi';
import { UserBook, BookStatus } from '../../../../../model/Book';

export interface BookshelfItemEntity extends SyncableEntity, UserBook {}

export class BookshelfItemSyncer implements EntitySyncer<BookshelfItemEntity> {
  entityType: string = 'bookshelf-item';

  async pull(_since?: Date): Promise<BookshelfItemEntity[]> {
    try {
      const list = await ReadingApi.listShelf();
      return list.map((b) => BookshelfItemSyncer.toEntity(b));
    } catch (_e) {
      return [];
    }
  }

  async push(items: BookshelfItemEntity[]): Promise<PushResult<BookshelfItemEntity>> {
    const accepted: BookshelfItemEntity[] = [];
    for (const it of items) {
      try {
        // 加书架（addToShelf 幂等：服务端 already-exists 不视为错误）
        try {
          await ReadingApi.addToShelf(it.bookId);
        } catch (_e) {
          // 如果已经在书架，addToShelf 可能返回错误；忽略，继续 update status
        }
        if (it.status) {
          await ReadingApi.updateShelfStatus(it.bookId, it.status);
        }
        accepted.push(it);
      } catch (_e) {
        // 留队列重试
      }
    }
    return { accepted, conflicts: [] };
  }

  resolveConflict(local: BookshelfItemEntity, server: BookshelfItemEntity): BookshelfItemEntity {
    return lastWriteWins(local, server);
  }

  private static toEntity(b: UserBook): BookshelfItemEntity {
    // UserBook 可能没有 updatedAt；用 addedAt 兜底
    const ub = b as unknown as { updatedAt?: string; addedAt?: string; id?: string; bookId?: string };
    return {
      ...b,
      id: ub.id ?? ub.bookId ?? '',
      updatedAt: ub.updatedAt ?? ub.addedAt ?? new Date().toISOString(),
    } as BookshelfItemEntity;
  }
}

// Re-export for convenience
export { BookStatus };
