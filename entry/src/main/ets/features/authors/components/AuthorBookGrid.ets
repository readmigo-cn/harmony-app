// L4 Feature - Authors - Component
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import type { AuthorReadingProgress } from '../service/AuthorsService';

interface BookEntry {
  bookId: string;
  percent: number;
}

@Component
export struct AuthorBookGrid {
  @Prop authorId: string;
  @Prop readingProgress: AuthorReadingProgress[];

  build() {
    Column({ space: AppSpacing.sm }) {
      Text('已读进度')
        .fontSize(AppFontSize.md)
        .fontColor(AppColors.textPrimary)
        .width('100%')

      if (!this.readingProgress || this.readingProgress.length === 0) {
        Text('暂无阅读记录')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textTertiary)
          .padding(AppSpacing.lg)
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        Grid() {
          ForEach(this.readingProgress, (entry: AuthorReadingProgress) => {
            GridItem() {
              Column({ space: AppSpacing.xs }) {
                Stack() {
                  Column()
                    .width('100%')
                    .height(4)
                    .backgroundColor(AppColors.bgSecondary)
                    .borderRadius(2)
                  Column()
                    .width(`${entry.percent}%`)
                    .height(4)
                    .backgroundColor(AppColors.brand)
                    .borderRadius(2)
                }
                .width('100%')
                .alignContent(Alignment.Start)

                Text(`${Math.round(entry.percent)}%`)
                  .fontSize(AppFontSize.xs)
                  .fontColor(AppColors.textSecondary)
              }
              .padding(AppSpacing.sm)
              .backgroundColor(AppColors.bgSecondary)
              .borderRadius(AppRadius.base)
            }
          })
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(AppSpacing.sm)
        .rowsGap(AppSpacing.sm)
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.base, right: AppSpacing.base })
  }
}
