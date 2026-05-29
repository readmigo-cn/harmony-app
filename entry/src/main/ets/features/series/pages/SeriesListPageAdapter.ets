// L4 Feature - Series - Adapter
import { SeriesViewModel } from '../viewmodel/SeriesViewModel';
import { SeriesListPage } from './SeriesListPage';

@Component
export struct SeriesListPageAdapter {
  private vm: SeriesViewModel = new SeriesViewModel();

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    SeriesListPage()
  }
}
