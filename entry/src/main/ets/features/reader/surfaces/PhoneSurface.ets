// L4 Feature - Reader - PhoneSurface
// Adapter pattern: delegates to existing Reader page unchanged.

import { ReaderViewModel } from '../viewmodel/ReaderViewModel';
import { Reader } from '../pages/Reader';
import type { ReaderRouteParams } from '../../../core/router/RouteConstants';

@Component
export struct ReaderPhoneSurface {
  @ObjectLink vm: ReaderViewModel;
  params: ReaderRouteParams = { bookId: '' };

  build() {
    Reader({ params: this.params })
  }
}
