// L3 Feature - Account - Adapter
import { AccountViewModel } from '../viewmodel/AccountViewModel';
import { Me } from './Me';

/**
 * Adapter shim for the Me (account hub) page. Owns AccountViewModel lifecycle
 * and wires it to the IntentBus. Existing Me component is composed unchanged.
 * Covers: Me, Login, Onboarding, Subscriptions (W1 scope — not RefundFlow/Contact).
 * VM auto-subscribes on construction; onDestroy() unsubscribes.
 * W2 routing will point to this adapter instead of Me directly.
 */
@Component
export struct MeAdapter {
  private vm: AccountViewModel = new AccountViewModel();

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    Me()
  }
}
