// L4 Feature - Stats - Component
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import type { DailyPoint } from '../service/StatsService';

interface TimeSlot {
  label: string;
  minutes: number;
  color: string;
}

function buildSlots(points: DailyPoint[]): TimeSlot[] {
  const morning = points.filter((_, i) => i % 3 === 0).reduce((s, p) => s + p.minutes, 0);
  const afternoon = points.filter((_, i) => i % 3 === 1).reduce((s, p) => s + p.minutes, 0);
  const evening = points.filter((_, i) => i % 3 === 2).reduce((s, p) => s + p.minutes, 0);
  return [
    { label: '早晨', minutes: morning, color: '#FF9800' },
    { label: '下午', minutes: afternoon, color: AppColors.brand },
    { label: '傍晚', minutes: evening, color: '#9C27B0' },
  ];
}

@Component
export struct TimeOfDayChart {
  @Prop points: DailyPoint[];

  private maxVal(): number {
    const slots = buildSlots(this.points);
    return Math.max(...slots.map((s) => s.minutes), 1);
  }

  build() {
    Column({ space: AppSpacing.sm }) {
      Text('一天中的阅读时段')
        .fontSize(AppFontSize.sm)
        .fontWeight(AppFontWeight.medium)
        .fontColor(AppColors.textPrimary)
        .alignSelf(ItemAlign.Start)

      Row({ space: AppSpacing.base }) {
        ForEach(buildSlots(this.points), (s: TimeSlot) => {
          Column({ space: AppSpacing.xs }) {
            Column()
              .width(32)
              .height(`${Math.max(4, Math.round((s.minutes / this.maxVal()) * 64))}`)
              .backgroundColor(s.color)
              .borderRadius({ topLeft: AppRadius.xs, topRight: AppRadius.xs })

            Text(`${s.minutes}m`)
              .fontSize(AppFontSize.xs)
              .fontColor(AppColors.textSecondary)

            Text(s.label)
              .fontSize(AppFontSize.xs)
              .fontColor(AppColors.textTertiary)
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.End)
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
