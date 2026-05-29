// L4 Feature - Audiobook - ContinueListening card
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeContinueListeningIntent } from '../intent/AudiobookIntents';
import type { AudiobookItem } from '../../../api/audiobooks/AudiobookApi';

@Component
export struct ContinueListeningCard {
  @Prop audiobook: AudiobookItem | undefined = undefined;
  @Prop progressPercent: number = 0;

  build() {
    if (this.audiobook) {
      Row({ space: AppSpacing.base }) {
        if (this.audiobook.coverUrl) {
          Image(this.audiobook.coverUrl)
            .width(56)
            .height(56)
            .borderRadius(8)
            .objectFit(ImageFit.Cover)
        } else {
          Column()
            .width(56)
            .height(56)
            .borderRadius(8)
            .backgroundColor(AppColors.bgSecondary)
        }

        Column({ space: AppSpacing.xs }) {
          Text(this.audiobook.title)
            .fontSize(AppFontSize.base)
            .fontWeight(AppFontWeight.medium)
            .fontColor(AppColors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(this.audiobook.narrator)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Progress({ value: this.progressPercent, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(4)
            .color(AppColors.accent)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button() {
          Image($r('app.media.ic_play_circle'))
            .width(32)
            .height(32)
        }
        .backgroundColor(Color.Transparent)
        .width(40)
        .height(40)
        .onClick(() => {
          IntentBus.getInstance().publish(makeContinueListeningIntent()).catch((_e: Error) => {});
        })
      }
      .width('100%')
      .padding(AppSpacing.base)
      .backgroundColor(AppColors.bgSecondary)
      .borderRadius(12)
    }
  }
}
