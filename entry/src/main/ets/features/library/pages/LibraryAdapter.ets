// L3 Feature - Library - Adapter
import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { Library } from './Library';

/**
 * Adapter shim that owns the LibraryViewModel lifecycle and wires it
 * to the IntentBus. The existing Library component is composed unchanged.
 * W2 routing will point to this adapter instead of Library directly.
 */
@Component
export struct LibraryAdapter {
  private vm: LibraryViewModel = new LibraryViewModel();
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsubscribe = this.vm.init();
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = null;
  }

  build() {
    Library()
  }
}
