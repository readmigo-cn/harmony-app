// L4 Feature - Audiobook - PhoneSurface
// Adapter pattern: delegates to existing AudiobookTab page unchanged.

import { AudiobookViewModel } from '../viewmodel/AudiobookViewModel';
import { AudiobookTab } from '../pages/AudiobookTab';

@Component
export struct AudiobookPhoneSurface {
  @ObjectLink vm: AudiobookViewModel;

  build() {
    AudiobookTab()
  }
}
