import { RdbOrm, EntitySchema } from '../RdbOrm';

/**
 * 阅读进度（替代 W7 直接 store 模式）。
 * 主键 = (user_id, book_id) 复合，但 RDB 走单 PK + 唯一索引以兼容 ORM。
 */
export interface ReadingProgress {
  id: string;            // userId + ':' + bookId
  userId: string;
  bookId: string;
  chapterId: string | null;
  position: number;
  percent: number;
  durationMs: number;
  updatedAt: number;
}

const ProgressEntity: EntitySchema<ReadingProgress> = RdbOrm.defineEntity<ReadingProgress>({
  table: 'reading_progress_v2',
  version: 1,
  columns: {
    id: { type: 'TEXT', primaryKey: true, notNull: true },
    user_id: { type: 'TEXT', notNull: true },
    book_id: { type: 'TEXT', notNull: true },
    chapter_id: { type: 'TEXT' },
    position: { type: 'INTEGER', defaultValue: 0 },
    percent: { type: 'REAL', defaultValue: 0 },
    duration_ms: { type: 'INTEGER', defaultValue: 0 },
    updated_at: { type: 'INTEGER', notNull: true },
  },
  indices: [
    { name: 'idx_prog_user_book', columns: ['user_id', 'book_id'], unique: true },
    { name: 'idx_prog_updated', columns: ['user_id', 'updated_at'] },
  ],
  fieldToColumn: {
    userId: 'user_id',
    bookId: 'book_id',
    chapterId: 'chapter_id',
    durationMs: 'duration_ms',
    updatedAt: 'updated_at',
  },
});

export class ReadingProgressRepository {
  static entity(): EntitySchema<ReadingProgress> { return ProgressEntity; }

  static makeId(userId: string, bookId: string): string { return `${userId}:${bookId}`; }

  /** upsert 是关键：同一本书反复保存进度。 */
  static save(p: ReadingProgress): Promise<number> {
    return RdbOrm.upsert(ProgressEntity, p);
  }

  static findByBook(userId: string, bookId: string): Promise<ReadingProgress | null> {
    return RdbOrm.findOne(ProgressEntity, (q) =>
      q.where('userId', '=', userId).andWhere('bookId', '=', bookId));
  }

  /** 用户最近读过的书；用于"继续阅读"卡片。 */
  static recentByUser(userId: string, limit: number = 10): Promise<ReadingProgress[]> {
    return RdbOrm.query(ProgressEntity)
      .where('userId', '=', userId)
      .orderBy('updatedAt', 'desc')
      .limit(limit)
      .all();
  }

  static incrementDuration(userId: string, bookId: string, deltaMs: number, now: number): Promise<ReadingProgress> {
    return RdbOrm.runInTransaction<ReadingProgress>(async () => {
      const cur = await ReadingProgressRepository.findByBook(userId, bookId);
      const next: ReadingProgress = cur ? {
        id: cur.id,
        userId: cur.userId,
        bookId: cur.bookId,
        chapterId: cur.chapterId,
        position: cur.position,
        percent: cur.percent,
        durationMs: cur.durationMs + deltaMs,
        updatedAt: now,
      } : {
        id: ReadingProgressRepository.makeId(userId, bookId),
        userId, bookId, chapterId: null, position: 0, percent: 0,
        durationMs: deltaMs, updatedAt: now,
      };
      await ReadingProgressRepository.save(next);
      return next;
    });
  }

  static deleteByBook(userId: string, bookId: string): Promise<number> {
    return RdbOrm.delete(ProgressEntity, (q) =>
      q.where('userId', '=', userId).andWhere('bookId', '=', bookId));
  }
}
