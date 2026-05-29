// L3 Feature - Badges - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import { BADGES_INTENT_KINDS } from '../intent/BadgesIntents';
import type { BadgesIntent, OpenDetailIntent, ShareBadgeIntent } from '../intent/BadgesIntents';
import { BadgesService } from '../service/BadgesService';
import type { Badge, BadgeProgress } from '../service/BadgesService';

export interface BadgesState {
  status: 'idle' | 'loading' | 'data' | 'error';
  gallery?: Badge[];
  inProgress?: BadgeProgress[];
  selected?: Badge;
  nextBadge?: BadgeProgress;
  newlyUnlocked?: Badge[];
  error?: { code: string; message: string };
}

export type BadgesVMState = ViewModelState<BadgesState>;

export class BadgesViewModel extends FeatureViewModel<BadgesState> {
  readonly kind = 'badges';

  @State state: BadgesVMState = { status: 'idle' };

  constructor() {
    super(BADGES_INTENT_KINDS as never);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    const i = intent as unknown as BadgesIntent;
    switch (i.kind) {
      case 'badges.loadGallery':
        await this.handleLoadGallery();
        break;
      case 'badges.openDetail':
        await this.handleOpenDetail(i as OpenDetailIntent);
        break;
      case 'badges.loadProgress':
        await this.handleLoadProgress();
        break;
      case 'badges.checkUnlocked':
        await this.handleCheckUnlocked();
        break;
      case 'badges.loadNext':
        await this.handleLoadNext();
        break;
      case 'badges.shareBadge':
        this.handleShareBadge(i as ShareBadgeIntent);
        break;
      default:
        break;
    }
  }

  private async handleLoadGallery(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const items = await BadgesService.fetchGallery();
      const gallery = items.map((b) => ({
        id: b.id,
        name: b.name,
        description: b.description,
        tier: b.tier,
        modelKey: b.modelKey,
      }));
      const inProgress = items.map((b) => b.progress);
      this.state = { status: 'data', data: { status: 'data', gallery, inProgress } };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'load_gallery_failed', message: (e as Error).message },
      };
    }
  }

  private async handleOpenDetail(intent: OpenDetailIntent): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const badge = await BadgesService.fetchDetail(intent.payload.badgeId);
      const prev = this.state.status === 'data' ? this.state.data : ({ status: 'idle' } as BadgesState);
      this.state = { status: 'data', data: { ...prev, status: 'data', selected: badge } };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'load_detail_failed', message: (e as Error).message },
      };
    }
  }

  private async handleLoadProgress(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const inProgress = await BadgesService.fetchProgress();
      const prev = this.state.status === 'data' ? this.state.data : ({ status: 'idle' } as BadgesState);
      this.state = { status: 'data', data: { ...prev, status: 'data', inProgress } };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'load_progress_failed', message: (e as Error).message },
      };
    }
  }

  private async handleCheckUnlocked(): Promise<void> {
    try {
      const newlyUnlocked = await BadgesService.checkNewlyUnlocked();
      const prev = this.state.status === 'data' ? this.state.data : ({ status: 'idle' } as BadgesState);
      this.state = { status: 'data', data: { ...prev, status: 'data', newlyUnlocked } };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'check_unlocked_failed', message: (e as Error).message },
      };
    }
  }

  private async handleLoadNext(): Promise<void> {
    try {
      const nextBadge = await BadgesService.fetchNextBadge();
      const prev = this.state.status === 'data' ? this.state.data : ({ status: 'idle' } as BadgesState);
      this.state = { status: 'data', data: { ...prev, status: 'data', nextBadge } };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'load_next_failed', message: (e as Error).message },
      };
    }
  }

  private handleShareBadge(intent: ShareBadgeIntent): void {
    // Share is handled at L4 via system share sheet; VM records which badge was shared
    const prev = this.state.status === 'data' ? this.state.data : ({ status: 'idle' } as BadgesState);
    this.state = { status: 'data', data: { ...prev, status: 'data' } };
  }
}
