// L3 Feature - Library - Intent
import type { OpenBookshelfIntent } from '../../../core/intent/Intent';

export type { OpenBookshelfIntent };

export type LibraryIntent = OpenBookshelfIntent;
export type LibraryIntentKind = LibraryIntent['kind'];

export const LIBRARY_INTENT_KINDS: LibraryIntentKind[] = [
  'library.openBookshelf',
];

export function makeOpenBookshelfIntent(): OpenBookshelfIntent {
  return {
    kind: 'library.openBookshelf',
    payload: {},
    idempotencyKey: `library.openBookshelf:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}
