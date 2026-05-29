// L4 Feature - AnnualReport - Single stat slide component
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import type { AnnualReportSlideData } from '../../../api/annual-report/AnnualReportApi';

@Component
export struct AnnualReportSlide {
  @Prop slide: AnnualReportSlideData;

  build() {
    Column({ space: AppSpacing.xl }) {
      if (this.slide.illustration) {
        Image(this.slide.illustration)
          .width(120)
          .height(120)
          .borderRadius(AppRadius.lg)
          .objectFit(ImageFit.Cover)
      } else {
        Column()
          .width(120)
          .height(120)
          .borderRadius(AppRadius.lg)
          .backgroundColor(AppColors.brand)
          .opacity(0.15)
      }

      Column({ space: AppSpacing.sm }) {
        Text(this.slide.value)
          .fontSize(56)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.brand)

        Text(this.slide.title)
          .fontSize(AppFontSize.lg)
          .fontWeight(AppFontWeight.medium)
          .fontColor(AppColors.textPrimary)
          .textAlign(TextAlign.Center)
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(AppSpacing.xl)
    .backgroundColor(AppColors.bgPrimary)
  }
}
