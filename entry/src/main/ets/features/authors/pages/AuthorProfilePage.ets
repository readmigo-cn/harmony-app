// L4 Feature - Authors - Page
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { AuthorsViewModel } from '../viewmodel/AuthorsViewModel';
import type { AuthorsData } from '../viewmodel/AuthorsViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeOpenAuthorProfileIntent, makeLoadRelatedAuthorsIntent, makeLoadAuthorReadingProgressIntent } from '../intent/AuthorsIntents';
import { AuthorBioCard } from '../components/AuthorBioCard';
import { AuthorBookGrid } from '../components/AuthorBookGrid';

@Entry
@Component
export struct AuthorProfilePage {
  @State private state: ViewModelState<AuthorsData> = { status: 'idle' };
  private vm: AuthorsViewModel = new AuthorsViewModel();
  private authorId: string = '';

  aboutToAppear(): void {
    this.authorId = (AppStorage.Get<string>('authors_selected_id')) ?? '';
    this.vm['state'] = { status: 'idle' };
    if (this.authorId) {
      IntentBus.getInstance().publish(makeOpenAuthorProfileIntent(this.authorId) as never);
      IntentBus.getInstance().publish(makeLoadRelatedAuthorsIntent(this.authorId) as never);
      IntentBus.getInstance().publish(makeLoadAuthorReadingProgressIntent(this.authorId) as never);
    }
    this.syncState();
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  private syncState(): void {
    this.state = this.vm.getState() as ViewModelState<AuthorsData>;
  }

  build() {
    NavDestination() {
      if (this.state.status === 'loading' || this.state.status === 'idle') {
        Column() {
          LoadingProgress().width(40).height(40).color(AppColors.brand)
          Text('加载中...').fontSize(AppFontSize.sm).fontColor(AppColors.textSecondary)
            .margin({ top: AppSpacing.sm })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.state.status === 'error') {
        Column({ space: AppSpacing.base }) {
          Text('加载失败').fontSize(AppFontSize.md).fontColor(AppColors.danger)
          Text(this.state.error.message).fontSize(AppFontSize.sm).fontColor(AppColors.textTertiary)
          Button('重试')
            .backgroundColor(AppColors.brand)
            .fontColor(AppColors.textInverse)
            .onClick(() => {
              if (this.authorId) {
                IntentBus.getInstance().publish(makeOpenAuthorProfileIntent(this.authorId) as never);
              }
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: AppSpacing.base }) {
            if (this.state.data.profile) {
              AuthorBioCard({ author: this.state.data.profile })
            }
            AuthorBookGrid({
              authorId: this.authorId,
              readingProgress: this.state.data.readingProgress ?? [],
            })
          }
          .width('100%')
          .padding({ bottom: AppSpacing.xl })
        }
        .width('100%')
        .height('100%')
      }
    }
    .title('作者详情')
  }
}
