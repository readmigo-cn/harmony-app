// L3 Feature - Reader - Intent
import type {
  OpenBookIntent,
  JumpToChapterIntent,
  JumpToPageIntent,
  SelectTextIntent,
  OpenHighlightLayerIntent,
  OpenTocSheetIntent,
  OpenReaderSettingsIntent,
  LookupWordIntent,
  TextRange,
  Intent,
} from '../../../core/intent/Intent';
import type { HighlightColor } from '../../../model/Highlight';

export type {
  OpenBookIntent,
  JumpToChapterIntent,
  JumpToPageIntent,
  SelectTextIntent,
  OpenHighlightLayerIntent,
  OpenTocSheetIntent,
  OpenReaderSettingsIntent,
  LookupWordIntent,
  TextRange,
};

// ── W3 additional intents (module-local) ────────────────────────────

export interface SaveHighlightPayload {
  readonly bookId: string;
  readonly chapterId: string;
  readonly chapterIndex: number;
  readonly blockIndex: number;
  readonly startCharOffset: number;
  readonly endCharOffset: number;
  readonly text: string;
  readonly color: HighlightColor;
}

export type SaveHighlightIntent = Intent<'reader.saveHighlight', SaveHighlightPayload>;

export interface EditHighlightPayload {
  readonly highlightId: string;
  readonly bookId: string;
  readonly color?: HighlightColor;
  readonly note?: string;
}

export type EditHighlightIntent = Intent<'reader.editHighlight', EditHighlightPayload>;

export interface DeleteHighlightPayload {
  readonly highlightId: string;
  readonly bookId: string;
}

export type DeleteHighlightIntent = Intent<'reader.deleteHighlight', DeleteHighlightPayload>;

export interface SaveNotePayload {
  readonly bookId: string;
  readonly chapterId: string;
  readonly highlightId?: string;
  readonly noteId?: string;
  readonly content: string;
  readonly tags: string[];
}

export type SaveNoteIntent = Intent<'reader.saveNote', SaveNotePayload>;

// ── W3 bookmark intents (module-local) ─────────────────────────────

export interface SaveBookmarkPayload {
  readonly bookId: string;
  readonly chapterId: string;
  readonly pageIdx: number;
  readonly label?: string;
}

export type SaveBookmarkIntent = Intent<'reader.saveBookmark', SaveBookmarkPayload>;

export interface DeleteBookmarkPayload {
  readonly bookmarkId: string;
}

export type DeleteBookmarkIntent = Intent<'reader.deleteBookmark', DeleteBookmarkPayload>;

export type ReaderW3Intent =
  | SaveHighlightIntent
  | EditHighlightIntent
  | DeleteHighlightIntent
  | SaveNoteIntent
  | SaveBookmarkIntent
  | DeleteBookmarkIntent;

export type ReaderIntent =
  | OpenBookIntent
  | JumpToChapterIntent
  | JumpToPageIntent
  | SelectTextIntent
  | OpenHighlightLayerIntent
  | OpenTocSheetIntent
  | OpenReaderSettingsIntent
  | LookupWordIntent
  | SaveHighlightIntent
  | EditHighlightIntent
  | DeleteHighlightIntent
  | SaveNoteIntent
  | SaveBookmarkIntent
  | DeleteBookmarkIntent;

export type ReaderIntentKind = ReaderIntent['kind'];

export const READER_INTENT_KINDS: ReaderIntentKind[] = [
  'reader.openBook',
  'reader.jumpToChapter',
  'reader.jumpToPage',
  'reader.selectText',
  'reader.openHighlightLayer',
  'reader.openTocSheet',
  'reader.openSettings',
  'reader.lookupWord',
  'reader.saveHighlight',
  'reader.editHighlight',
  'reader.deleteHighlight',
  'reader.saveNote',
  'reader.saveBookmark',
  'reader.deleteBookmark',
];

function makeKey(kind: string, extra: string): string {
  return `${kind}:${extra}:${Date.now()}`;
}

export function makeOpenBookIntent(bookId: string): OpenBookIntent {
  return {
    kind: 'reader.openBook',
    payload: { bookId },
    idempotencyKey: makeKey('reader.openBook', bookId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeJumpToChapterIntent(chapterId: string): JumpToChapterIntent {
  return {
    kind: 'reader.jumpToChapter',
    payload: { chapterId },
    idempotencyKey: makeKey('reader.jumpToChapter', chapterId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeJumpToPageIntent(pageIdx: number): JumpToPageIntent {
  return {
    kind: 'reader.jumpToPage',
    payload: { pageIdx },
    idempotencyKey: makeKey('reader.jumpToPage', String(pageIdx)),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeSelectTextIntent(range: TextRange): SelectTextIntent {
  return {
    kind: 'reader.selectText',
    payload: { range },
    idempotencyKey: makeKey('reader.selectText', `${range.chapterId}:${range.startCharOffset}`),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeOpenHighlightLayerIntent(): OpenHighlightLayerIntent {
  return {
    kind: 'reader.openHighlightLayer',
    payload: {},
    idempotencyKey: makeKey('reader.openHighlightLayer', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeOpenTocSheetIntent(): OpenTocSheetIntent {
  return {
    kind: 'reader.openTocSheet',
    payload: {},
    idempotencyKey: makeKey('reader.openTocSheet', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeOpenReaderSettingsIntent(): OpenReaderSettingsIntent {
  return {
    kind: 'reader.openSettings',
    payload: {},
    idempotencyKey: makeKey('reader.openSettings', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLookupWordIntent(word: string, ctxSentence?: string): LookupWordIntent {
  return {
    kind: 'reader.lookupWord',
    payload: { word, ctxSentence },
    idempotencyKey: makeKey('reader.lookupWord', word),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeSaveHighlightIntent(payload: SaveHighlightPayload): SaveHighlightIntent {
  return {
    kind: 'reader.saveHighlight',
    payload,
    idempotencyKey: makeKey('reader.saveHighlight', `${payload.chapterId}:${payload.startCharOffset}`),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeEditHighlightIntent(payload: EditHighlightPayload): EditHighlightIntent {
  return {
    kind: 'reader.editHighlight',
    payload,
    idempotencyKey: makeKey('reader.editHighlight', payload.highlightId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeDeleteHighlightIntent(payload: DeleteHighlightPayload): DeleteHighlightIntent {
  return {
    kind: 'reader.deleteHighlight',
    payload,
    idempotencyKey: makeKey('reader.deleteHighlight', payload.highlightId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeSaveNoteIntent(payload: SaveNotePayload): SaveNoteIntent {
  return {
    kind: 'reader.saveNote',
    payload,
    idempotencyKey: makeKey('reader.saveNote', `${payload.bookId}:${payload.highlightId ?? 'no-hl'}:${Date.now()}`),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeSaveBookmarkIntent(payload: SaveBookmarkPayload): SaveBookmarkIntent {
  return {
    kind: 'reader.saveBookmark',
    payload,
    idempotencyKey: makeKey('reader.saveBookmark', `${payload.bookId}:${payload.pageIdx}`),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeDeleteBookmarkIntent(payload: DeleteBookmarkPayload): DeleteBookmarkIntent {
  return {
    kind: 'reader.deleteBookmark',
    payload,
    idempotencyKey: makeKey('reader.deleteBookmark', payload.bookmarkId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}
