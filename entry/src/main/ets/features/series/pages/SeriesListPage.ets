// L4 Feature - Series - Page
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { SeriesViewModel } from '../viewmodel/SeriesViewModel';
import type { SeriesData } from '../viewmodel/SeriesViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeLoadSeriesListIntent, makeOpenSeriesDetailIntent } from '../intent/SeriesIntents';
import { SeriesCard } from '../components/SeriesCard';
import type { Series } from '../service/SeriesService';

@Entry
@Component
export struct SeriesListPage {
  @State private state: ViewModelState<SeriesData> = { status: 'idle' };
  private vm: SeriesViewModel = new SeriesViewModel();

  aboutToAppear(): void {
    IntentBus.getInstance().publish(makeLoadSeriesListIntent() as never);
    this.syncState();
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  private syncState(): void {
    this.state = this.vm.getState() as ViewModelState<SeriesData>;
  }

  private openDetail(seriesId: string): void {
    AppStorage.SetOrCreate('series_selected_id', seriesId);
    IntentBus.getInstance().publish(makeOpenSeriesDetailIntent(seriesId) as never);
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
            .onClick(() => IntentBus.getInstance().publish(makeLoadSeriesListIntent() as never))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          if (!this.state.data.list || this.state.data.list.length === 0) {
            Text('暂无系列').fontSize(AppFontSize.md).fontColor(AppColors.textTertiary)
              .width('100%')
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
          } else {
            List({ space: AppSpacing.sm }) {
              ForEach(this.state.data.list, (series: Series) => {
                ListItem() {
                  SeriesCard({
                    series,
                    onTap: () => this.openDetail(series.id),
                  })
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
    .title('系列书单')
  }
}
