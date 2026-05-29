// L4 Feature - Library - PhoneSurface
// Adapter pattern: delegates to existing Library page unchanged.

import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { Library } from '../pages/Library';

@Component
export struct LibraryPhoneSurface {
  @ObjectLink vm: LibraryViewModel;

  build() {
    Library()
  }
}
