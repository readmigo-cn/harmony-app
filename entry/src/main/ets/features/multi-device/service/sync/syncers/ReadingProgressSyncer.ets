/**
 * ReadingProgressSyncer.ets — 阅读进度 entity 同步器
 *
 * 是 W7 ProgressSync 的通用化迁移：
 *   - 仍然走 ReadingApi.getProgress/updateProgress（本任务不动后端 endpoint）
 *   - W7 ProgressSync 保留运行；调用方可自由切换到 SyncEngine
 *
 * 冲突策略：percent 取 max（不让旧 server 数据回退本地阅读进度）+ updatedAt 取靠后。
 */

import { EntitySyncer, PushResult, SyncableEntity } from '../SyncEngine';
import { ReadingApi } from '../../../../../api/reading/ReadingApi';
import { ReadingProgressDto } from '../../../../../model/ReadingProgress';

/**
 * 服务端 reading.progress 用 (userId, bookId) 作为唯一键，没有 id 字段。
 * 这里把 bookId 作为 SyncableEntity.id 复用（reading-progress 命名空间内不会重复）。
 */
export interface ReadingProgressEntity extends SyncableEntity, ReadingProgressDto {}

export class ReadingProgressSyncer implements EntitySyncer<ReadingProgressEntity> {
  entityType: string = 'reading-progress';

  /**
   * Reading progress 没有列表 API；pull 仅按需单本拉取（由调用方传 bookId）。
   * 通用 pull(since) 这里返回空：上层用 pullOne(bookId) 替代。
   */
  async pull(_since?: Date): Promise<ReadingProgressEntity[]> {
    return [];
  }

  /** 单本拉取（W7 ProgressSync.pull 等价行为）。 */
  async pullOne(bookId: string): Promise<ReadingProgressEntity | null> {
    try {
      const dto = await ReadingApi.getProgress(bookId);
      if (!dto) return null;
      return ReadingProgressSyncer.toEntity(dto);
    } catch (_e) {
      return null;
    }
  }

  /**
   * push 实际是 PUT /reading/progress/:bookId 的批量循环。
   * 没有 server 返回 conflicts 的协议字段，这里把所有成功项作为 accepted 返回。
   */
  async push(items: ReadingProgressEntity[]): Promise<PushResult<ReadingProgressEntity>> {
    const accepted: ReadingProgressEntity[] = [];
    for (const it of items) {
      try {
        await ReadingApi.updateProgress(it.bookId, {
          bookId: it.bookId,
          chapterIndex: it.chapterIndex,
          blockIndex: it.blockIndex,
          charOffset: it.charOffset,
          pageIndex: it.pageIndex,
          percent: it.percent,
          updatedAt: it.updatedAt,
        });
        accepted.push(it);
      } catch (_e) {
        // 留在队列等下次重试（SyncEngine.flush 会触发退避）
      }
    }
    return { accepted, conflicts: [] };
  }

  resolveConflict(local: ReadingProgressEntity, server: ReadingProgressEntity): ReadingProgressEntity {
    const lt = Date.parse(local.updatedAt) || 0;
    const st = Date.parse(server.updatedAt) || 0;
    const winnerTs = Math.max(lt, st);
    const winnerIso = new Date(winnerTs).toISOString();
    return {
      id: local.id,
      bookId: local.bookId ?? server.bookId,
      chapterIndex: Math.max(local.chapterIndex ?? 0, server.chapterIndex ?? 0),
      blockIndex: local.blockIndex ?? server.blockIndex,
      charOffset: local.charOffset ?? server.charOffset,
      pageIndex: local.pageIndex ?? server.pageIndex,
      // percent 取 max：进度不回退
      percent: Math.max(local.percent ?? 0, server.percent ?? 0),
      updatedAt: winnerIso,
      deleted: (local.deleted === true) || (server.deleted === true),
    };
  }

  private static toEntity(dto: ReadingProgressDto): ReadingProgressEntity {
    return {
      id: dto.bookId,
      bookId: dto.bookId,
      chapterIndex: dto.chapterIndex,
      blockIndex: dto.blockIndex,
      charOffset: dto.charOffset,
      pageIndex: dto.pageIndex,
      percent: dto.percent,
      updatedAt: dto.updatedAt ?? new Date().toISOString(),
    };
  }
}
