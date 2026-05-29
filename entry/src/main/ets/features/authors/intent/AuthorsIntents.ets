// L3 Feature - Authors - Intent
import type { Intent } from '../../../core/intent/Intent';

export type OpenAuthorProfileIntent = Intent<'authors.openProfile', { authorId: string }>;
export type LoadRelatedAuthorsIntent = Intent<'authors.loadRelated', { authorId: string }>;
export type FollowAuthorIntent = Intent<'authors.follow', { authorId: string }>;
export type UnfollowAuthorIntent = Intent<'authors.unfollow', { authorId: string }>;
export type LoadFollowingAuthorsIntent = Intent<'authors.loadFollowing', Record<string, never>>;
export type LoadAuthorReadingProgressIntent = Intent<'authors.loadReadingProgress', { authorId: string }>;

export type AuthorsIntent =
  | OpenAuthorProfileIntent
  | LoadRelatedAuthorsIntent
  | FollowAuthorIntent
  | UnfollowAuthorIntent
  | LoadFollowingAuthorsIntent
  | LoadAuthorReadingProgressIntent;

export type AuthorsIntentKind = AuthorsIntent['kind'];

export const AUTHORS_INTENT_KINDS: AuthorsIntentKind[] = [
  'authors.openProfile',
  'authors.loadRelated',
  'authors.follow',
  'authors.unfollow',
  'authors.loadFollowing',
  'authors.loadReadingProgress',
];

function makeKey(kind: string, extra: string): string {
  return `${kind}:${extra}:${Date.now()}`;
}

export function makeOpenAuthorProfileIntent(authorId: string): OpenAuthorProfileIntent {
  return {
    kind: 'authors.openProfile',
    payload: { authorId },
    idempotencyKey: makeKey('authors.openProfile', authorId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadRelatedAuthorsIntent(authorId: string): LoadRelatedAuthorsIntent {
  return {
    kind: 'authors.loadRelated',
    payload: { authorId },
    idempotencyKey: makeKey('authors.loadRelated', authorId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeFollowAuthorIntent(authorId: string): FollowAuthorIntent {
  return {
    kind: 'authors.follow',
    payload: { authorId },
    idempotencyKey: makeKey('authors.follow', authorId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeUnfollowAuthorIntent(authorId: string): UnfollowAuthorIntent {
  return {
    kind: 'authors.unfollow',
    payload: { authorId },
    idempotencyKey: makeKey('authors.unfollow', authorId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadFollowingAuthorsIntent(): LoadFollowingAuthorsIntent {
  return {
    kind: 'authors.loadFollowing',
    payload: {},
    idempotencyKey: makeKey('authors.loadFollowing', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadAuthorReadingProgressIntent(authorId: string): LoadAuthorReadingProgressIntent {
  return {
    kind: 'authors.loadReadingProgress',
    payload: { authorId },
    idempotencyKey: makeKey('authors.loadReadingProgress', authorId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}
