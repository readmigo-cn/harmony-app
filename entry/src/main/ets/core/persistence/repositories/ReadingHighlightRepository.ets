import { RdbOrm, EntitySchema } from '../RdbOrm';

/**
 * 阅读高亮记录。color 用 hex 字符串保存（#RRGGBB）。
 */
export interface ReadingHighlight {
  id: string;
  userId: string;
  bookId: string;
  chapterId: string | null;
  blockIndex: number;
  charOffset: number;
  charLength: number;
  text: string;
  color: string;
  note: string | null;
  createdAt: number;
  updatedAt: number;
}

const HighlightEntity: EntitySchema<ReadingHighlight> = RdbOrm.defineEntity<ReadingHighlight>({
  table: 'reading_highlights',
  version: 1,
  columns: {
    id: { type: 'TEXT', primaryKey: true, notNull: true },
    user_id: { type: 'TEXT', notNull: true },
    book_id: { type: 'TEXT', notNull: true },
    chapter_id: { type: 'TEXT' },
    block_index: { type: 'INTEGER', defaultValue: 0 },
    char_offset: { type: 'INTEGER', defaultValue: 0 },
    char_length: { type: 'INTEGER', defaultValue: 0 },
    text: { type: 'TEXT' },
    color: { type: 'TEXT', defaultValue: '#FFEB3B' },
    note: { type: 'TEXT' },
    created_at: { type: 'INTEGER', notNull: true },
    updated_at: { type: 'INTEGER', notNull: true },
  },
  indices: [
    { name: 'idx_hl_book', columns: ['book_id', 'chapter_id'] },
    { name: 'idx_hl_user', columns: ['user_id', 'created_at'] },
  ],
  fieldToColumn: {
    userId: 'user_id',
    bookId: 'book_id',
    chapterId: 'chapter_id',
    blockIndex: 'block_index',
    charOffset: 'char_offset',
    charLength: 'char_length',
    createdAt: 'created_at',
    updatedAt: 'updated_at',
  },
});

export class ReadingHighlightRepository {
  static entity(): EntitySchema<ReadingHighlight> { return HighlightEntity; }

  static insert(h: ReadingHighlight): Promise<number> {
    return RdbOrm.upsert(HighlightEntity, h);
  }

  static listByChapter(bookId: string, chapterId: string | null): Promise<ReadingHighlight[]> {
    let q = RdbOrm.query(HighlightEntity).where('bookId', '=', bookId);
    if (chapterId === null) q = q.andWhere('chapterId', 'is null');
    else q = q.andWhere('chapterId', '=', chapterId);
    return q.orderBy('charOffset', 'asc').all();
  }

  static listByBook(bookId: string): Promise<ReadingHighlight[]> {
    return RdbOrm.query(HighlightEntity)
      .where('bookId', '=', bookId)
      .orderBy('createdAt', 'desc')
      .all();
  }

  static updateNote(id: string, note: string | null, updatedAt: number): Promise<number> {
    const patch: Partial<ReadingHighlight> = { note, updatedAt };
    return RdbOrm.update(HighlightEntity, patch, (q) => q.where('id', '=', id));
  }

  static deleteById(id: string): Promise<number> {
    return RdbOrm.delete(HighlightEntity, (q) => q.where('id', '=', id));
  }
}
