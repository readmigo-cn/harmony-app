// L4 Feature - Discover - PhoneSurface
// Adapter pattern: delegates to existing Discover page unchanged.

import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { Discover } from '../pages/Discover';

@Component
export struct DiscoverPhoneSurface {
  @ObjectLink vm: DiscoverViewModel;

  build() {
    Discover()
  }
}
