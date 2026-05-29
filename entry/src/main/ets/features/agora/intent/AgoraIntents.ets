// L3 - features/agora - Intent
//
// Agora feature intents are defined module-locally — they are NOT added to
// the AnyIntent union in core/intent/Intent.ets (that is W1's domain).
// The IntentBus accepts any Intent<K, P>, so these work without being in
// the union. Add to AnyIntent only when cross-feature intent routing is needed.

import type { Intent } from '../../../core/intent/Intent';

// ── Agora intent types ──────────────────────────────────────────────

export type LoadTimelineIntent = Intent<'agora.loadTimeline', { cursor?: string }>;
export type OpenPostIntent = Intent<'agora.openPost', { postId: string }>;
export type LikePostIntent = Intent<'agora.likePost', { postId: string }>;
export type UnlikePostIntent = Intent<'agora.unlikePost', { postId: string }>;
export type CreatePostIntent = Intent<'agora.createPost', { text: string; mediaUrls?: string[] }>;
export type LoadCommentsIntent = Intent<'agora.loadComments', { postId: string; cursor?: string }>;
export type LikeCommentIntent = Intent<'agora.likeComment', { commentId: string }>;
export type FollowAuthorIntent = Intent<'agora.followAuthor', { authorId: string }>;

export type AgoraIntent =
  | LoadTimelineIntent
  | OpenPostIntent
  | LikePostIntent
  | UnlikePostIntent
  | CreatePostIntent
  | LoadCommentsIntent
  | LikeCommentIntent
  | FollowAuthorIntent;

export type AgoraIntentKind = AgoraIntent['kind'];

export const AGORA_INTENT_KINDS: AgoraIntentKind[] = [
  'agora.loadTimeline',
  'agora.openPost',
  'agora.likePost',
  'agora.unlikePost',
  'agora.createPost',
  'agora.loadComments',
  'agora.likeComment',
  'agora.followAuthor',
];

function makeKey(kind: string, extra: string): string {
  return `${kind}:${extra}:${Date.now()}`;
}

export function makeLoadTimelineIntent(cursor?: string): LoadTimelineIntent {
  return {
    kind: 'agora.loadTimeline',
    payload: { cursor },
    idempotencyKey: makeKey('agora.loadTimeline', cursor ?? 'initial'),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeOpenPostIntent(postId: string): OpenPostIntent {
  return {
    kind: 'agora.openPost',
    payload: { postId },
    idempotencyKey: makeKey('agora.openPost', postId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLikePostIntent(postId: string): LikePostIntent {
  return {
    kind: 'agora.likePost',
    payload: { postId },
    idempotencyKey: makeKey('agora.likePost', postId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeUnlikePostIntent(postId: string): UnlikePostIntent {
  return {
    kind: 'agora.unlikePost',
    payload: { postId },
    idempotencyKey: makeKey('agora.unlikePost', postId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeCreatePostIntent(text: string, mediaUrls?: string[]): CreatePostIntent {
  return {
    kind: 'agora.createPost',
    payload: { text, mediaUrls },
    idempotencyKey: makeKey('agora.createPost', text.slice(0, 20)),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadCommentsIntent(postId: string, cursor?: string): LoadCommentsIntent {
  return {
    kind: 'agora.loadComments',
    payload: { postId, cursor },
    idempotencyKey: makeKey('agora.loadComments', `${postId}:${cursor ?? 'initial'}`),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLikeCommentIntent(commentId: string): LikeCommentIntent {
  return {
    kind: 'agora.likeComment',
    payload: { commentId },
    idempotencyKey: makeKey('agora.likeComment', commentId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeFollowAuthorIntent(authorId: string): FollowAuthorIntent {
  return {
    kind: 'agora.followAuthor',
    payload: { authorId },
    idempotencyKey: makeKey('agora.followAuthor', authorId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}
