/**
 * ReadingSession.ets — W3 阅读会话追踪 (extended from W7-C6 scaffold)
 *
 * Changes in W3:
 *   - start() now returns a sessionId string (UUID) stored in state for ViewModel tracking.
 *   - recordChapterChange / recordWordLookup accept sessionId for correctness across concurrent opens.
 *   - end(sessionId) finalises, pushes to ReadingProgressRepository, and syncs DistributedSoul.
 *   - onBackground / onForeground preserved; auto-end hook documented for Phase 5 wiring.
 */

import { ReadingApi } from '../../../api/reading/ReadingApi';
import {
  ReadingProgressRepository,
  ReadingProgress,
} from '../../../core/persistence/repositories/ReadingProgressRepository';
import { ReadingSoul } from '../../../core/distributed-soul/ReadingSoul';

export interface SessionInfo {
  sessionId: string;
  bookId: string;
  chapterId: string;
  chapterIndex: number;
  startedAt: number;
  activeMs: number;
  pagesRead: number;
  chaptersRead: number;
  wordsLooked: number;
  paused: boolean;
}

const AUTO_PAUSE_THRESHOLD_MS = 30_000;

function genId(): string {
  const part = (): string => Math.floor((1 + Math.random()) * 0x10000).toString(16).slice(1);
  return `${part()}${part()}-${part()}-${part()}-${part()}-${part()}${part()}${part()}`;
}

class ReadingSessionImpl {
  private sessions: Map<string, SessionInfo> = new Map();
  private lastTickTs: Map<string, number> = new Map();
  private backgroundedAt: number = 0;

  /**
   * Start a session for a book+chapter. Returns the local sessionId.
   * If a session for this bookId already exists it is resumed and its id returned.
   */
  start(bookId: string, chapterId: string): string {
    for (const [id, s] of this.sessions) {
      if (s.bookId === bookId) {
        if (s.paused) this.resumeSession(id);
        return id;
      }
    }
    const sessionId = genId();
    const now = Date.now();
    const info: SessionInfo = {
      sessionId,
      bookId,
      chapterId,
      chapterIndex: 0,
      startedAt: now,
      activeMs: 0,
      pagesRead: 0,
      chaptersRead: 0,
      wordsLooked: 0,
      paused: false,
    };
    this.sessions.set(sessionId, info);
    this.lastTickTs.set(sessionId, now);

    // Fire-and-forget API session creation; local sessionId is independent.
    ReadingApi.startSession(bookId).then((resp) => {
      const s = this.sessions.get(sessionId);
      if (s) (s as Record<string, unknown>)['remoteSessionId'] = resp.sessionId;
    }).catch(() => {});

    return sessionId;
  }

  /**
   * Record that the reader moved to a new chapter within this session.
   */
  recordChapterChange(sessionId: string, newChapterId: string): void {
    const s = this.sessions.get(sessionId);
    if (!s) return;
    if (newChapterId !== s.chapterId) {
      s.chaptersRead += 1;
      s.chapterId = newChapterId;
    }
  }

  /**
   * Record a dictionary / word-lookup event.
   */
  recordWordLookup(sessionId: string, word: string): void {
    const s = this.sessions.get(sessionId);
    if (!s) return;
    s.wordsLooked += 1;
    void word;
  }

  /**
   * Finalise a session: compute duration, persist to RDB, push to DistributedSoul.
   * Silent on errors — caller must not block on this.
   *
   * Phase 5 note: call from EntryAbility.onBackground via the ViewModel adapter.
   */
  async end(sessionId: string): Promise<void> {
    const s = this.sessions.get(sessionId);
    if (!s) return;
    this.sessions.delete(sessionId);
    this.lastTickTs.delete(sessionId);

    if (!s.paused) {
      const now = Date.now();
      const delta = now - (this.lastTickTs.get(sessionId) ?? now);
      if (delta > 0 && delta < AUTO_PAUSE_THRESHOLD_MS * 2) s.activeMs += delta;
    }

    // Persist progress to RDB
    try {
      const userId = '';
      const progressId = ReadingProgressRepository.makeId(userId, s.bookId);
      const now = Date.now();
      const existing = await ReadingProgressRepository.findByBook(userId, s.bookId);
      const progress: ReadingProgress = {
        id: progressId,
        userId,
        bookId: s.bookId,
        chapterId: s.chapterId,
        position: 0,
        percent: 0,
        durationMs: (existing?.durationMs ?? 0) + s.activeMs,
        updatedAt: now,
      };
      await ReadingProgressRepository.save(progress);
    } catch (_e) {}

    // Push to DistributedSoul
    try {
      await ReadingSoul.setPosition(s.bookId, s.chapterId, s.pagesRead, 0);
    } catch (_e) {}

    // Report to API
    const remoteId = (s as Record<string, unknown>)['remoteSessionId'] as string | undefined;
    if (remoteId) {
      ReadingApi.endSession(remoteId, {
        durationSeconds: Math.max(0, Math.round(s.activeMs / 1000)),
        pagesRead: s.pagesRead,
        chapterIndex: s.chapterIndex,
      }).catch(() => {});
    }
  }

  tick(sessionId: string): number {
    const s = this.sessions.get(sessionId);
    if (!s || s.paused) return s?.activeMs ?? 0;
    const now = Date.now();
    const last = this.lastTickTs.get(sessionId) ?? now;
    const delta = now - last;
    if (delta > 0 && delta < AUTO_PAUSE_THRESHOLD_MS * 2) s.activeMs += delta;
    this.lastTickTs.set(sessionId, now);
    return s.activeMs;
  }

  recordPageTurn(sessionId: string): void {
    const s = this.sessions.get(sessionId);
    if (s) s.pagesRead += 1;
  }

  getCurrentSession(sessionId: string): SessionInfo | null {
    const s = this.sessions.get(sessionId);
    if (!s) return null;
    return { ...s };
  }

  onBackground(): void {
    this.backgroundedAt = Date.now();
    for (const [id, s] of this.sessions) {
      this.tick(id);
      s.paused = true;
    }
  }

  onForeground(bookId?: string): void {
    const now = Date.now();
    const bgMs = this.backgroundedAt > 0 ? now - this.backgroundedAt : 0;
    this.backgroundedAt = 0;
    for (const [id, s] of this.sessions) {
      if (bookId && bookId !== s.bookId) continue;
      const last = bgMs > AUTO_PAUSE_THRESHOLD_MS ? now : now - bgMs;
      this.lastTickTs.set(id, last);
      s.paused = false;
    }
  }

  // ── Legacy compat (used by existing ViewModel before W3) ─────────────────────

  /** @deprecated Use start(bookId, chapterId) returning sessionId instead. */
  async startLegacy(bookId: string, chapterIndex: number): Promise<void> {
    this.start(bookId, String(chapterIndex));
  }

  /** @deprecated Use recordChapterChange(sessionId, newChapterId) instead. */
  recordChapterChangeLegacy(newIndex: number): void {
    for (const [id, s] of this.sessions) {
      this.recordChapterChange(id, String(newIndex));
      void s;
    }
  }

  /** @deprecated Use recordWordLookup(sessionId, word) instead. */
  recordWordLookupLegacy(): void {
    for (const [id] of this.sessions) this.recordWordLookup(id, '');
  }
}

export const ReadingSession = new ReadingSessionImpl();
