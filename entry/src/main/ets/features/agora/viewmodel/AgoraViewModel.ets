// L3 - features/agora - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import type { IntentKind } from '../../../core/intent/ViewModel';
import { AgoraService } from '../service/AgoraService';
import type { AgoraPost, AgoraComment } from '../service/AgoraService';
import { AGORA_INTENT_KINDS } from '../intent/AgoraIntents';
import type {
  LoadTimelineIntent,
  OpenPostIntent,
  LikePostIntent,
  UnlikePostIntent,
  CreatePostIntent,
  LoadCommentsIntent,
  LikeCommentIntent,
  FollowAuthorIntent,
} from '../intent/AgoraIntents';

export type { AgoraPost, AgoraComment };

export interface AgoraState {
  status: 'idle' | 'loading' | 'data' | 'error';
  timeline?: AgoraPost[];
  cursor?: string;
  selectedPost?: AgoraPost;
  comments?: AgoraComment[];
  error?: { code: string; message: string };
}

export type AgoraVMState = ViewModelState<AgoraState>;

export class AgoraViewModel extends FeatureViewModel<AgoraState> {
  readonly kind = 'agora';

  constructor() {
    // Agora kinds are not in the W1 AnyIntent union; cast required since
    // IntentBus.subscribe is keyed by IntentKind. The bus accepts any string key
    // at runtime — the cast is safe because bus dispatches by kind string only.
    super(AGORA_INTENT_KINDS as unknown as IntentKind[]);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    switch (intent.kind) {
      case 'agora.loadTimeline':
        await this.handleLoadTimeline(intent as unknown as LoadTimelineIntent);
        break;
      case 'agora.openPost':
        await this.handleOpenPost(intent as unknown as OpenPostIntent);
        break;
      case 'agora.likePost':
        await this.handleLikePost(intent as unknown as LikePostIntent);
        break;
      case 'agora.unlikePost':
        await this.handleUnlikePost(intent as unknown as UnlikePostIntent);
        break;
      case 'agora.createPost':
        await this.handleCreatePost(intent as unknown as CreatePostIntent);
        break;
      case 'agora.loadComments':
        await this.handleLoadComments(intent as unknown as LoadCommentsIntent);
        break;
      case 'agora.likeComment':
        await this.handleLikeComment(intent as unknown as LikeCommentIntent);
        break;
      case 'agora.followAuthor':
        await this.handleFollowAuthor(intent as unknown as FollowAuthorIntent);
        break;
      default:
        break;
    }
  }

  private async handleLoadTimeline(intent: LoadTimelineIntent): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const resp = await AgoraService.shared.loadTimeline(intent.payload.cursor);
      this.state = {
        status: 'data',
        data: { status: 'data', timeline: resp.items, cursor: resp.cursor },
      };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'load_timeline_failed', message: (e as Error).message },
      };
    }
  }

  private async handleOpenPost(intent: OpenPostIntent): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const post = await AgoraService.shared.getPost(intent.payload.postId);
      const prev = this.state.status === 'data' ? this.state.data : undefined;
      this.state = {
        status: 'data',
        data: { ...(prev ?? { status: 'data' }), status: 'data', selectedPost: post },
      };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'open_post_failed', message: (e as Error).message },
      };
    }
  }

  private async handleLikePost(intent: LikePostIntent): Promise<void> {
    try {
      await AgoraService.shared.likePost(intent.payload.postId);
      if (this.state.status === 'data') {
        const data = this.state.data;
        const timeline = data.timeline?.map((p) =>
          p.id === intent.payload.postId
            ? { ...p, liked: true, likeCount: p.likeCount + 1 }
            : p,
        );
        this.state = { status: 'data', data: { ...data, timeline } };
      }
    } catch (e) {
      // optimistic update failure: no state change, surface may show toast
    }
  }

  private async handleUnlikePost(intent: UnlikePostIntent): Promise<void> {
    try {
      await AgoraService.shared.unlikePost(intent.payload.postId);
      if (this.state.status === 'data') {
        const data = this.state.data;
        const timeline = data.timeline?.map((p) =>
          p.id === intent.payload.postId
            ? { ...p, liked: false, likeCount: Math.max(0, p.likeCount - 1) }
            : p,
        );
        this.state = { status: 'data', data: { ...data, timeline } };
      }
    } catch (e) {
      // optimistic update failure: surface may show toast
    }
  }

  private async handleCreatePost(intent: CreatePostIntent): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const post = await AgoraService.shared.createPost(
        intent.payload.text,
        intent.payload.mediaUrls,
      );
      const prev = this.state.status === 'data' ? this.state.data : { status: 'data' as const };
      const timeline = [post, ...(prev.timeline ?? [])];
      this.state = { status: 'data', data: { ...prev, status: 'data', timeline } };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'create_post_failed', message: (e as Error).message },
      };
    }
  }

  private async handleLoadComments(intent: LoadCommentsIntent): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const resp = await AgoraService.shared.loadComments(
        intent.payload.postId,
        intent.payload.cursor,
      );
      const prev = this.state.status === 'data' ? this.state.data : { status: 'data' as const };
      this.state = {
        status: 'data',
        data: { ...prev, status: 'data', comments: resp.items, cursor: resp.cursor },
      };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'load_comments_failed', message: (e as Error).message },
      };
    }
  }

  private async handleLikeComment(intent: LikeCommentIntent): Promise<void> {
    try {
      await AgoraService.shared.likeComment(intent.payload.commentId);
      if (this.state.status === 'data') {
        const data = this.state.data;
        const comments = data.comments?.map((c) =>
          c.id === intent.payload.commentId
            ? { ...c, liked: true, likeCount: c.likeCount + 1 }
            : c,
        );
        this.state = { status: 'data', data: { ...data, comments } };
      }
    } catch (e) {
      // optimistic update failure
    }
  }

  private async handleFollowAuthor(intent: FollowAuthorIntent): Promise<void> {
    try {
      await AgoraService.shared.followAuthor(intent.payload.authorId);
    } catch (e) {
      // follow failure is non-critical; surface may show toast
    }
  }
}
