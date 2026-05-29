// L4 Feature - Quotes - Adapter
// Owns QuotesViewModel lifecycle and wires it to QuotesPage + QuoteDetailPage.
import { QuotesViewModel } from '../viewmodel/QuotesViewModel';
import type { QuotesState } from '../viewmodel/QuotesViewModel';
import { QuotesPage } from './QuotesPage';
import { QuoteDetailPage } from './QuoteDetailPage';

@Component
export struct QuotesPageAdapter {
  @State private vmState: QuotesState = { status: 'idle' };

  private vm: QuotesViewModel = new QuotesViewModel();

  aboutToAppear(): void {
    // vmState is driven by intent publish in QuotesPage
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    QuotesPage()
  }
}

@Component
export struct QuoteDetailAdapter {
  @State private vmState: QuotesState = { status: 'idle' };

  private vm: QuotesViewModel = new QuotesViewModel();

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    QuoteDetailPage({ vmState: this.vmState })
  }
}
