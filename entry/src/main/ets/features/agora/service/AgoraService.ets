// L2 - features/agora - Service
import { AgoraApi } from '../../../api/agora/AgoraApi';
import type { AgoraPost, AgoraComment, AgoraTimelineResponse, AgoraCommentsResponse } from '../../../api/agora/AgoraApi';

export type { AgoraPost, AgoraComment, AgoraTimelineResponse, AgoraCommentsResponse };

/**
 * AgoraService — domain service for the community feed feature.
 * Singleton via AgoraService.shared. Returns plain values/Promises;
 * does not publish intents or know about state envelopes.
 */
export class AgoraService {
  static readonly shared: AgoraService = new AgoraService();

  private constructor() {}

  loadTimeline(cursor?: string): Promise<AgoraTimelineResponse> {
    return AgoraApi.getTimeline(cursor);
  }

  getPost(postId: string): Promise<AgoraPost> {
    return AgoraApi.getPost(postId);
  }

  createPost(text: string, mediaUrls?: string[]): Promise<AgoraPost> {
    return AgoraApi.createPost(text, mediaUrls);
  }

  likePost(postId: string): Promise<void> {
    return AgoraApi.likePost(postId);
  }

  unlikePost(postId: string): Promise<void> {
    return AgoraApi.unlikePost(postId);
  }

  loadComments(postId: string, cursor?: string): Promise<AgoraCommentsResponse> {
    return AgoraApi.getComments(postId, cursor);
  }

  likeComment(commentId: string): Promise<void> {
    return AgoraApi.likeComment(commentId);
  }

  followAuthor(authorId: string): Promise<void> {
    return AgoraApi.followAuthor(authorId);
  }
}
