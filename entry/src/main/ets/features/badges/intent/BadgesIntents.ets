// L3 Feature - Badges - Intent
import type { Intent } from '../../../core/intent/Intent';

// ── Badges intent types ────────────────────────────────────────────────────

export type LoadGalleryIntent = Intent<'badges.loadGallery', Record<string, never>>;
export type OpenDetailIntent = Intent<'badges.openDetail', { badgeId: string }>;
export type LoadProgressIntent = Intent<'badges.loadProgress', Record<string, never>>;
export type CheckUnlockedIntent = Intent<'badges.checkUnlocked', Record<string, never>>;
export type LoadNextIntent = Intent<'badges.loadNext', Record<string, never>>;
export type ShareBadgeIntent = Intent<'badges.shareBadge', { badgeId: string }>;

export type BadgesIntent =
  | LoadGalleryIntent
  | OpenDetailIntent
  | LoadProgressIntent
  | CheckUnlockedIntent
  | LoadNextIntent
  | ShareBadgeIntent;

export type BadgesIntentKind = BadgesIntent['kind'];

export const BADGES_INTENT_KINDS: BadgesIntentKind[] = [
  'badges.loadGallery',
  'badges.openDetail',
  'badges.loadProgress',
  'badges.checkUnlocked',
  'badges.loadNext',
  'badges.shareBadge',
];

function makeKey(kind: string, extra: string): string {
  return `${kind}:${extra}:${Date.now()}`;
}

export const BadgesIntents = {
  loadGallery(): LoadGalleryIntent {
    return {
      kind: 'badges.loadGallery',
      payload: {},
      idempotencyKey: makeKey('badges.loadGallery', ''),
      source: 'phone' as never,
      tsMs: Date.now(),
    };
  },

  openDetail(badgeId: string): OpenDetailIntent {
    return {
      kind: 'badges.openDetail',
      payload: { badgeId },
      idempotencyKey: makeKey('badges.openDetail', badgeId),
      source: 'phone' as never,
      tsMs: Date.now(),
    };
  },

  loadProgress(): LoadProgressIntent {
    return {
      kind: 'badges.loadProgress',
      payload: {},
      idempotencyKey: makeKey('badges.loadProgress', ''),
      source: 'phone' as never,
      tsMs: Date.now(),
    };
  },

  checkUnlocked(): CheckUnlockedIntent {
    return {
      kind: 'badges.checkUnlocked',
      payload: {},
      idempotencyKey: makeKey('badges.checkUnlocked', ''),
      source: 'phone' as never,
      tsMs: Date.now(),
    };
  },

  loadNext(): LoadNextIntent {
    return {
      kind: 'badges.loadNext',
      payload: {},
      idempotencyKey: makeKey('badges.loadNext', ''),
      source: 'phone' as never,
      tsMs: Date.now(),
    };
  },

  shareBadge(badgeId: string): ShareBadgeIntent {
    return {
      kind: 'badges.shareBadge',
      payload: { badgeId },
      idempotencyKey: makeKey('badges.shareBadge', badgeId),
      source: 'phone' as never,
      tsMs: Date.now(),
    };
  },
};
