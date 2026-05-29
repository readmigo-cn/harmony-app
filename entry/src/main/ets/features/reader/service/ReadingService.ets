/**
 * ReadingService.ets — L2 domain service for chapter loading
 *
 * Tier:  memory cache → disk cache → API
 * Offline: catches network errors and falls through to disk cache;
 *          throws OfflineUnavailableError when both miss.
 */

import { ReadingApi } from '../../../api/reading/ReadingApi';
import { ChapterCacheStrategy } from '../../../core/cache/strategies/ChapterCacheStrategy';
import { Book } from '../../../model/Book';
import { Chapter, ChapterContent } from '../../../model/Chapter';

export class OfflineUnavailableError extends Error {
  constructor(bookId: string, chapterId: string) {
    super(`Offline: chapter ${chapterId} of book ${bookId} not cached`);
    this.name = 'OfflineUnavailableError';
  }
}

const MEMORY_CAP = 6;

interface MemEntry {
  key: string;
  content: ChapterContent;
  accessedAt: number;
}

class ReadingServiceImpl {
  // LRU memory cache: key = `{bookId}:{chapterId}`
  private memCache: MemEntry[] = [];

  // ---------- Book / Chapter loading ----------------------------------------

  async loadBook(bookId: string): Promise<Book> {
    return ReadingApi.getBookDetail(bookId);
  }

  async loadChapters(bookId: string): Promise<Chapter[]> {
    return ReadingApi.getChapters(bookId);
  }

  async loadChapterContent(bookId: string, chapterId: string): Promise<ChapterContent> {
    const memHit = this.memGet(bookId, chapterId);
    if (memHit) return memHit;

    // Try disk cache before hitting network
    let content: ChapterContent | null = null;
    try {
      content = await ChapterCacheStrategy.get(bookId, this.chapterIndex(chapterId));
    } catch (_e) {
      content = null;
    }

    if (!content) {
      // Fetch from network; if offline this throws
      try {
        content = await ReadingApi.getChapterContent(bookId, chapterId);
      } catch (networkErr) {
        // Network failed — check disk one more time (may have been populated by a parallel call)
        const diskRetry = await ChapterCacheStrategy.get(bookId, this.chapterIndex(chapterId)).catch(() => null);
        if (diskRetry) {
          this.memPut(bookId, chapterId, diskRetry);
          return diskRetry;
        }
        throw new OfflineUnavailableError(bookId, chapterId);
      }
      // Populate disk cache (silent)
      ChapterCacheStrategy.put(bookId, this.chapterIndex(chapterId), content, false).catch(() => {});
    }

    this.memPut(bookId, chapterId, content);
    return content;
  }

  // fire-and-forget; used by ViewModel after open-book
  prefetchAdjacent(bookId: string, chapters: Chapter[], currentIdx: number): void {
    const targets: number[] = [];
    if (currentIdx > 0) targets.push(currentIdx - 1);
    if (currentIdx < chapters.length - 1) targets.push(currentIdx + 1);
    for (const idx of targets) {
      const ch = chapters[idx];
      if (!ch) continue;
      this.loadChapterContent(bookId, ch.id).catch(() => {});
    }
  }

  // ---------- LRU memory cache internals ------------------------------------

  private memKey(bookId: string, chapterId: string): string {
    return `${bookId}:${chapterId}`;
  }

  private memGet(bookId: string, chapterId: string): ChapterContent | null {
    const key = this.memKey(bookId, chapterId);
    const idx = this.memCache.findIndex((e) => e.key === key);
    if (idx < 0) return null;
    const entry = this.memCache.splice(idx, 1)[0];
    entry.accessedAt = Date.now();
    this.memCache.push(entry); // move to MRU end
    return entry.content;
  }

  private memPut(bookId: string, chapterId: string, content: ChapterContent): void {
    const key = this.memKey(bookId, chapterId);
    const existing = this.memCache.findIndex((e) => e.key === key);
    if (existing >= 0) this.memCache.splice(existing, 1);
    this.memCache.push({ key, content, accessedAt: Date.now() });
    if (this.memCache.length > MEMORY_CAP) {
      // Evict LRU (front of array = oldest)
      this.memCache.shift();
    }
  }

  clearMemory(): void {
    this.memCache = [];
  }

  // ---------- Helpers -------------------------------------------------------

  // ChapterCacheStrategy uses numeric index; we treat chapterId as numeric when possible,
  // otherwise fall through to 0. The API gives Chapter objects with both id and index.
  private chapterIndex(chapterId: string): number {
    const n = parseInt(chapterId, 10);
    return isNaN(n) ? 0 : n;
  }
}

export const ReadingService = new ReadingServiceImpl();
