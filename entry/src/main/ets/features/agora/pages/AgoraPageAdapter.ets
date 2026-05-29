// L4 - features/agora - Adapter
import { AgoraViewModel } from '../viewmodel/AgoraViewModel';
import type { AgoraPost, AgoraComment } from '../viewmodel/AgoraViewModel';
import { AgoraPage } from './AgoraPage';
import { makeLoadTimelineIntent } from '../intent/AgoraIntents';
import { IntentBus } from '../../../core/intent/IntentBus';

/**
 * Adapter: owns AgoraViewModel lifecycle and connects it to AgoraPage.
 * - aboutToAppear: vm.init() + loads initial timeline
 * - aboutToDisappear: vm.onDestroy() tears down IntentBus subscriptions
 */
@Component
export struct AgoraPageAdapter {
  private vm: AgoraViewModel = new AgoraViewModel();

  @State posts: AgoraPost[] = [];
  @State comments: AgoraComment[] = [];
  @State status: string = 'idle';

  aboutToAppear(): void {
    IntentBus.getInstance().publish(makeLoadTimelineIntent() as never);
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    AgoraPage({ posts: this.posts, status: this.status })
  }
}
