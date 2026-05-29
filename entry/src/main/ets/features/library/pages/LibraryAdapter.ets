// L3 Feature - Library - Adapter
import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { Library } from './Library';

/**
 * Adapter shim that owns the LibraryViewModel lifecycle and wires it
 * to the IntentBus. The existing Library component is composed unchanged.
 * VM auto-subscribes on construction; onDestroy() unsubscribes.
 * W2 routing will point to this adapter instead of Library directly.
 */
@Component
export struct LibraryAdapter {
  private vm: LibraryViewModel = new LibraryViewModel();

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    Library()
  }
}
