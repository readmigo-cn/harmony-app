// L3 Feature - Reader - Intent
import type {
  OpenBookIntent,
  JumpToChapterIntent,
  SelectTextIntent,
  LookupWordIntent,
} from '../../../core/intent/Intent';
import { SurfaceKind } from '../../../core/surface/SurfaceKind';

export type { OpenBookIntent, JumpToChapterIntent, SelectTextIntent, LookupWordIntent };

export type ReaderIntent =
  | OpenBookIntent
  | JumpToChapterIntent
  | SelectTextIntent
  | LookupWordIntent;

export type ReaderIntentKind = ReaderIntent['kind'];

export const READER_INTENT_KINDS: ReaderIntentKind[] = [
  'reader/open-book',
  'reader/jump-to-chapter',
  'reader/select-text',
  'reader/lookup-word',
];

function makeKey(kind: string, extra: string): string {
  return `${kind}:${extra}:${Date.now()}`;
}

export function makeOpenBookIntent(
  bookId: string,
  resumePosition: boolean = true,
  source: SurfaceKind = SurfaceKind.Phone,
): OpenBookIntent {
  return {
    kind: 'reader/open-book',
    payload: { bookId, resumePosition },
    idempotencyKey: makeKey('reader/open-book', bookId),
    source,
    tsMs: Date.now(),
  };
}

export function makeJumpToChapterIntent(
  bookId: string,
  chapterId: string,
  charOffset: number = 0,
  source: SurfaceKind = SurfaceKind.Phone,
): JumpToChapterIntent {
  return {
    kind: 'reader/jump-to-chapter',
    payload: { bookId, chapterId, charOffset },
    idempotencyKey: makeKey('reader/jump-to-chapter', `${bookId}:${chapterId}`),
    source,
    tsMs: Date.now(),
  };
}

export function makeSelectTextIntent(
  bookId: string,
  chapterId: string,
  startOffset: number,
  endOffset: number,
  selectedText: string,
  source: SurfaceKind = SurfaceKind.Phone,
): SelectTextIntent {
  return {
    kind: 'reader/select-text',
    payload: { bookId, chapterId, startOffset, endOffset, selectedText },
    idempotencyKey: makeKey('reader/select-text', `${bookId}:${chapterId}:${startOffset}`),
    source,
    tsMs: Date.now(),
  };
}

export function makeLookupWordIntent(
  word: string,
  context: string,
  bookId: string,
  chapterId: string,
  source: SurfaceKind = SurfaceKind.Phone,
): LookupWordIntent {
  return {
    kind: 'reader/lookup-word',
    payload: { word, context, bookId, chapterId },
    idempotencyKey: makeKey('reader/lookup-word', `${bookId}:${word}`),
    source,
    tsMs: Date.now(),
  };
}
