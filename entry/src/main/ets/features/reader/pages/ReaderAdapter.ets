// L3 Feature - Reader - Adapter
import { ReaderViewModel } from '../viewmodel/ReaderViewModel';
import { Reader } from './Reader';
import type { ReaderRouteParams } from '../../../core/router/RouteConstants';
import { READER_INTENT_KINDS } from '../intent/ReaderIntents';
import { IntentBus } from '../../../core/intent/IntentBus';

/**
 * Adapter shim that owns the ReaderViewModel lifecycle and wires it
 * to the IntentBus. The existing Reader component is composed unchanged.
 * W2 routing will point to this adapter instead of Reader directly.
 */
@Component
export struct ReaderAdapter {
  @Prop params: ReaderRouteParams;

  private vm: ReaderViewModel = new ReaderViewModel();
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsubscribe = this.vm.init();
    // Drain any queued intents for reader kinds that arrived before this surface mounted.
    const bus = IntentBus.getInstance();
    for (const k of READER_INTENT_KINDS) {
      // subscribe triggers queue drain automatically inside IntentBus.subscribe
      // vm.init() already subscribes; this loop is intentionally a no-op here
      void k; // satisfy linter
    }
    void bus; // satisfy linter
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = null;
  }

  build() {
    Reader({ params: this.params })
  }
}
