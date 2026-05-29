// L4 Feature - Authors - Page
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { AuthorsViewModel } from '../viewmodel/AuthorsViewModel';
import type { AuthorsData } from '../viewmodel/AuthorsViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeLoadFollowingAuthorsIntent, makeOpenAuthorProfileIntent } from '../intent/AuthorsIntents';
import type { Author } from '../service/AuthorsService';

@Entry
@Component
export struct FollowingAuthorsPage {
  @State private state: ViewModelState<AuthorsData> = { status: 'idle' };
  private vm: AuthorsViewModel = new AuthorsViewModel();

  aboutToAppear(): void {
    IntentBus.getInstance().publish(makeLoadFollowingAuthorsIntent() as never);
    this.syncState();
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  private syncState(): void {
    this.state = this.vm.getState() as ViewModelState<AuthorsData>;
  }

  private openProfile(authorId: string): void {
    AppStorage.SetOrCreate('authors_selected_id', authorId);
    IntentBus.getInstance().publish(makeOpenAuthorProfileIntent(authorId) as never);
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
            .onClick(() => IntentBus.getInstance().publish(makeLoadFollowingAuthorsIntent() as never))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          if (!this.state.data.following || this.state.data.following.length === 0) {
            Column({ space: AppSpacing.base }) {
              Text('还没有关注的作者').fontSize(AppFontSize.md).fontColor(AppColors.textTertiary)
              Text('去发现更多作者').fontSize(AppFontSize.sm).fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            List({ space: AppSpacing.sm }) {
              ForEach(this.state.data.following, (author: Author) => {
                ListItem() {
                  Row({ space: AppSpacing.base }) {
                    Image(author.avatarUrl)
                      .width(48)
                      .height(48)
                      .borderRadius(24)
                      .backgroundColor(AppColors.bgSecondary)
                    Column({ space: AppSpacing.xs }) {
                      Text(author.name)
                        .fontSize(AppFontSize.md)
                        .fontWeight(AppFontWeight.medium)
                        .fontColor(AppColors.textPrimary)
                      Text(`${author.bookCount} 部作品`)
                        .fontSize(AppFontSize.xs)
                        .fontColor(AppColors.textSecondary)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    Text('>')
                      .fontSize(AppFontSize.sm)
                      .fontColor(AppColors.textTertiary)
                  }
                  .width('100%')
                  .padding(AppSpacing.base)
                  .backgroundColor(AppColors.bgPrimary)
                  .borderRadius(AppRadius.base)
                  .onClick(() => this.openProfile(author.id))
                }
              })
            }
            .layoutWeight(1)
            .padding({ left: AppSpacing.base, right: AppSpacing.base })
            .divider({ strokeWidth: 1, color: AppColors.divider })
          }
        }
        .width('100%')
        .height('100%')
      }
    }
    .title('关注的作者')
  }
}
