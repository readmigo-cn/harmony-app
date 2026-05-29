// L4 Feature - Reader - Adapter
// Owns all 3 VMs as separate @State fields; wires each to the IntentBus.
import { ReaderViewModel } from '../viewmodel/ReaderViewModel';
import { ReaderLookupViewModel } from '../viewmodel/ReaderLookupViewModel';
import { ReaderProgressViewModel } from '../viewmodel/ReaderProgressViewModel';
import { Reader } from './Reader';
import type { ReaderRouteParams } from '../../../core/router/RouteConstants';

@Component
export struct ReaderAdapter {
  @Prop params: ReaderRouteParams;

  @State private vm: ReaderViewModel = new ReaderViewModel();
  @State private lookupVm: ReaderLookupViewModel = this.vm.lookupVm;
  @State private progressVm: ReaderProgressViewModel = this.vm.progressVm;

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    Reader({ params: this.params })
  }
}
