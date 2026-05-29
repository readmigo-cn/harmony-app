// L4 Feature - Authors - Adapter
import { AuthorsViewModel } from '../viewmodel/AuthorsViewModel';
import { AuthorProfilePage } from './AuthorProfilePage';

@Component
export struct AuthorProfilePageAdapter {
  private vm: AuthorsViewModel = new AuthorsViewModel();

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    AuthorProfilePage()
  }
}
