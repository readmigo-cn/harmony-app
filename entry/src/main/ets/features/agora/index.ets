// features/agora - barrel
// Re-exports public surface only. ViewModel and Service are internal.
export { AgoraPage } from './pages/AgoraPage';
export { AgoraPageAdapter } from './pages/AgoraPageAdapter';
export type { AgoraPost, AgoraComment, AgoraState } from './viewmodel/AgoraViewModel';
export {
  AGORA_INTENT_KINDS,
  makeLoadTimelineIntent,
  makeOpenPostIntent,
  makeLikePostIntent,
  makeUnlikePostIntent,
  makeCreatePostIntent,
  makeLoadCommentsIntent,
  makeLikeCommentIntent,
  makeFollowAuthorIntent,
} from './intent/AgoraIntents';
export type { AgoraIntent, AgoraIntentKind } from './intent/AgoraIntents';
