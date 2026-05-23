/**
 * ReadingHighlightSyncer.ets — 阅读高亮 entity 同步器
 *
 * 直接走现有 ReadingApi.{listHighlights, createHighlight, updateHighlight, deleteHighlight}。
 * pull 需要 bookId 维度；通用 pull(since) 在没有 bookId 时返回空，
 * 调用方应在打开某本书时调 pullForBook(bookId)。
 *
 * 冲突：LWW（updatedAt 比较），note 字段取 winner。
 */

import { EntitySyncer, PushResult, SyncableEntity } from '../SyncEngine';
import { ReadingApi } from '../../../../../api/reading/ReadingApi';
import { Highlight, HighlightColor } from '../../../../../model/Highlight';

export interface HighlightEntity extends SyncableEntity, Highlight {}

export class ReadingHighlightSyncer implements EntitySyncer<HighlightEntity> {
  entityType: string = 'reading-highlight';

  async pull(_since?: Date): Promise<HighlightEntity[]> {
    // 没有全局拉取 endpoint；上层应按书拉
    return [];
  }

  async pullForBook(bookId: string): Promise<HighlightEntity[]> {
    try {
      const list = await ReadingApi.listHighlights(bookId);
      return list.map((h) => ReadingHighlightSyncer.toEntity(h));
    } catch (_e) {
      return [];
    }
  }

  async push(items: HighlightEntity[]): Promise<PushResult<HighlightEntity>> {
    const accepted: HighlightEntity[] = [];
    for (const it of items) {
      try {
        if (it.deleted) {
          await ReadingApi.deleteHighlight(it.id);
          accepted.push(it);
          continue;
        }
        // id 以 server 真实 id 开头的视为已存在 → patch；否则 create
        const isExisting = it.id && !it.id.startsWith('local-');
        if (isExisting) {
          await ReadingApi.updateHighlight(it.id, { color: it.color, note: it.note });
        } else {
          const created = await ReadingApi.createHighlight({
            bookId: it.bookId,
            chapterId: it.chapterId,
            chapterIndex: it.chapterIndex,
            blockIndex: it.blockIndex,
            charOffset: it.charOffset,
            charLength: it.charLength,
            text: it.text,
            color: it.color as HighlightColor,
            note: it.note,
          });
          accepted.push(ReadingHighlightSyncer.toEntity(created));
          continue;
        }
        accepted.push(it);
      } catch (_e) {
        // 留队列重试
      }
    }
    return { accepted, conflicts: [] };
  }

  resolveConflict(local: HighlightEntity, server: HighlightEntity): HighlightEntity {
    const lt = Date.parse(local.updatedAt ?? '') || 0;
    const st = Date.parse(server.updatedAt ?? '') || 0;
    const winner = st > lt ? server : local;
    return {
      ...winner,
      deleted: (local.deleted === true) || (server.deleted === true),
    };
  }

  private static toEntity(h: Highlight): HighlightEntity {
    return {
      ...h,
      updatedAt: h.updatedAt ?? h.createdAt,
    };
  }
}
