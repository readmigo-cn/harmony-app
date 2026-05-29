// L3 Feature - Reader - Adapter
import { ReaderViewModel } from '../viewmodel/ReaderViewModel';
import { Reader } from './Reader';
import type { ReaderRouteParams } from '../../../core/router/RouteConstants';

/**
 * Adapter shim that owns the ReaderViewModel lifecycle and wires it
 * to the IntentBus. The existing Reader component is composed unchanged.
 * VM auto-subscribes on construction; onDestroy() unsubscribes.
 * W2 routing will point to this adapter instead of Reader directly.
 */
@Component
export struct ReaderAdapter {
  @Prop params: ReaderRouteParams;

  private vm: ReaderViewModel = new ReaderViewModel();

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    Reader({ params: this.params })
  }
}
