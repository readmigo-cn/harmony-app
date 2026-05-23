import { StoreKeys } from './StoreKeys';
import { PreferencesManager } from '../core/persistence/PreferencesManager';

export interface ReadingProgress {
  bookId: string;
  chapterId: string;
  position: number;
  percent: number;
  updatedAt: number;
}

export interface CurrentBook {
  bookId: string;
  slug: string;
  title: string;
  coverUrl: string;
}

export interface RecentBookEntry {
  bookId: string;
  visitedAt: number;
}

/** W7-C5：单章节阅读状态。 */
export type ChapterStatus = 'unread' | 'reading' | 'finished';

/** 章节状态嵌套结构：bookId -> chapterIndex(string) -> status。
 *  外层 Map 序列化：避免 JSON 不支持 Map 直接 stringify，统一持久化为 plain object。 */
export interface ChapterStatusMap {
  [bookId: string]: { [chapterIndex: string]: ChapterStatus };
}

/** lastSyncedAt 持久化结构：bookId -> 时间戳（ms）。 */
export interface LastSyncedMap {
  [bookId: string]: number;
}

const MAX_RECENT = 10;

/**
 * ReadingStore：当前在读 + 进度 + 最近 10 本。
 *
 * 存储分层：
 *   AppStorage 持运行时引用，UI 用 @StorageLink 监听。
 *   PreferencesManager 持久化（JSON 序列化字符串），重启回灌。
 *
 * 兼容旧 API：setCurrentBook(bookId), setLastProgress, getLastProgress 保留。
 */
export class ReadingStore {
  static async init(): Promise<void> {
    const bookId = await PreferencesManager.getString(StoreKeys.READING_CURRENT_BOOK, '');
    const slug = await PreferencesManager.getString(StoreKeys.READING_CURRENT_SLUG, '');
    const title = await PreferencesManager.getString(StoreKeys.READING_CURRENT_TITLE, '');
    const cover = await PreferencesManager.getString(StoreKeys.READING_CURRENT_COVER, '');
    const progressRaw = await PreferencesManager.getString(StoreKeys.READING_LAST_PROGRESS, '');
    const sessionId = await PreferencesManager.getString(StoreKeys.READING_SESSION_ID, '');
    const recentRaw = await PreferencesManager.getString(StoreKeys.READING_RECENT_BOOKS, '');

    AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_BOOK, bookId);
    AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_SLUG, slug);
    AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_TITLE, title);
    AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_COVER, cover);
    AppStorage.SetOrCreate<string>(StoreKeys.READING_SESSION_ID, sessionId);

    if (progressRaw.length > 0) {
      try {
        const p = JSON.parse(progressRaw) as ReadingProgress;
        AppStorage.SetOrCreate<ReadingProgress>(StoreKeys.READING_LAST_PROGRESS, p);
      } catch (_) {
        // ignore corrupt blob
      }
    }
    if (recentRaw.length > 0) {
      try {
        const list = JSON.parse(recentRaw) as RecentBookEntry[];
        AppStorage.SetOrCreate<RecentBookEntry[]>(StoreKeys.READING_RECENT_BOOKS, list);
      } catch (_) {
        AppStorage.SetOrCreate<RecentBookEntry[]>(StoreKeys.READING_RECENT_BOOKS, []);
      }
    } else {
      AppStorage.SetOrCreate<RecentBookEntry[]>(StoreKeys.READING_RECENT_BOOKS, []);
    }

    // W7-C5：章节状态（chapterProgress）回灌
    const chProgressRaw = await PreferencesManager.getString(StoreKeys.READING_CHAPTER_PROGRESS, '');
    let chProgress: ChapterStatusMap = {};
    if (chProgressRaw.length > 0) {
      try {
        chProgress = JSON.parse(chProgressRaw) as ChapterStatusMap;
      } catch (_) {
        chProgress = {};
      }
    }
    AppStorage.SetOrCreate<ChapterStatusMap>(StoreKeys.READING_CHAPTER_PROGRESS, chProgress);

    // W7-C6：lastSyncedAt 回灌
    const syncedRaw = await PreferencesManager.getString(StoreKeys.READING_LAST_SYNCED_AT, '');
    let synced: LastSyncedMap = {};
    if (syncedRaw.length > 0) {
      try {
        synced = JSON.parse(syncedRaw) as LastSyncedMap;
      } catch (_) {
        synced = {};
      }
    }
    AppStorage.SetOrCreate<LastSyncedMap>(StoreKeys.READING_LAST_SYNCED_AT, synced);
  }

  /**
   * 兼容旧签名：setCurrentBook(bookId)；新签名带 slug/title/cover。
   * 调用方可只传 bookId（onboarding 兼容），或传完整对象。
   */
  static setCurrentBook(bookId: string, slug: string = '', title: string = '', coverUrl: string = ''): void {
    AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_BOOK, bookId);
    AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_SLUG, slug);
    AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_TITLE, title);
    AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_COVER, coverUrl);
    PreferencesManager.setString(StoreKeys.READING_CURRENT_BOOK, bookId);
    PreferencesManager.setString(StoreKeys.READING_CURRENT_SLUG, slug);
    PreferencesManager.setString(StoreKeys.READING_CURRENT_TITLE, title);
    PreferencesManager.setString(StoreKeys.READING_CURRENT_COVER, coverUrl);
    ReadingStore.addToRecent(bookId);
  }

  static getCurrentBook(): string | undefined {
    return AppStorage.Get<string>(StoreKeys.READING_CURRENT_BOOK);
  }

  static getCurrentBookFull(): CurrentBook | undefined {
    const bookId = AppStorage.Get<string>(StoreKeys.READING_CURRENT_BOOK) ?? '';
    if (!bookId) return undefined;
    return {
      bookId,
      slug: AppStorage.Get<string>(StoreKeys.READING_CURRENT_SLUG) ?? '',
      title: AppStorage.Get<string>(StoreKeys.READING_CURRENT_TITLE) ?? '',
      coverUrl: AppStorage.Get<string>(StoreKeys.READING_CURRENT_COVER) ?? '',
    };
  }

  /** 兼容旧 API：完整覆盖。 */
  static setLastProgress(p: ReadingProgress): void {
    AppStorage.SetOrCreate<ReadingProgress>(StoreKeys.READING_LAST_PROGRESS, p);
    PreferencesManager.setString(StoreKeys.READING_LAST_PROGRESS, JSON.stringify(p));
  }

  static getLastProgress(): ReadingProgress | undefined {
    return AppStorage.Get<ReadingProgress>(StoreKeys.READING_LAST_PROGRESS);
  }

  /**
   * 增量更新当前进度。bookId 取自 currentBook（若无则忽略）。
   */
  static updateProgress(chapterIndex: number, percent: number, scrollOffset: number): void {
    const bookId = AppStorage.Get<string>(StoreKeys.READING_CURRENT_BOOK) ?? '';
    if (!bookId) return;
    const next: ReadingProgress = {
      bookId,
      chapterId: chapterIndex.toString(),
      position: scrollOffset,
      percent,
      updatedAt: Date.now(),
    };
    ReadingStore.setLastProgress(next);
  }

  static startSession(sessionId: string): void {
    AppStorage.SetOrCreate<string>(StoreKeys.READING_SESSION_ID, sessionId);
    PreferencesManager.setString(StoreKeys.READING_SESSION_ID, sessionId);
  }

  static getSessionId(): string {
    return AppStorage.Get<string>(StoreKeys.READING_SESSION_ID) ?? '';
  }

  static endSession(): void {
    AppStorage.SetOrCreate<string>(StoreKeys.READING_SESSION_ID, '');
    PreferencesManager.setString(StoreKeys.READING_SESSION_ID, '');
  }

  static addToRecent(bookId: string): void {
    if (!bookId) return;
    const cur = AppStorage.Get<RecentBookEntry[]>(StoreKeys.READING_RECENT_BOOKS) ?? [];
    const filtered = cur.filter((e) => e.bookId !== bookId);
    filtered.unshift({ bookId, visitedAt: Date.now() });
    const trimmed = filtered.slice(0, MAX_RECENT);
    AppStorage.SetOrCreate<RecentBookEntry[]>(StoreKeys.READING_RECENT_BOOKS, trimmed);
    PreferencesManager.setString(StoreKeys.READING_RECENT_BOOKS, JSON.stringify(trimmed));
  }

  static getRecent(): RecentBookEntry[] {
    return AppStorage.Get<RecentBookEntry[]>(StoreKeys.READING_RECENT_BOOKS) ?? [];
  }

  // ─── W7-C5 章节状态 ──────────────────────────────────────────

  /** 写入单个章节状态，并持久化整张表。 */
  static setChapterStatus(bookId: string, chapterIndex: number, status: ChapterStatus): void {
    if (!bookId) return;
    const all = AppStorage.Get<ChapterStatusMap>(StoreKeys.READING_CHAPTER_PROGRESS) ?? {};
    const bookMap = all[bookId] ?? {};
    bookMap[chapterIndex.toString()] = status;
    all[bookId] = bookMap;
    AppStorage.SetOrCreate<ChapterStatusMap>(StoreKeys.READING_CHAPTER_PROGRESS, all);
    PreferencesManager.setString(StoreKeys.READING_CHAPTER_PROGRESS, JSON.stringify(all));
  }

  /** 返回某本书的章节状态键值表，组件层可转 Map<number, ChapterStatus>。 */
  static getChapterStatuses(bookId: string): Record<string, ChapterStatus> {
    const all = AppStorage.Get<ChapterStatusMap>(StoreKeys.READING_CHAPTER_PROGRESS) ?? {};
    return all[bookId] ?? {};
  }

  /** 批量设置（pull 云端进度后回灌全书） */
  static setBookChapterStatuses(bookId: string, map: Record<string, ChapterStatus>): void {
    if (!bookId) return;
    const all = AppStorage.Get<ChapterStatusMap>(StoreKeys.READING_CHAPTER_PROGRESS) ?? {};
    all[bookId] = map;
    AppStorage.SetOrCreate<ChapterStatusMap>(StoreKeys.READING_CHAPTER_PROGRESS, all);
    PreferencesManager.setString(StoreKeys.READING_CHAPTER_PROGRESS, JSON.stringify(all));
  }

  // ─── W7-C6 lastSyncedAt ─────────────────────────────────────

  static setLastSyncedAt(bookId: string, ts: number): void {
    if (!bookId) return;
    const all = AppStorage.Get<LastSyncedMap>(StoreKeys.READING_LAST_SYNCED_AT) ?? {};
    all[bookId] = ts;
    AppStorage.SetOrCreate<LastSyncedMap>(StoreKeys.READING_LAST_SYNCED_AT, all);
    PreferencesManager.setString(StoreKeys.READING_LAST_SYNCED_AT, JSON.stringify(all));
  }

  static getLastSyncedAt(bookId: string): number {
    const all = AppStorage.Get<LastSyncedMap>(StoreKeys.READING_LAST_SYNCED_AT) ?? {};
    return all[bookId] ?? 0;
  }

  static clear(): void {
    AppStorage.Delete(StoreKeys.READING_CURRENT_BOOK);
    AppStorage.Delete(StoreKeys.READING_CURRENT_SLUG);
    AppStorage.Delete(StoreKeys.READING_CURRENT_TITLE);
    AppStorage.Delete(StoreKeys.READING_CURRENT_COVER);
    AppStorage.Delete(StoreKeys.READING_LAST_PROGRESS);
    AppStorage.Delete(StoreKeys.READING_SESSION_ID);
    AppStorage.SetOrCreate<RecentBookEntry[]>(StoreKeys.READING_RECENT_BOOKS, []);
    PreferencesManager.remove(StoreKeys.READING_CURRENT_BOOK);
    PreferencesManager.remove(StoreKeys.READING_CURRENT_SLUG);
    PreferencesManager.remove(StoreKeys.READING_CURRENT_TITLE);
    PreferencesManager.remove(StoreKeys.READING_CURRENT_COVER);
    PreferencesManager.remove(StoreKeys.READING_LAST_PROGRESS);
    PreferencesManager.remove(StoreKeys.READING_SESSION_ID);
    PreferencesManager.remove(StoreKeys.READING_RECENT_BOOKS);
    AppStorage.Delete(StoreKeys.READING_CHAPTER_PROGRESS);
    AppStorage.Delete(StoreKeys.READING_LAST_SYNCED_AT);
    PreferencesManager.remove(StoreKeys.READING_CHAPTER_PROGRESS);
    PreferencesManager.remove(StoreKeys.READING_LAST_SYNCED_AT);
    PreferencesManager.remove(StoreKeys.READING_PROGRESS_QUEUE);
  }
}
