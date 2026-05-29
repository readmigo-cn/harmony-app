// L2 - api/agora - Api
import { HttpClient } from '../client/HttpClient';

export interface AgoraPost {
  id: string;
  authorId: string;
  authorName: string;
  authorAvatarUrl?: string;
  text: string;
  mediaUrls?: string[];
  likeCount: number;
  commentCount: number;
  liked: boolean;
  createdAt: string;
}

export interface AgoraComment {
  id: string;
  postId: string;
  authorId: string;
  authorName: string;
  authorAvatarUrl?: string;
  text: string;
  likeCount: number;
  liked: boolean;
  createdAt: string;
}

export interface AgoraTimelineResponse {
  items: AgoraPost[];
  cursor?: string;
}

export interface AgoraCommentsResponse {
  items: AgoraComment[];
  cursor?: string;
}

/**
 * Agora (community) API client — mirrors iOS /agora/* endpoints.
 *   GET  /agora/posts?cursor=
 *   GET  /agora/posts/:id
 *   POST /agora/posts
 *   POST /agora/posts/:id/like
 *   DELETE /agora/posts/:id/like
 *   GET  /agora/posts/:id/comments?cursor=
 *   POST /agora/comments/:id/like
 *   POST /agora/authors/:id/follow
 */
export class AgoraApi {
  static getTimeline(cursor?: string): Promise<AgoraTimelineResponse> {
    const query: Record<string, string | number> = {};
    if (cursor) query.cursor = cursor;
    return HttpClient.get<AgoraTimelineResponse>('/agora/posts', query);
  }

  static getPost(postId: string): Promise<AgoraPost> {
    return HttpClient.get<AgoraPost>(`/agora/posts/${encodeURIComponent(postId)}`);
  }

  static createPost(text: string, mediaUrls?: string[]): Promise<AgoraPost> {
    const body: Record<string, string | string[]> = { text };
    if (mediaUrls && mediaUrls.length > 0) body.mediaUrls = mediaUrls;
    return HttpClient.post<AgoraPost>('/agora/posts', body);
  }

  static likePost(postId: string): Promise<void> {
    return HttpClient.post<void>(`/agora/posts/${encodeURIComponent(postId)}/like`);
  }

  static unlikePost(postId: string): Promise<void> {
    return HttpClient.delete<void>(`/agora/posts/${encodeURIComponent(postId)}/like`);
  }

  static getComments(postId: string, cursor?: string): Promise<AgoraCommentsResponse> {
    const query: Record<string, string | number> = {};
    if (cursor) query.cursor = cursor;
    return HttpClient.get<AgoraCommentsResponse>(
      `/agora/posts/${encodeURIComponent(postId)}/comments`,
      query,
    );
  }

  static likeComment(commentId: string): Promise<void> {
    return HttpClient.post<void>(`/agora/comments/${encodeURIComponent(commentId)}/like`);
  }

  static followAuthor(authorId: string): Promise<void> {
    return HttpClient.post<void>(`/agora/authors/${encodeURIComponent(authorId)}/follow`);
  }
}
