// L4 Feature - Stats - Component
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import type { ProgressEntry } from '../service/StatsService';

interface GenreSlice {
  label: string;
  pct: number;
  color: string;
}

const PALETTE: string[] = [
  AppColors.brand,
  '#FF9800',
  '#4CAF50',
  '#9C27B0',
  '#F44336',
  '#2196F3',
];

@Component
export struct GenreBreakdown {
  @Prop progress: ProgressEntry[];

  private slices(): GenreSlice[] {
    if (this.progress.length === 0) {
      return [{ label: '暂无数据', pct: 1.0, color: AppColors.bgTertiary }];
    }
    const total = this.progress.reduce((s, p) => s + p.percent, 0) || 1;
    return this.progress.slice(0, 6).map((p, i) => ({
      label: p.bookId,
      pct: p.percent / total,
      color: PALETTE[i % PALETTE.length],
    }));
  }

  build() {
    Column({ space: AppSpacing.sm }) {
      Text('阅读进度分布')
        .fontSize(AppFontSize.sm)
        .fontWeight(AppFontWeight.medium)
        .fontColor(AppColors.textPrimary)
        .alignSelf(ItemAlign.Start)

      Row({ space: AppSpacing.base }) {
        Column() {
          ForEach(this.slices(), (s: GenreSlice) => {
            Row({ space: AppSpacing.xs }) {
              Column()
                .width(`${Math.max(4, Math.round(s.pct * 120))}`)
                .height(12)
                .backgroundColor(s.color)
                .borderRadius(AppRadius.xs)
              Text(`${s.label} ${Math.round(s.pct * 100)}%`)
                .fontSize(AppFontSize.xs)
                .fontColor(AppColors.textSecondary)
                .maxLines(1)
            }
            .margin({ bottom: AppSpacing.xs })
          })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          ForEach(this.slices(), (s: GenreSlice) => {
            Column()
              .width(12)
              .height(`${Math.max(4, Math.round(s.pct * 80))}`)
              .backgroundColor(s.color)
              .margin({ bottom: 2 })
          })
        }
        .alignItems(HorizontalAlign.Center)
        .width(16)
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.base)
    .backgroundColor(AppColors.bgSecondary)
    .borderRadius(AppRadius.base)
  }
}
