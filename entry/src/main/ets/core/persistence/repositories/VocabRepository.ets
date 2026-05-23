import { RdbOrm, EntitySchema } from '../RdbOrm';

/**
 * 生词本条目。
 * srsState: 0=new / 1=learning / 2=review / 3=mastered。
 */
export interface VocabNote {
  id: string;
  userId: string;
  bookId: string;
  word: string;
  definition: string | null;
  context: string | null;
  language: string;
  srsState: number;
  reviewCount: number;
  nextReviewAt: number;  // epoch ms
  createdAt: number;
  updatedAt: number;
}

const VocabEntity: EntitySchema<VocabNote> = RdbOrm.defineEntity<VocabNote>({
  table: 'vocab_notes',
  version: 1,
  columns: {
    id: { type: 'TEXT', primaryKey: true, notNull: true },
    user_id: { type: 'TEXT', notNull: true },
    book_id: { type: 'TEXT' },
    word: { type: 'TEXT', notNull: true },
    definition: { type: 'TEXT' },
    context: { type: 'TEXT' },
    language: { type: 'TEXT', notNull: true },
    srs_state: { type: 'INTEGER', defaultValue: 0 },
    review_count: { type: 'INTEGER', defaultValue: 0 },
    next_review_at: { type: 'INTEGER', defaultValue: 0 },
    created_at: { type: 'INTEGER', notNull: true },
    updated_at: { type: 'INTEGER', notNull: true },
  },
  indices: [
    { name: 'idx_vocab_user_word', columns: ['user_id', 'word'], unique: true },
    { name: 'idx_vocab_review', columns: ['user_id', 'next_review_at'] },
  ],
  fieldToColumn: {
    userId: 'user_id',
    bookId: 'book_id',
    srsState: 'srs_state',
    reviewCount: 'review_count',
    nextReviewAt: 'next_review_at',
    createdAt: 'created_at',
    updatedAt: 'updated_at',
  },
});

/**
 * 生词本仓储；基于新 RdbOrm。
 * 现有 NoteRepository 保持不动，新模块统一接入此处。
 */
export class VocabRepository {
  static entity(): EntitySchema<VocabNote> { return VocabEntity; }

  static insert(note: VocabNote): Promise<number> {
    return RdbOrm.upsert(VocabEntity, note);
  }

  static findById(id: string): Promise<VocabNote | null> {
    return RdbOrm.findOne(VocabEntity, (q) => q.where('id', '=', id));
  }

  /** 取该用户当前到期复习条目，按 nextReviewAt 升序。 */
  static dueForReview(userId: string, now: number, limit: number = 20): Promise<VocabNote[]> {
    return RdbOrm.query(VocabEntity)
      .where('userId', '=', userId)
      .andWhere('nextReviewAt', '<=', now)
      .orderBy('nextReviewAt', 'asc')
      .limit(limit)
      .all();
  }

  static listByUser(userId: string, limit: number = 100): Promise<VocabNote[]> {
    return RdbOrm.query(VocabEntity)
      .where('userId', '=', userId)
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .all();
  }

  static updateReview(id: string, srsState: number, reviewCount: number, nextReviewAt: number, updatedAt: number): Promise<number> {
    const patch: Partial<VocabNote> = { srsState, reviewCount, nextReviewAt, updatedAt };
    return RdbOrm.update(VocabEntity, patch, (q) => q.where('id', '=', id));
  }

  static deleteById(id: string): Promise<number> {
    return RdbOrm.delete(VocabEntity, (q) => q.where('id', '=', id));
  }

  static countByUser(userId: string): Promise<number> {
    return RdbOrm.count(VocabEntity, (q) => q.where('userId', '=', userId));
  }
}
