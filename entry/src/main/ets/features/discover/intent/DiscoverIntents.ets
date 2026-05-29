// L3 Feature - Discover - Intent
import type { BrowseDiscoverIntent } from '../../../core/intent/Intent';

export type { BrowseDiscoverIntent };

export type DiscoverIntent = BrowseDiscoverIntent;
export type DiscoverIntentKind = DiscoverIntent['kind'];

export const DISCOVER_INTENT_KINDS: DiscoverIntentKind[] = [
  'discover.browse',
];

export function makeBrowseDiscoverIntent(tab?: string): BrowseDiscoverIntent {
  return {
    kind: 'discover.browse',
    payload: { tab },
    idempotencyKey: `discover.browse:${tab ?? ''}:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}
