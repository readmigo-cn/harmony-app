// L1 - Foundation - DistributedSoul
// Typed shapes for all distributed state objects shared across devices.

/**
 * Lamport-ish logical timestamp for conflict resolution.
 * Triple: (deviceId, monotonic seq, wallClockMs) — last-writer-wins on compare.
 * @since W1
 */
export interface LamportTs {
  readonly deviceId: string;
  readonly seq: number;
  readonly wallClockMs: number;
}

/**
 * Discriminated-union tag for all soul types.
 * @since W1
 */
export type SoulKind = 'reading' | 'book' | 'chapter' | 'selection' | 'device';

/**
 * Text range within a chapter for selection / highlight sharing.
 * @since W1
 */
export interface TextRange {
  readonly startCharOffset: number;
  readonly endCharOffset: number;
  readonly chapterId: string;
}

/**
 * Reading progress for a single book, distributed across devices.
 * @since W1
 */
export interface ReadingSoul {
  readonly kind: 'reading';
  readonly schemaVersion: 1;
  readonly bookId: string;
  readonly chapterId: string;
  readonly pageIdx: number;
  readonly charOffset: number;
  readonly ts: LamportTs;
}

/**
 * Lightweight book metadata snapshot used in distributed context.
 * @since W1
 */
export interface BookSoul {
  readonly kind: 'book';
  readonly schemaVersion: 1;
  readonly bookId: string;
  readonly title: string;
  readonly coverUrl: string;
  readonly totalChapters: number;
  readonly ts: LamportTs;
}

/**
 * Chapter metadata for distributed chapter-jump navigation.
 * @since W1
 */
export interface ChapterSoul {
  readonly kind: 'chapter';
  readonly schemaVersion: 1;
  readonly chapterId: string;
  readonly bookId: string;
  readonly index: number;
  readonly title: string;
  readonly ts: LamportTs;
}

/**
 * Optimistic local text selection; prefer local on conflict (see SoulEngine).
 * @since W1
 */
export interface SelectionSoul {
  readonly kind: 'selection';
  readonly schemaVersion: 1;
  readonly sessionId: string;
  /** Conflict rule: prefer local optimistic value on range field. */
  readonly range: TextRange;
  readonly ts: LamportTs;
}

/**
 * Device presence entry in the distributed session.
 * @since W1
 */
export interface DeviceSoul {
  readonly kind: 'device';
  readonly schemaVersion: 1;
  readonly deviceId: string;
  readonly deviceName: string;
  readonly platform: string;
  readonly joinedAtMs: number;
  readonly ts: LamportTs;
}

/** Union of all soul shapes. @since W1 */
export type AnySoul = ReadingSoul | BookSoul | ChapterSoul | SelectionSoul | DeviceSoul;
