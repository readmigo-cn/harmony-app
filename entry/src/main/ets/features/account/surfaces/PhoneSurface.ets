// L4 Feature - Account - PhoneSurface
// Adapter pattern: delegates to existing Me page unchanged.

import { AccountViewModel } from '../viewmodel/AccountViewModel';
import { Me } from '../pages/Me';

@Component
export struct AccountPhoneSurface {
  @ObjectLink vm: AccountViewModel;

  build() {
    Me()
  }
}
