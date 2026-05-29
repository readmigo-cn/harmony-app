// L4 Feature - Quotes - QuotesPage
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeLoadDailyIntent, makeLoadTrendingIntent } from '../intent/QuotesIntents';
import { QuotesViewModel } from '../viewmodel/QuotesViewModel';
import type { QuotesState } from '../viewmodel/QuotesViewModel';
import { QuoteCard } from '../components/QuoteCard';

@Component
export struct QuotesPage {
  @State private activeTab: number = 0;
  @State private vmState: QuotesState = { status: 'idle' };

  private vm: QuotesViewModel = new QuotesViewModel();

  aboutToAppear(): void {
    this.loadCurrentTab();
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  private loadCurrentTab(): void {
    if (this.activeTab === 0) {
      IntentBus.getInstance().publish(makeLoadDailyIntent());
    } else {
      IntentBus.getInstance().publish(makeLoadTrendingIntent());
    }
  }

  @Builder
  tabBar(label: string, index: number) {
    Text(label)
      .fontSize(AppFontSize.sm)
      .fontWeight(this.activeTab === index ? AppFontWeight.bold : AppFontWeight.normal)
      .fontColor(this.activeTab === index ? AppColors.brand : AppColors.textSecondary)
      .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.sm, bottom: AppSpacing.sm })
      .border({
        width: { bottom: this.activeTab === index ? 2 : 0 },
        color: AppColors.brand,
      })
  }

  @Builder
  dailyContent() {
    if (this.vmState.status === 'loading') {
      Column() {
        LoadingProgress().width(40).height(40).color(AppColors.brand)
      }.width('100%').height(200).justifyContent(FlexAlign.Center)
    } else if (this.vmState.status === 'data' && this.vmState.data.daily) {
      Column({ space: AppSpacing.base }) {
        Text('今日金句').fontSize(AppFontSize.xs).fontColor(AppColors.textTertiary)
          .alignSelf(ItemAlign.Start)
        QuoteCard({ quote: this.vmState.data.daily })
      }
      .padding(AppSpacing.base)
      .width('100%')
    } else if (this.vmState.status === 'error') {
      Column({ space: AppSpacing.sm }) {
        Text('加载失败').fontSize(AppFontSize.sm).fontColor(AppColors.danger)
        Button('重试').onClick(() => IntentBus.getInstance().publish(makeLoadDailyIntent()))
      }.width('100%').height(200).justifyContent(FlexAlign.Center)
    } else {
      Column() {
        Text('暂无内容').fontSize(AppFontSize.sm).fontColor(AppColors.textTertiary)
      }.width('100%').height(200).justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  trendingContent() {
    if (this.vmState.status === 'loading') {
      Column() {
        LoadingProgress().width(40).height(40).color(AppColors.brand)
      }.width('100%').height(200).justifyContent(FlexAlign.Center)
    } else if (this.vmState.status === 'data' && this.vmState.data.trending && this.vmState.data.trending.length > 0) {
      List({ space: AppSpacing.sm }) {
        ForEach(this.vmState.data.trending, (q: { id: string; text: string; author: string; bookId?: string; bookTitle?: string; liked: boolean }) => {
          ListItem() {
            QuoteCard({ quote: q })
          }
          .padding({ left: AppSpacing.base, right: AppSpacing.base })
        })
      }
      .width('100%')
      .layoutWeight(1)
    } else if (this.vmState.status === 'error') {
      Column({ space: AppSpacing.sm }) {
        Text('加载失败').fontSize(AppFontSize.sm).fontColor(AppColors.danger)
        Button('重试').onClick(() => IntentBus.getInstance().publish(makeLoadTrendingIntent()))
      }.width('100%').height(200).justifyContent(FlexAlign.Center)
    } else {
      Column() {
        Text('暂无内容').fontSize(AppFontSize.sm).fontColor(AppColors.textTertiary)
      }.width('100%').height(200).justifyContent(FlexAlign.Center)
    }
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          this.tabBar('今日金句', 0)
          this.tabBar('热门金句', 1)
        }
        .width('100%')
        .borderWidth({ bottom: 1 })
        .borderColor(AppColors.divider)

        if (this.activeTab === 0) {
          this.dailyContent()
        } else {
          this.trendingContent()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgSecondary)
    }
    .title('金句')
    .onAppear(() => {
      this.loadCurrentTab();
    })
  }
}
