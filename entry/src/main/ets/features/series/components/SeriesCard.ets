// L4 Feature - Series - Component
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import type { Series } from '../service/SeriesService';

@Component
export struct SeriesCard {
  @Prop series: Series;
  onTap?: () => void;

  build() {
    Column({ space: AppSpacing.xs }) {
      Row() {
        Column({ space: AppSpacing.xs }) {
          Text(this.series.title)
            .fontSize(AppFontSize.md)
            .fontWeight(AppFontWeight.medium)
            .fontColor(AppColors.textPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.series.bookCount} 册`)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textTertiary)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.series.books && this.series.books.length > 0) {
        Text(this.series.books.slice(0, 3).map((b) => b.title).join(' / '))
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .padding(AppSpacing.base)
    .backgroundColor(AppColors.bgPrimary)
    .borderRadius(AppRadius.base)
    .onClick(() => {
      if (this.onTap) this.onTap();
    })
  }
}
