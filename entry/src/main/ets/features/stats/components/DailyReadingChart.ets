// L4 Feature - Stats - Component
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import type { DailyPoint } from '../service/StatsService';

@Component
export struct DailyReadingChart {
  @Prop points: DailyPoint[];

  private maxMinutes(): number {
    if (this.points.length === 0) return 1;
    return Math.max(...this.points.map((p) => p.minutes), 1);
  }

  private barHeightPct(minutes: number): number {
    return Math.max(0.04, minutes / this.maxMinutes());
  }

  private shortDate(iso: string): string {
    const parts = iso.split('-');
    return parts.length >= 3 ? `${parts[1]}/${parts[2]}` : iso;
  }

  build() {
    Column({ space: AppSpacing.sm }) {
      Text('每日阅读时长（分钟）')
        .fontSize(AppFontSize.sm)
        .fontWeight(AppFontWeight.medium)
        .fontColor(AppColors.textPrimary)
        .alignSelf(ItemAlign.Start)

      Row({ space: 4 }) {
        ForEach(this.points, (p: DailyPoint) => {
          Column({ space: 2 }) {
            Column()
              .width(20)
              .height(`${Math.round(this.barHeightPct(p.minutes) * 80)}`)
              .backgroundColor(p.minutes > 0 ? AppColors.brand : AppColors.bgTertiary)
              .borderRadius({ topLeft: AppRadius.xs, topRight: AppRadius.xs })

            Text(this.shortDate(p.date))
              .fontSize(8)
              .fontColor(AppColors.textTertiary)
              .maxLines(1)
          }
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
          .height(100)
          .layoutWeight(1)
        })
      }
      .width('100%')
      .height(100)
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding(AppSpacing.base)
    .backgroundColor(AppColors.bgSecondary)
    .borderRadius(AppRadius.base)
  }
}
