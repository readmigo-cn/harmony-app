// L4 Feature - Series - Page
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { SeriesViewModel } from '../viewmodel/SeriesViewModel';
import type { SeriesData } from '../viewmodel/SeriesViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeOpenSeriesDetailIntent } from '../intent/SeriesIntents';
import type { SeriesBook } from '../service/SeriesService';

@Entry
@Component
export struct SeriesDetailPage {
  @State private state: ViewModelState<SeriesData> = { status: 'idle' };
  private vm: SeriesViewModel = new SeriesViewModel();
  private seriesId: string = '';

  aboutToAppear(): void {
    this.seriesId = (AppStorage.Get<string>('series_selected_id')) ?? '';
    if (this.seriesId) {
      IntentBus.getInstance().publish(makeOpenSeriesDetailIntent(this.seriesId) as never);
    }
    this.syncState();
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  private syncState(): void {
    this.state = this.vm.getState() as ViewModelState<SeriesData>;
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
              if (this.seriesId) {
                IntentBus.getInstance().publish(makeOpenSeriesDetailIntent(this.seriesId) as never);
              }
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: AppSpacing.base }) {
            if (this.state.data.selected) {
              Column({ space: AppSpacing.xs }) {
                Text(this.state.data.selected.title)
                  .fontSize(AppFontSize.xl)
                  .fontWeight(AppFontWeight.bold)
                  .fontColor(AppColors.textPrimary)
                Text(`共 ${this.state.data.selected.bookCount} 册`)
                  .fontSize(AppFontSize.sm)
                  .fontColor(AppColors.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.base })

              List({ space: AppSpacing.sm }) {
                ForEach(this.state.data.selected.books, (book: SeriesBook) => {
                  ListItem() {
                    Row({ space: AppSpacing.base }) {
                      Text(`${book.order}`)
                        .width(32)
                        .height(32)
                        .textAlign(TextAlign.Center)
                        .fontSize(AppFontSize.sm)
                        .fontColor(AppColors.textInverse)
                        .backgroundColor(AppColors.brand)
                        .borderRadius(16)
                      Text(book.title)
                        .fontSize(AppFontSize.md)
                        .fontColor(AppColors.textPrimary)
                        .layoutWeight(1)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .width('100%')
                    .padding(AppSpacing.base)
                    .backgroundColor(AppColors.bgPrimary)
                    .borderRadius(AppRadius.base)
                    .alignItems(VerticalAlign.Center)
                  }
                })
              }
              .padding({ left: AppSpacing.base, right: AppSpacing.base })
              .divider({ strokeWidth: 1, color: AppColors.divider })
            }
          }
          .width('100%')
          .padding({ bottom: AppSpacing.xl })
        }
        .width('100%')
        .height('100%')
      }
    }
    .title('系列详情')
  }
}
