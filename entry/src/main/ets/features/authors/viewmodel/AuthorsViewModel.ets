// L3 Feature - Authors - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import { AUTHORS_INTENT_KINDS } from '../intent/AuthorsIntents';
import type {
  OpenAuthorProfileIntent,
  LoadRelatedAuthorsIntent,
  FollowAuthorIntent,
  UnfollowAuthorIntent,
  LoadAuthorReadingProgressIntent,
} from '../intent/AuthorsIntents';
import { AuthorsService } from '../service/AuthorsService';
import type { Author, AuthorReadingProgress } from '../service/AuthorsService';

export interface AuthorsData {
  profile?: Author;
  related?: Author[];
  following?: Author[];
  readingProgress?: AuthorReadingProgress[];
}

export type AuthorsState = ViewModelState<AuthorsData>;

export class AuthorsViewModel extends FeatureViewModel<AuthorsData> {
  readonly kind = 'authors';

  constructor() {
    super(AUTHORS_INTENT_KINDS as never);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    switch (intent.kind) {
      case 'authors.openProfile':
        await this.handleOpenProfile(intent as unknown as OpenAuthorProfileIntent);
        break;
      case 'authors.loadRelated':
        await this.handleLoadRelated(intent as unknown as LoadRelatedAuthorsIntent);
        break;
      case 'authors.follow':
        await this.handleFollow(intent as unknown as FollowAuthorIntent);
        break;
      case 'authors.unfollow':
        await this.handleUnfollow(intent as unknown as FollowAuthorIntent);
        break;
      case 'authors.loadFollowing':
        await this.handleLoadFollowing();
        break;
      case 'authors.loadReadingProgress':
        await this.handleLoadReadingProgress(intent as unknown as LoadAuthorReadingProgressIntent);
        break;
      default:
        break;
    }
  }

  private async handleOpenProfile(intent: OpenAuthorProfileIntent): Promise<void> {
    const { authorId } = intent.payload;
    this.state = { status: 'loading' };
    try {
      const profile = await AuthorsService.getProfile(authorId);
      const current = this.state.status === 'data' ? this.state.data : {};
      this.state = { status: 'data', data: { ...current, profile } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_profile_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadRelated(intent: LoadRelatedAuthorsIntent): Promise<void> {
    const { authorId } = intent.payload;
    try {
      const related = await AuthorsService.getRelated(authorId);
      const current = this.state.status === 'data' ? this.state.data : {};
      this.state = { status: 'data', data: { ...current, related } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_related_failed', message: (e as Error).message } };
    }
  }

  private async handleFollow(intent: FollowAuthorIntent): Promise<void> {
    const { authorId } = intent.payload;
    try {
      await AuthorsService.follow(authorId);
      if (this.state.status === 'data' && this.state.data.profile?.id === authorId) {
        const profile = { ...this.state.data.profile, followed: true };
        this.state = { status: 'data', data: { ...this.state.data, profile } };
      }
    } catch (e) {
      this.state = { status: 'error', error: { code: 'follow_failed', message: (e as Error).message } };
    }
  }

  private async handleUnfollow(intent: FollowAuthorIntent): Promise<void> {
    const { authorId } = intent.payload;
    try {
      await AuthorsService.follow(authorId);
      if (this.state.status === 'data' && this.state.data.profile?.id === authorId) {
        const profile = { ...this.state.data.profile, followed: false };
        this.state = { status: 'data', data: { ...this.state.data, profile } };
      }
    } catch (e) {
      this.state = { status: 'error', error: { code: 'unfollow_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadFollowing(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const following = await AuthorsService.getFollowing();
      this.state = { status: 'data', data: { following } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_following_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadReadingProgress(intent: LoadAuthorReadingProgressIntent): Promise<void> {
    const { authorId } = intent.payload;
    try {
      const readingProgress = await AuthorsService.getReadingProgress(authorId);
      const current = this.state.status === 'data' ? this.state.data : {};
      this.state = { status: 'data', data: { ...current, readingProgress } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_progress_failed', message: (e as Error).message } };
    }
  }
}
