// L4 Feature - Audiobook - Banner shown for narrations with per-sentence highlights
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';

@Component
export struct SubtitleGuideBanner {
  @Prop visible: boolean = false;
  onDismiss: () => void = () => {};

  build() {
    if (this.visible) {
      Row({ space: AppSpacing.sm }) {
        Text('💡')
          .fontSize(AppFontSize.base)

        Text($r('app.string.subtitle_guide_tip'))
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textSecondary)
          .layoutWeight(1)

        Button('×')
          .fontSize(AppFontSize.base)
          .fontColor(AppColors.textTertiary)
          .backgroundColor(Color.Transparent)
          .width(28)
          .height(28)
          .onClick(() => this.onDismiss())
      }
      .width('100%')
      .padding({ left: AppSpacing.base, right: AppSpacing.sm, top: AppSpacing.sm, bottom: AppSpacing.sm })
      .backgroundColor('#EDE9FE')
      .borderRadius(8)
    }
  }
}
