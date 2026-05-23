import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';

const DB_NAME = 'readmigo.db';
const DB_VERSION = 1;

const SQL_BOOKS = `
CREATE TABLE IF NOT EXISTS books (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  author TEXT,
  cover_url TEXT,
  language TEXT,
  cefr_level TEXT,
  added_at INTEGER NOT NULL
)`;

const SQL_PROGRESS = `
CREATE TABLE IF NOT EXISTS reading_progress (
  book_id TEXT PRIMARY KEY,
  chapter_id TEXT,
  position INTEGER DEFAULT 0,
  percent REAL DEFAULT 0,
  updated_at INTEGER NOT NULL
)`;

const SQL_NOTES = `
CREATE TABLE IF NOT EXISTS notes (
  id TEXT PRIMARY KEY,
  book_id TEXT NOT NULL,
  chapter_id TEXT,
  text TEXT,
  range_start INTEGER,
  range_end INTEGER,
  created_at INTEGER NOT NULL
)`;

/**
 * RDB 初始化。Reader/Library 业务模块到位后再写 Repository 层。
 */
export class DatabaseManager {
  private static rdb: relationalStore.RdbStore | null = null;

  static async init(context: common.UIAbilityContext): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    DatabaseManager.rdb = await relationalStore.getRdbStore(context, config);
    await DatabaseManager.rdb.executeSql(SQL_BOOKS);
    await DatabaseManager.rdb.executeSql(SQL_PROGRESS);
    await DatabaseManager.rdb.executeSql(SQL_NOTES);
    if (DatabaseManager.rdb.version === 0) {
      DatabaseManager.rdb.version = DB_VERSION;
    }
  }

  static get(): relationalStore.RdbStore {
    if (!DatabaseManager.rdb) {
      throw new Error('DatabaseManager not initialized. Call init() in EntryAbility first.');
    }
    return DatabaseManager.rdb;
  }
}
