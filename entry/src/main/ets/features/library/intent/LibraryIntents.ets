// L3 Feature - Library - Intent
import type { OpenBookshelfIntent } from '../../../core/intent/Intent';
import { SurfaceKind } from '../../../core/surface/SurfaceKind';

export type { OpenBookshelfIntent };

export type LibraryIntent = OpenBookshelfIntent;
export type LibraryIntentKind = LibraryIntent['kind'];

export const LIBRARY_INTENT_KINDS: LibraryIntentKind[] = [
  'library/open-shelf',
];

export function makeOpenBookshelfIntent(
  shelfId: string | null = null,
  filterTag: string | null = null,
  source: SurfaceKind = SurfaceKind.Phone,
): OpenBookshelfIntent {
  return {
    kind: 'library/open-shelf',
    payload: { shelfId, filterTag },
    idempotencyKey: `library/open-shelf:${shelfId ?? ''}:${filterTag ?? ''}:${Date.now()}`,
    source,
    tsMs: Date.now(),
  };
}
