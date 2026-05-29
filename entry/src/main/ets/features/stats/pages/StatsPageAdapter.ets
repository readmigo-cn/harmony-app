// L4 Feature - Stats - Adapter
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { IntentBus } from '../../../core/intent/IntentBus';
import { StatsViewModel } from '../viewmodel/StatsViewModel';
import type { StatsData } from '../viewmodel/StatsViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import { StatsOverviewCard } from '../components/StatsOverviewCard';
import { DailyReadingChart } from '../components/DailyReadingChart';
import { GenreBreakdown } from '../components/GenreBreakdown';
import { TimeOfDayChart } from '../components/TimeOfDayChart';
import {
  makeLoadOverviewIntent,
  makeLoadDailyIntent,
  makeLoadTrendIntent,
  makeLoadProgressIntent,
  makeLoadInsightsIntent,
} from '../intent/StatsIntents';

@Component
export struct StatsPageAdapter {
  @State vmState: ViewModelState<StatsData> = { status: 'idle' };
  private vm: StatsViewModel = new StatsViewModel();

  aboutToAppear(): void {
    this.vm = new StatsViewModel();
    this.bootstrap();
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  private bootstrap(): void {
    this.loadAll();
  }

  private loadAll(): void {
    const bus = IntentBus.getInstance();
    bus.publish(makeLoadOverviewIntent());
    bus.publish(makeLoadDailyIntent('7d'));
    bus.publish(makeLoadTrendIntent());
    bus.publish(makeLoadProgressIntent());
    bus.publish(makeLoadInsightsIntent());
    this.vmState = this.vm.getState();
  }

  build() {
    if (this.vmState.status === 'loading' || this.vmState.status === 'idle') {
      Column() {
        LoadingProgress().width(40).height(40).color(AppColors.brand)
        Text('加载中...').fontSize(AppFontSize.sm).fontColor(AppColors.textSecondary)
          .margin({ top: AppSpacing.sm })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.vmState.status === 'error') {
      Column({ space: AppSpacing.base }) {
        Text('加载失败').fontSize(AppFontSize.md).fontColor(AppColors.danger)
        Text(this.vmState.error.message).fontSize(AppFontSize.sm).fontColor(AppColors.textTertiary)
        Button('重试').onClick(() => this.loadAll())
          .backgroundColor(AppColors.brand).fontColor(AppColors.textInverse)
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      this.dataView(this.vmState.data)
    }
  }

  @Builder
  dataView(data: StatsData) {
    Scroll() {
      Column({ space: AppSpacing.base }) {
        if (data.overview) {
          StatsOverviewCard({ overview: data.overview })
        }
        if (data.daily && data.daily.length > 0) {
          DailyReadingChart({ points: data.daily })
        }
        if (data.progress && data.progress.length > 0) {
          GenreBreakdown({ progress: data.progress })
        }
        if (data.daily && data.daily.length > 0) {
          TimeOfDayChart({ points: data.daily })
        }
        if (data.insights && data.insights.length > 0) {
          Column({ space: AppSpacing.sm }) {
            Text('阅读洞察').fontSize(AppFontSize.sm).fontColor(AppColors.textPrimary)
              .alignSelf(ItemAlign.Start)
            ForEach(data.insights, (insight: string) => {
              Text(`• ${insight}`)
                .fontSize(AppFontSize.xs)
                .fontColor(AppColors.textSecondary)
                .alignSelf(ItemAlign.Start)
            })
          }
          .width('100%')
          .padding(AppSpacing.base)
          .backgroundColor(AppColors.bgSecondary)
        }
      }
      .padding(AppSpacing.base)
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%').height('100%')
  }
}
