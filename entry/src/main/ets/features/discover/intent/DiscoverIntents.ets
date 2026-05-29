// L3 Feature - Discover - Intent
import type { BrowseDiscoverIntent } from '../../../core/intent/Intent';
import { SurfaceKind } from '../../../core/surface/SurfaceKind';

export type { BrowseDiscoverIntent };

export type DiscoverIntent = BrowseDiscoverIntent;
export type DiscoverIntentKind = DiscoverIntent['kind'];

export const DISCOVER_INTENT_KINDS: DiscoverIntentKind[] = [
  'discover/browse',
];

export function makeBrowseDiscoverIntent(
  category: string | null = null,
  searchQuery: string | null = null,
  source: SurfaceKind = SurfaceKind.Phone,
): BrowseDiscoverIntent {
  return {
    kind: 'discover/browse',
    payload: { category, searchQuery },
    idempotencyKey: `discover/browse:${category ?? ''}:${searchQuery ?? ''}:${Date.now()}`,
    source,
    tsMs: Date.now(),
  };
}
