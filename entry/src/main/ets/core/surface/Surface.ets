// L1 - Foundation - Surface
// ArkUI component that delegates rendering to the surface-appropriate renderer.
//
// WHY ArkUI is imported here (the only ArkUI import in L1):
//   Surface is the single composition point that bridges the L1 intent/surface
//   contract with ArkUI's @Component model. Keeping it in L1 avoids duplicating
//   this dispatch logic across every L4 feature surface. The import is intentional
//   and load-bearing; it must not be moved to L4 without revisiting the registry pattern.

import { SurfaceContext } from './SurfaceContext';
import { SurfaceRegistry } from './SurfaceRegistry';
import type { FeatureViewModel } from '../intent/ViewModel';
import type { IntentKind } from '../intent/Intent';

/**
 * Generic surface-aware container component.
 * Resolves the correct renderer for the current device surface and feature state.
 *
 * Usage:
 *   Surface({ vm: myReaderViewModel, intentKind: 'reader/open-book' })
 *
 * The component does NOT own the VM lifecycle — callers must init/dispose the VM.
 * @since W1
 */
@Component
export struct Surface {
  // FeatureViewModel<object> is the widest erasure that satisfies the constraint.
  @ObjectLink vm: FeatureViewModel<object>;
  intentKind: IntentKind = 'reader/open-book';

  build() {
    Column() {
      // Resolve renderer at build time; re-evaluates if SurfaceContext changes.
      // @ts-ignore — builder ref invocation; type-safe at registration site.
      const renderer = SurfaceRegistry.resolve(SurfaceContext.current(), this.intentKind);
      if (renderer) {
        // Call the registered @Builder function with current state.
        renderer(this.vm.getState());
      } else {
        // Graceful degradation: show nothing if no renderer is registered.
        Text('No renderer registered for ' + this.intentKind + ' on ' + SurfaceContext.current())
          .fontSize(12)
          .fontColor('#FF0000');
      }
    }
  }
}
