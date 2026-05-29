// L1 - Foundation - Intent
// Discriminated-union Intent base and all W1 concrete intent definitions.
// kind strings follow <feature>.<verb> camelCase per intent-contract.md §1.2.

import type { SurfaceKind } from '../surface/SurfaceKind';

/**
 * Base shape for all intents. K is the discriminant string; P is the payload.
 * Intents are frozen at publish time — do not mutate after construction.
 * source is stamped by IntentBus from SurfaceContext; renderers must not set it.
 * @since W1
 */
export interface Intent<K extends string, P extends object> {
  readonly kind: K;
  readonly payload: P;
  /** Dedup key — same key within 1000ms is dropped. See intent-contract.md §4. */
  readonly idempotencyKey: string;
  /** Set by IntentBus at publish time, not by the renderer. */
  readonly source: SurfaceKind;
  readonly tsMs: number;
}

// ── Reader feature intents ──────────────────────────────────────────

/** @since W1 */
export interface TextRange {
  readonly startCharOffset: number;
  readonly endCharOffset: number;
  readonly chapterId: string;
}

/** @since W1 */
export type OpenBookIntent = Intent<'reader.openBook', { bookId: string }>;

/** @since W1 */
export type JumpToChapterIntent = Intent<'reader.jumpToChapter', { chapterId: string }>;

/** @since W1 */
export type JumpToPageIntent = Intent<'reader.jumpToPage', { pageIdx: number }>;

/** @since W1 */
export type SelectTextIntent = Intent<'reader.selectText', { range: TextRange }>;

/** @since W1 */
export type OpenHighlightLayerIntent = Intent<'reader.openHighlightLayer', Record<string, never>>;

/** @since W1 */
export type OpenTocSheetIntent = Intent<'reader.openTocSheet', Record<string, never>>;

/** @since W1 */
export type OpenReaderSettingsIntent = Intent<'reader.openSettings', Record<string, never>>;

/** @since W1 */
export type LookupWordIntent = Intent<'reader.lookupWord', { word: string; ctxSentence?: string }>;

// ── Discover feature intents ────────────────────────────────────────

/** @since W1 */
export type BrowseDiscoverIntent = Intent<'discover.browse', { tab?: string }>;

// ── Library feature intents ─────────────────────────────────────────

/** @since W1 */
export type OpenBookshelfIntent = Intent<'library.openBookshelf', Record<string, never>>;

// ── Account feature intents ─────────────────────────────────────────

/** @since W1 */
export type OpenAccountIntent = Intent<'account.open', Record<string, never>>;

/** @since W1 */
export type OpenSubscriptionsIntent = Intent<'account.openSubscriptions', Record<string, never>>;

// ── Audiobook feature intents ───────────────────────────────────────

/** @since W1 */
export type PlayAudiobookIntent = Intent<'audiobook.play', { bookId: string; chapterId?: string }>;

/** @since W1 */
export type PauseAudiobookIntent = Intent<'audiobook.pause', Record<string, never>>;

/**
 * Union of all W1 concrete intents.
 * @since W1
 */
export type AnyIntent =
  | OpenBookIntent
  | JumpToChapterIntent
  | JumpToPageIntent
  | SelectTextIntent
  | OpenHighlightLayerIntent
  | OpenTocSheetIntent
  | OpenReaderSettingsIntent
  | LookupWordIntent
  | BrowseDiscoverIntent
  | OpenBookshelfIntent
  | OpenAccountIntent
  | OpenSubscriptionsIntent
  | PlayAudiobookIntent
  | PauseAudiobookIntent;

/** Extract the kind string union from AnyIntent. @since W1 */
export type IntentKind = AnyIntent['kind'];
