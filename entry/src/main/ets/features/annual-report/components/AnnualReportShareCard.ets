// L4 Feature - AnnualReport - Shareable card component
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import type { AnnualReport } from '../../../api/annual-report/AnnualReportApi';

@Component
export struct AnnualReportShareCard {
  @Prop report: AnnualReport;
  onShare?: () => void;

  build() {
    Column({ space: AppSpacing.lg }) {
      Column({ space: AppSpacing.base }) {
        Text(`${this.report.year} 年度阅读`)
          .fontSize(AppFontSize.xl)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textInverse)

        Text(`读了 ${this.report.booksRead} 本书`)
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textInverse)
          .opacity(0.85)

        Text(`阅读 ${Math.round(this.report.minutesRead / 60)} 小时`)
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textInverse)
          .opacity(0.85)

        if (this.report.topAuthor) {
          Text(`最爱作者：${this.report.topAuthor}`)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textInverse)
            .opacity(0.7)
        }
      }
      .alignItems(HorizontalAlign.Center)
      .width('100%')
      .padding(AppSpacing.xl)
      .backgroundColor(AppColors.brand)
      .borderRadius(AppRadius.xl)

      Button('分享报告')
        .width('100%')
        .height(48)
        .backgroundColor(AppColors.brand)
        .fontColor(AppColors.textInverse)
        .fontSize(AppFontSize.md)
        .borderRadius(AppRadius.base)
        .onClick(() => {
          if (this.onShare) {
            this.onShare();
          }
        })
    }
    .width('100%')
    .padding(AppSpacing.base)
  }
}
