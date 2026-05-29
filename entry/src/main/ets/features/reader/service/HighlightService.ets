/**
 * HighlightService.ets — W3 高亮管理 Service (extended from W8-C8 scaffold)
 *
 * Strategy:
 *   - Local-first: all reads hit ReadingHighlightRepository (RDB) then memory cache.
 *   - Writes go to RDB immediately, then enqueue cloud sync via ReadingApi.
 *   - sync queue: 5s debounce flush, exponential backoff on failure.
 *   - Cloud conflict resolution (list merge) remains server-wins except pending ops.
 */

import { ReadingApi } from '../../../api/reading/ReadingApi';
import {
  Highlight,
  CreateHighlightDto,
  UpdateHighlightDto,
  HighlightColor,
} from '../../../model/Highlight';
import { PreferencesManager } from '../../../core/persistence/PreferencesManager';
import {
  ReadingHighlightRepository,
  ReadingHighlight,
} from '../../../core/persistence/repositories/ReadingHighlightRepository';

// ── Sync queue types ──────────────────────────────────────────────────────────

type PendingOpKind = 'create' | 'update' | 'delete';

interface PendingOp {
  id: string;
  kind: PendingOpKind;
  payload?: CreateHighlightDto | UpdateHighlightDto;
  retries: number;
  enqueuedAt: number;
}

const QUEUE_KEY = 'highlight_pending_queue_v1';
const DEBOUNCE_MS = 5_000;
const BACKOFF_MS = [1_000, 2_000, 4_000, 8_000, 16_000];

// ── Domain model exposed to ui-dev and ViewModel ──────────────────────────────

export interface HighlightInput {
  bookId: string;
  chapterId: string;
  chapterIndex: number;
  blockIndex: number;
  charOffset: number;
  charLength: number;
  text: string;
  color: HighlightColor;
  note?: string;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function genId(): string {
  const part = (): string => Math.floor((1 + Math.random()) * 0x10000).toString(16).slice(1);
  return `${part()}${part()}-${part()}-${part()}-${part()}-${part()}${part()}${part()}`;
}

function repoToHighlight(r: ReadingHighlight): Highlight {
  return {
    id: r.id,
    bookId: r.bookId,
    chapterId: r.chapterId ?? undefined,
    blockIndex: r.blockIndex,
    charOffset: r.charOffset,
    charLength: r.charLength,
    text: r.text,
    color: (r.color as HighlightColor) ?? 'yellow',
    note: r.note ?? undefined,
    createdAt: new Date(r.createdAt).toISOString(),
    updatedAt: new Date(r.updatedAt).toISOString(),
  };
}

// ── Service singleton ─────────────────────────────────────────────────────────

class HighlightServiceImpl {
  private cache: Map<string, Highlight[]> = new Map();
  private pending: PendingOp[] = [];
  private debounceTimer: number = -1;
  private retryTimer: number = -1;
  private inited: boolean = false;

  async init(): Promise<void> {
    if (this.inited) return;
    this.inited = true;
    const raw = await PreferencesManager.getString(QUEUE_KEY, '');
    if (raw.length > 0) {
      try { this.pending = JSON.parse(raw) as PendingOp[]; } catch (_e) { this.pending = []; }
    }
    if (this.pending.length > 0) this.scheduleFlush();
  }

  /**
   * List highlights for a book + optional chapter filter.
   * Reads from RDB first; falls back to empty array on DB error.
   * ui-dev's HighlightLayer calls HighlightService.shared.list(bookId, chapterId).
   */
  async list(bookId: string, chapterId?: string): Promise<Highlight[]> {
    if (!bookId) return [];
    const cacheKey = chapterId ? `${bookId}:${chapterId}` : bookId;
    const cached = this.cache.get(cacheKey);
    if (cached) return cached.slice();

    try {
      const rows = chapterId
        ? await ReadingHighlightRepository.listByChapter(bookId, chapterId)
        : await ReadingHighlightRepository.listByBook(bookId);
      const list = rows.map(repoToHighlight).sort((a, b) => a.charOffset - b.charOffset);
      this.cache.set(cacheKey, list);
      return list.slice();
    } catch (_e) {
      return [];
    }
  }

  /**
   * Save a new highlight: writes to RDB, updates cache, enqueues cloud sync.
   * Returns the persisted Highlight with its generated id.
   */
  async save(input: HighlightInput): Promise<Highlight> {
    const id = genId();
    const now = Date.now();
    const isoNow = new Date(now).toISOString();

    const row: ReadingHighlight = {
      id,
      userId: '',
      bookId: input.bookId,
      chapterId: input.chapterId,
      blockIndex: input.blockIndex,
      charOffset: input.charOffset,
      charLength: input.charLength,
      text: input.text,
      color: input.color,
      note: input.note ?? null,
      createdAt: now,
      updatedAt: now,
    };
    await ReadingHighlightRepository.insert(row);

    const highlight: Highlight = {
      id,
      bookId: input.bookId,
      chapterId: input.chapterId,
      chapterIndex: input.chapterIndex,
      blockIndex: input.blockIndex,
      charOffset: input.charOffset,
      charLength: input.charLength,
      text: input.text,
      color: input.color,
      note: input.note,
      createdAt: isoNow,
      updatedAt: isoNow,
    };
    this.invalidateBookCache(input.bookId);

    const dto: CreateHighlightDto = {
      bookId: input.bookId,
      chapterId: input.chapterId,
      chapterIndex: input.chapterIndex,
      blockIndex: input.blockIndex,
      charOffset: input.charOffset,
      charLength: input.charLength,
      text: input.text,
      color: input.color,
      note: input.note,
    };
    this.enqueue({ id, kind: 'create', payload: dto, retries: 0, enqueuedAt: now });
    return highlight;
  }

  /**
   * Update color or note on an existing highlight.
   */
  async update(highlightId: string, patch: UpdateHighlightDto): Promise<void> {
    const now = Date.now();
    await ReadingHighlightRepository.updateNote(
      highlightId,
      patch.note ?? null,
      now,
    );
    this.invalidateAllCache();
    this.enqueue({ id: highlightId, kind: 'update', payload: patch, retries: 0, enqueuedAt: now });
  }

  /**
   * Delete a highlight by id.
   */
  async delete(highlightId: string): Promise<void> {
    await ReadingHighlightRepository.deleteById(highlightId);
    this.invalidateAllCache();
    this.enqueue({ id: highlightId, kind: 'delete', retries: 0, enqueuedAt: Date.now() });
  }

  /**
   * Text export of all highlights for a book (for share / backup).
   * Format: one line per highlight — "chapterId|offset|text|color|note".
   */
  async export(bookId: string): Promise<string> {
    const highlights = await this.list(bookId);
    const lines = highlights.map((h) => {
      const note = h.note ?? '';
      return `${h.chapterId ?? ''}|${h.charOffset}|${h.text}|${h.color}|${note}`;
    });
    return lines.join('\n');
  }

  /** Force-flush pending ops (call when app goes to background). */
  async flush(): Promise<void> {
    if (this.debounceTimer !== -1) { clearTimeout(this.debounceTimer); this.debounceTimer = -1; }
    if (this.retryTimer !== -1) { clearTimeout(this.retryTimer); this.retryTimer = -1; }
    if (this.pending.length === 0) return;

    const remaining: PendingOp[] = [];
    let anyFailed = false;
    for (const op of this.pending) {
      try { await this.runOp(op); } catch (_e) { op.retries += 1; anyFailed = true; remaining.push(op); }
    }
    this.pending = remaining;
    this.persistQueue();
    if (anyFailed) this.scheduleBackoffRetry();
  }

  /** Cloud pull + local merge (server wins except pending ids). */
  async sync(bookId: string): Promise<void> {
    if (!bookId) return;
    let server: Highlight[] = [];
    try { server = await ReadingApi.listHighlights(bookId); } catch (_e) { return; }
    const local = await this.list(bookId);
    const pendingIds = new Set(this.pending.map((op) => op.id));
    const merged: Map<string, Highlight> = new Map();
    for (const h of server) merged.set(h.id, h);
    for (const h of local) {
      if (!merged.has(h.id) && pendingIds.has(h.id)) merged.set(h.id, h);
    }
    const next: Highlight[] = [];
    merged.forEach((v) => next.push(v));
    this.cache.set(bookId, next);
  }

  // ── Internal ─────────────────────────────────────────────────────────────────

  private enqueue(op: PendingOp): void {
    this.pending.push(op);
    this.persistQueue();
    this.scheduleFlush();
  }

  private async runOp(op: PendingOp): Promise<void> {
    if (op.kind === 'create') { await ReadingApi.createHighlight(op.payload as CreateHighlightDto); return; }
    if (op.kind === 'update') { await ReadingApi.updateHighlight(op.id, op.payload as UpdateHighlightDto); return; }
    if (op.kind === 'delete') { await ReadingApi.deleteHighlight(op.id); return; }
  }

  private scheduleFlush(): void {
    if (this.debounceTimer !== -1) return;
    this.debounceTimer = setTimeout(() => { this.debounceTimer = -1; this.flush(); }, DEBOUNCE_MS) as unknown as number;
  }

  private scheduleBackoffRetry(): void {
    let maxRetry = 0;
    for (const op of this.pending) { if (op.retries > maxRetry) maxRetry = op.retries; }
    const idx = Math.min(maxRetry, BACKOFF_MS.length - 1);
    if (this.retryTimer !== -1) return;
    this.retryTimer = setTimeout(() => { this.retryTimer = -1; this.flush(); }, BACKOFF_MS[idx]) as unknown as number;
  }

  private persistQueue(): void { PreferencesManager.setString(QUEUE_KEY, JSON.stringify(this.pending)); }

  private invalidateBookCache(bookId: string): void {
    for (const key of this.cache.keys()) {
      if (key === bookId || key.startsWith(`${bookId}:`)) this.cache.delete(key);
    }
  }

  private invalidateAllCache(): void { this.cache.clear(); }
}

export const HighlightService = new HighlightServiceImpl();
export { HighlightColor };
