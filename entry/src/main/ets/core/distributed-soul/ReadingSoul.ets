// L1 - Foundation - DistributedSoul
// Facade over SoulEngine / LocalFallback; the canonical API for reading-progress state.

import { SoulEngine } from './SoulEngine';
import { LocalFallback } from './LocalFallback';
import type { ReadingSoul as ReadingSoulShape } from './SoulSchema';
import type { SoulListener } from './SoulEngine';

const PATH_BOOK = 'reading.book';
const PATH_CHAPTER = 'reading.chapterId';
const PATH_PAGE = 'reading.pageIdx';
const PATH_CHAR = 'reading.charOffset';

/** @since W1 */
export interface ReadingPosition {
  readonly bookId: string;
  readonly chapterId: string;
  readonly pageIdx: number;
  readonly charOffset: number;
}

/**
 * Facade providing ergonomic read/write access to the distributed reading position.
 * Automatically routes to SoulEngine (multi-device) or LocalFallback (single-device).
 * @since W1
 */
export class ReadingSoul {
  private static readonly engine = SoulEngine.getInstance();

  /**
   * Returns the current distributed reading position.
   * @since W1
   */
  static async currentBook(): Promise<ReadingSoulShape | null> {
    const engine = ReadingSoul.engine;
    if (!engine.isFallbackMode) {
      // Read from engine cache via subscribe-once pattern.
      return new Promise<ReadingSoulShape | null>((resolve) => {
        let resolved = false;
        const unsub = engine.subscribe<ReadingSoulShape>(PATH_BOOK, (v) => {
          if (!resolved) {
            resolved = true;
            unsub();
            resolve(v);
          }
        });
        // If no cached value, resolve null after microtask.
        Promise.resolve().then(() => {
          if (!resolved) {
            resolved = true;
            unsub();
            resolve(null);
          }
        });
      });
    }
    return LocalFallback.get<ReadingSoulShape>(PATH_BOOK, null as unknown as ReadingSoulShape);
  }

  /**
   * Write the current reading position to distributed storage.
   * @since W1
   */
  static async setPosition(
    bookId: string,
    chapterId: string,
    pageIdx: number,
    charOffset: number,
  ): Promise<void> {
    const engine = ReadingSoul.engine;
    if (!engine.isFallbackMode) {
      await engine.update(PATH_BOOK, bookId);
      await engine.update(PATH_CHAPTER, chapterId);
      await engine.update(PATH_PAGE, pageIdx);
      await engine.update(PATH_CHAR, charOffset);
    } else {
      await LocalFallback.set(PATH_BOOK, bookId);
      await LocalFallback.set(PATH_CHAPTER, chapterId);
      await LocalFallback.set(PATH_PAGE, pageIdx);
      await LocalFallback.set(PATH_CHAR, charOffset);
    }
  }

  /**
   * Subscribe to any change in reading position across devices.
   * Returns an unsubscribe function.
   * @since W1
   */
  static observe(listener: SoulListener<ReadingPosition>): () => void {
    const engine = ReadingSoul.engine;
    const state: ReadingPosition = {
      bookId: '',
      chapterId: '',
      pageIdx: 0,
      charOffset: 0,
    };
    const emit = () => {
      if (state.bookId) {
        try { listener({ ...state }); } catch (_e) { /* swallow */ }
      }
    };

    if (!engine.isFallbackMode) {
      const u1 = engine.subscribe<string>(PATH_BOOK, (v) => { (state as { bookId: string }).bookId = v; emit(); });
      const u2 = engine.subscribe<string>(PATH_CHAPTER, (v) => { (state as { chapterId: string }).chapterId = v; emit(); });
      const u3 = engine.subscribe<number>(PATH_PAGE, (v) => { (state as { pageIdx: number }).pageIdx = v; emit(); });
      const u4 = engine.subscribe<number>(PATH_CHAR, (v) => { (state as { charOffset: number }).charOffset = v; emit(); });
      return () => { u1(); u2(); u3(); u4(); };
    } else {
      const u1 = LocalFallback.subscribe<string>(PATH_BOOK, (v) => { (state as { bookId: string }).bookId = v; emit(); });
      const u2 = LocalFallback.subscribe<string>(PATH_CHAPTER, (v) => { (state as { chapterId: string }).chapterId = v; emit(); });
      const u3 = LocalFallback.subscribe<number>(PATH_PAGE, (v) => { (state as { pageIdx: number }).pageIdx = v; emit(); });
      const u4 = LocalFallback.subscribe<number>(PATH_CHAR, (v) => { (state as { charOffset: number }).charOffset = v; emit(); });
      return () => { u1(); u2(); u3(); u4(); };
    }
  }
}
