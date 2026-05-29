// L3 Feature - Audiobook - Adapter
import { AudiobookViewModel } from '../viewmodel/AudiobookViewModel';
import { AudiobookTab } from './AudiobookTab';

/**
 * Adapter shim that owns the AudiobookViewModel lifecycle and wires it
 * to the IntentBus. Covers AudiobookTab + AudiobookPlayer intent routing.
 * The existing AudiobookTab component is composed unchanged.
 * W2 routing will point to this adapter instead of AudiobookTab directly.
 */
@Component
export struct AudiobookTabAdapter {
  private vm: AudiobookViewModel = new AudiobookViewModel();
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsubscribe = this.vm.init();
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = null;
  }

  build() {
    AudiobookTab()
  }
}
