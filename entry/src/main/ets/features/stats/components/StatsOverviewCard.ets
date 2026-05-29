// L4 Feature - Stats - Component
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import type { OverviewData } from '../service/StatsService';

@Component
export struct StatsOverviewCard {
  @Prop overview: OverviewData;

  build() {
    Row({ space: AppSpacing.base }) {
      this.statCell('书', `${this.overview.booksRead}`)
      this.statCell('分钟', `${this.overview.minutesRead}`)
      this.statCell('连续天', `${this.overview.currentStreak}`)
    }
    .width('100%')
    .padding(AppSpacing.base)
    .backgroundColor(AppColors.bgSecondary)
    .borderRadius(AppRadius.base)
    .justifyContent(FlexAlign.SpaceEvenly)
  }

  @Builder
  statCell(label: string, value: string) {
    Column({ space: AppSpacing.xs }) {
      Text(value)
        .fontSize(AppFontSize.xl)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.brand)
      Text(label)
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textSecondary)
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }
}
