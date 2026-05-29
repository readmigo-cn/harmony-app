// L4 Feature - Audiobook - Grid of audiobook cards
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeOpenDetailIntent } from '../intent/AudiobookIntents';
import type { AudiobookItem } from '../../../api/audiobooks/AudiobookApi';

@Component
export struct AudiobookCard {
  @Prop audiobook: AudiobookItem = {
    id: '',
    title: '',
    narrator: '',
    durationMs: 0,
    coverUrl: '',
    provider: 'librivox',
    languages: [],
    free: true,
  };

  private formatDuration(ms: number): string {
    const h = Math.floor(ms / 3600000);
    const m = Math.floor((ms % 3600000) / 60000);
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
  }

  build() {
    Column({ space: AppSpacing.xs }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.audiobook.coverUrl) {
          Image(this.audiobook.coverUrl)
            .width('100%')
            .aspectRatio(1)
            .borderRadius(8)
            .objectFit(ImageFit.Cover)
        } else {
          Column()
            .width('100%')
            .aspectRatio(1)
            .borderRadius(8)
            .backgroundColor(AppColors.bgSecondary)
        }

        if (!this.audiobook.free) {
          Text('PRO')
            .fontSize(9)
            .fontColor(Color.White)
            .fontWeight(AppFontWeight.bold)
            .padding({ left: 4, right: 4, top: 2, bottom: 2 })
            .backgroundColor('#A78BFA')
            .borderRadius(4)
            .margin(4)
        }
      }
      .width('100%')

      Text(this.audiobook.title)
        .fontSize(AppFontSize.sm)
        .fontWeight(AppFontWeight.medium)
        .fontColor(AppColors.textPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.audiobook.narrator)
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.formatDuration(this.audiobook.durationMs))
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textTertiary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      IntentBus.getInstance()
        .publish(makeOpenDetailIntent(this.audiobook.id))
        .catch((_e: Error) => {});
    })
  }
}

@Component
export struct AudiobookGrid {
  @Prop items: AudiobookItem[] = [];
  @Prop title: string = '';

  build() {
    Column({ space: AppSpacing.sm }) {
      if (this.title) {
        Text(this.title)
          .fontSize(AppFontSize.lg)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
          .width('100%')
      }

      if (this.items.length === 0) {
        Text($r('app.string.common_empty'))
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textTertiary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: AppSpacing.lg, bottom: AppSpacing.lg })
      } else {
        Grid() {
          ForEach(this.items, (item: AudiobookItem) => {
            GridItem() {
              AudiobookCard({ audiobook: item })
            }
          })
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(AppSpacing.sm)
        .rowsGap(AppSpacing.base)
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
