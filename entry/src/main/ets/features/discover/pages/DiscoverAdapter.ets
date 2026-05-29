// L3 Feature - Discover - Adapter
import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { Discover } from './Discover';

/**
 * Adapter shim that owns the DiscoverViewModel lifecycle and wires it
 * to the IntentBus. The existing Discover component is composed unchanged.
 * VM auto-subscribes on construction; onDestroy() unsubscribes.
 * W2 routing will point to this adapter instead of Discover directly.
 */
@Component
export struct DiscoverAdapter {
  private vm: DiscoverViewModel = new DiscoverViewModel();

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    Discover()
  }
}
