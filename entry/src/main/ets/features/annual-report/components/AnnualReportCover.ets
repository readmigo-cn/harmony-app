// L4 Feature - AnnualReport - Cover slide component
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';

@Component
export struct AnnualReportCover {
  @Prop year: number;

  build() {
    Column({ space: AppSpacing.lg }) {
      Text(String(this.year))
        .fontSize(72)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textInverse)
        .opacity(0.9)

      Text('年度阅读报告')
        .fontSize(AppFontSize.xxl)
        .fontWeight(AppFontWeight.medium)
        .fontColor(AppColors.textInverse)

      Text('回顾你的阅读之旅')
        .fontSize(AppFontSize.md)
        .fontColor(AppColors.textInverse)
        .opacity(0.7)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppColors.brand)
  }
}
