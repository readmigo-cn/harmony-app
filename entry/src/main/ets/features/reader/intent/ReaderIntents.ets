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
} from '../../../core/intent/Intent';

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

export type ReaderIntent =
  | OpenBookIntent
  | JumpToChapterIntent
  | JumpToPageIntent
  | SelectTextIntent
  | OpenHighlightLayerIntent
  | OpenTocSheetIntent
  | OpenReaderSettingsIntent
  | LookupWordIntent;

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
