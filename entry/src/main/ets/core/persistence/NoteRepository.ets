import relationalStore from '@ohos.data.relationalStore';
import { DatabaseManager } from './DatabaseManager';

export interface LocalNote {
  id: string;            // 客户端生成的本地 id（UUID）
  bookId: string;
  chapterId: string | null;
  blockIndex: number;
  charOffset: number;
  charLength: number;
  originalText: string;
  noteText: string | null;
  createdAt: number;     // epoch ms
  remoteId?: string;     // 同步成功后填充
}

const TABLE = 'notes';
const COLUMNS = [
  'id', 'book_id', 'chapter_id', 'text',
  'range_start', 'range_end', 'created_at',
];

export class NoteRepository {
  /**
   * Local schema (DatabaseManager 已创建)：
   *   id TEXT PRIMARY KEY, book_id TEXT, chapter_id TEXT, text TEXT,
   *   range_start INTEGER, range_end INTEGER, created_at INTEGER
   * note: 当前 schema 未存 noteText 与 remoteId；下批 V2 schema migration 时补上。
   */
  static async insert(n: LocalNote): Promise<void> {
    const rdb = DatabaseManager.get();
    const values: relationalStore.ValuesBucket = {
      id: n.id,
      book_id: n.bookId,
      chapter_id: n.chapterId,
      text: n.originalText,
      range_start: n.charOffset,
      range_end: n.charOffset + n.charLength,
      created_at: n.createdAt,
    };
    await rdb.insert(TABLE, values);
  }

  static async listByBook(bookId: string): Promise<LocalNote[]> {
    const rdb = DatabaseManager.get();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('book_id', bookId);
    predicates.orderByDesc('created_at');
    const cursor = await rdb.query(predicates, COLUMNS);
    const result: LocalNote[] = [];
    while (cursor.goToNextRow()) {
      result.push({
        id: cursor.getString(cursor.getColumnIndex('id')),
        bookId: cursor.getString(cursor.getColumnIndex('book_id')),
        chapterId: cursor.getString(cursor.getColumnIndex('chapter_id')) ?? null,
        blockIndex: 0,
        charOffset: cursor.getLong(cursor.getColumnIndex('range_start')),
        charLength:
          cursor.getLong(cursor.getColumnIndex('range_end')) -
          cursor.getLong(cursor.getColumnIndex('range_start')),
        originalText: cursor.getString(cursor.getColumnIndex('text')),
        noteText: null,
        createdAt: cursor.getLong(cursor.getColumnIndex('created_at')),
      });
    }
    cursor.close();
    return result;
  }

  static async deleteById(id: string): Promise<void> {
    const rdb = DatabaseManager.get();
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    await rdb.delete(predicates);
  }
}
