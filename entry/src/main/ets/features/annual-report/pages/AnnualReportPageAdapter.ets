// L4 Feature - AnnualReport - Page adapter shim
import { AnnualReportViewModel } from '../viewmodel/AnnualReportViewModel';
import { AnnualReportPage } from './AnnualReportPage';

@Component
export struct AnnualReportPageAdapter {
  private vm: AnnualReportViewModel = new AnnualReportViewModel();

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    AnnualReportPage()
  }
}
