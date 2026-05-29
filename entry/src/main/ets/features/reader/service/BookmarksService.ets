/**
 * BookmarksService.ets — L2 service for reader bookmarks.
 *
 * Uses BookmarksRepository (RDB) as the local store.
 * No cloud sync in W3 — bookmarks are local-first only for now.
 * userId is empty string until AccountStore integration lands (W4).
 */

import {
  BookmarksRepository,
  Bookmark,
} from '../../../core/persistence/repositories/BookmarksRepository';

export type { Bookmark };

export interface BookmarkInput {
  bookId: string;
  chapterId: string;
  pageIdx: number;
  label?: string;
}

function genId(): string {
  const part = (): string => Math.floor((1 + Math.random()) * 0x10000).toString(16).slice(1);
  return `${part()}${part()}-${part()}-${part()}-${part()}-${part()}${part()}${part()}`;
}

class BookmarksServiceImpl {
  private cache: Map<string, Bookmark[]> = new Map();

  /**
   * List all bookmarks for a book, sorted by creation time descending.
   */
  async list(bookId: string): Promise<Bookmark[]> {
    const cached = this.cache.get(bookId);
    if (cached) return cached.slice();
    try {
      const rows = await BookmarksRepository.listByBook(bookId, '');
      this.cache.set(bookId, rows);
      return rows.slice();
    } catch (_e) {
      return [];
    }
  }

  /**
   * Save a new bookmark. Returns the persisted Bookmark with its generated id.
   */
  async save(input: BookmarkInput): Promise<Bookmark> {
    const id = genId();
    const now = Date.now();
    const bookmark: Bookmark = {
      id,
      userId: '',
      bookId: input.bookId,
      chapterId: input.chapterId,
      pageIdx: input.pageIdx,
      label: input.label ?? null,
      createdAt: now,
    };
    await BookmarksRepository.insert(bookmark);
    this.cache.delete(input.bookId);
    return bookmark;
  }

  /**
   * Delete a bookmark by id.
   */
  async delete(bookmarkId: string): Promise<void> {
    await BookmarksRepository.deleteById(bookmarkId);
    this.cache.clear();
  }
}

export const BookmarksService = new BookmarksServiceImpl();
