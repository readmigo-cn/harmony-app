import { RdbOrm, EntitySchema } from '../RdbOrm';

/**
 * A reader bookmark pinning a specific page position within a chapter.
 *
 * Table: bookmarks
 * PK: id (client-generated UUID)
 * Indexed by (book_id, created_at) for list queries.
 */
export interface Bookmark {
  id: string;
  userId: string;
  bookId: string;
  chapterId: string;
  pageIdx: number;
  label: string | null;
  createdAt: number;
}

const BookmarkEntity: EntitySchema<Bookmark> = RdbOrm.defineEntity<Bookmark>({
  table: 'bookmarks',
  version: 1,
  columns: {
    id: { type: 'TEXT', primaryKey: true, notNull: true },
    user_id: { type: 'TEXT', notNull: true },
    book_id: { type: 'TEXT', notNull: true },
    chapter_id: { type: 'TEXT', notNull: true },
    page_idx: { type: 'INTEGER', defaultValue: 0 },
    label: { type: 'TEXT' },
    created_at: { type: 'INTEGER', notNull: true },
  },
  indices: [
    { name: 'idx_bm_book_user', columns: ['book_id', 'user_id', 'created_at'] },
  ],
  fieldToColumn: {
    userId: 'user_id',
    bookId: 'book_id',
    chapterId: 'chapter_id',
    pageIdx: 'page_idx',
    createdAt: 'created_at',
  },
});

export class BookmarksRepository {
  static entity(): EntitySchema<Bookmark> { return BookmarkEntity; }

  static insert(b: Bookmark): Promise<number> {
    return RdbOrm.upsert(BookmarkEntity, b);
  }

  static listByBook(bookId: string, userId: string): Promise<Bookmark[]> {
    return RdbOrm.query(BookmarkEntity)
      .where('bookId', '=', bookId)
      .andWhere('userId', '=', userId)
      .orderBy('createdAt', 'desc')
      .all();
  }

  static deleteById(id: string): Promise<number> {
    return RdbOrm.delete(BookmarkEntity, (q) => q.where('id', '=', id));
  }
}
