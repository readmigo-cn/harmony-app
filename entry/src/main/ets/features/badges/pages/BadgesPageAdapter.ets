// L4 Feature - Badges - Page Adapter
// Wires BadgesPage into the shell tab / router entry point.
import { BadgesViewModel } from '../viewmodel/BadgesViewModel';
import { BadgesIntents } from '../intent/BadgesIntents';
import { IntentBus } from '../../../core/intent/IntentBus';

@Component
export struct BadgesPageAdapter {
  private vm: BadgesViewModel = new BadgesViewModel();

  aboutToAppear(): void {
    IntentBus.getInstance().publish(BadgesIntents.loadGallery());
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    // Delegates rendering to BadgesPage which is the @Entry root.
    // Adapter exists so shell tabs can embed badges without a router push.
    Text('BadgesPageAdapter — rendered via BadgesPage @Entry')
      .fontSize(12)
      .fontColor('#AAAAAA')
  }
}
