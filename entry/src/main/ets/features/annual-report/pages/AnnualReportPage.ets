// L4 Feature - AnnualReport - Main slideshow page
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { IntentBus } from '../../../core/intent/IntentBus';
import { AnnualReportViewModel } from '../viewmodel/AnnualReportViewModel';
import { AnnualReportCover } from '../components/AnnualReportCover';
import { AnnualReportSlide } from '../components/AnnualReportSlide';
import { AnnualReportShareCard } from '../components/AnnualReportShareCard';
import {
  makeAnnualReportLoadIntent,
  makeAnnualReportShareIntent,
} from '../intent/AnnualReportIntents';
import type { AnnualReport } from '../../../api/annual-report/AnnualReportApi';

@Entry
@Component
export struct AnnualReportPage {
  @State currentSlideIndex: number = 0;
  @State vmState: { status: string; data?: { report?: AnnualReport; currentYear?: number } } = { status: 'idle' };

  private vm: AnnualReportViewModel = new AnnualReportViewModel();
  private currentYear: number = new Date().getFullYear() - 1;

  aboutToAppear(): void {
    IntentBus.getInstance().publish(makeAnnualReportLoadIntent(this.currentYear));
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  private get report(): AnnualReport | undefined {
    if (this.vmState.status === 'data') {
      return (this.vmState as { status: string; data: { report?: AnnualReport } }).data.report;
    }
    return undefined;
  }

  private totalSlides(): number {
    const rep = this.report;
    if (!rep) return 1;
    return 1 + rep.slides.length + 1;
  }

  private onSwipe(dx: number): void {
    if (dx < -50 && this.currentSlideIndex < this.totalSlides() - 1) {
      this.currentSlideIndex += 1;
    } else if (dx > 50 && this.currentSlideIndex > 0) {
      this.currentSlideIndex -= 1;
    }
  }

  private onShareTap(): void {
    IntentBus.getInstance().publish(makeAnnualReportShareIntent(this.currentYear));
  }

  @Builder
  slideContent() {
    const rep = this.report;
    if (!rep) {
      return;
    }
    if (this.currentSlideIndex === 0) {
      AnnualReportCover({ year: rep.year })
    } else if (this.currentSlideIndex <= rep.slides.length) {
      AnnualReportSlide({ slide: rep.slides[this.currentSlideIndex - 1] })
    } else {
      AnnualReportShareCard({ report: rep, onShare: () => this.onShareTap() })
    }
  }

  @Builder
  dotsIndicator() {
    Row({ space: AppSpacing.xs }) {
      ForEach(Array.from({ length: this.totalSlides() }), (_: unknown, i: number) => {
        Column()
          .width(i === this.currentSlideIndex ? 16 : 8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(i === this.currentSlideIndex ? AppColors.brand : AppColors.divider)
      })
    }
    .justifyContent(FlexAlign.Center)
    .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm })
  }

  build() {
    NavDestination() {
      if (this.vmState.status === 'loading' || this.vmState.status === 'idle') {
        Column() {
          LoadingProgress().width(48).height(48).color(AppColors.brand)
          Text('正在加载年度报告...')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
            .margin({ top: AppSpacing.sm })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.vmState.status === 'error') {
        Column({ space: AppSpacing.base }) {
          Text('加载失败').fontSize(AppFontSize.md).fontColor(AppColors.danger)
          Button('重试')
            .onClick(() => IntentBus.getInstance().publish(makeAnnualReportLoadIntent(this.currentYear)))
            .backgroundColor(AppColors.brand)
            .fontColor(AppColors.textInverse)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          Stack()
            .layoutWeight(1)
            .width('100%')
            .gesture(
              PanGesture({ direction: PanDirection.Horizontal })
                .onActionEnd((e: GestureEvent) => this.onSwipe(e.offsetX))
            )

          this.dotsIndicator()
        }
        .width('100%')
        .height('100%')
      }
    }
    .hideTitleBar(true)
  }
}
