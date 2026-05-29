// L4 Feature - Stats - Book detail page
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import { IntentBus } from '../../../core/intent/IntentBus';
import { StatsViewModel } from '../viewmodel/StatsViewModel';
import type { StatsData } from '../viewmodel/StatsViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import { makeOpenBookDetailIntent } from '../intent/StatsIntents';

@Entry
@Component
export struct BookStatsDetailPage {
  @State vmState: ViewModelState<StatsData> = { status: 'idle' };
  @State bookId: string = '';
  private vm: StatsViewModel = new StatsViewModel();

  aboutToAppear(): void {
    this.vm = new StatsViewModel();
    const params = AppStorage.Get<Record<string, string>>('book_stats_params');
    this.bookId = params?.bookId ?? '';
    if (this.bookId) {
      IntentBus.getInstance().publish(makeOpenBookDetailIntent(this.bookId));
      this.vmState = this.vm.getState();
    }
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: AppSpacing.sm }) {
          Text('< 返回')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.brand)
            .padding(AppSpacing.xs)
            .onClick(() => RouterService.pop())

          Text('本书统计')
            .fontSize(AppFontSize.lg)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textPrimary)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.sm, bottom: AppSpacing.sm })

        if (this.vmState.status === 'loading' || this.vmState.status === 'idle') {
          Column() {
            LoadingProgress().width(40).height(40).color(AppColors.brand)
          }
          .width('100%').layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.vmState.status === 'error') {
          Column({ space: AppSpacing.base }) {
            Text('加载失败').fontSize(AppFontSize.md).fontColor(AppColors.danger)
            Text(this.vmState.error.message).fontSize(AppFontSize.sm).fontColor(AppColors.textTertiary)
          }
          .width('100%').layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.vmState.data.selectedBookStats) {
          const stats = this.vmState.data.selectedBookStats;
          Column({ space: AppSpacing.base }) {
            this.statRow('书籍 ID', stats.bookId)
            this.statRow('阅读场次', `${stats.sessions}`)
            this.statRow('已读章节', `${stats.chapters}`)
            this.statRow('总时长', `${Math.round(stats.durationMs / 60000)} 分钟`)
          }
          .width('100%')
          .padding(AppSpacing.base)
        }
      }
      .width('100%').height('100%')
      .backgroundColor(AppColors.bgPrimary)
    }
    .hideTitleBar(true)
  }

  @Builder
  statRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textSecondary)
        .layoutWeight(1)
      Text(value)
        .fontSize(AppFontSize.sm)
        .fontWeight(AppFontWeight.medium)
        .fontColor(AppColors.textPrimary)
    }
    .width('100%')
    .padding(AppSpacing.sm)
    .backgroundColor(AppColors.bgSecondary)
    .borderRadius(AppRadius.sm)
  }
}
