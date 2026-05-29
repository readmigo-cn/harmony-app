// L4 Feature - Audiobook - Paywall banner shown when canPlay returns false
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { IntentBus } from '../../../core/intent/IntentBus';
import { RouterService } from '../../../core/router/RouterService';
import { RoutePath } from '../../../core/router/RouteConstants';

@Component
export struct PaywallBanner {
  @Prop visible: boolean = false;
  onDismiss: () => void = () => {};

  build() {
    if (this.visible) {
      Column({ space: AppSpacing.sm }) {
        Row() {
          Text($r('app.string.paywall_tts_title'))
            .fontSize(AppFontSize.base)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textPrimary)
            .layoutWeight(1)

          Button() {
            Text('×')
              .fontSize(AppFontSize.lg)
              .fontColor(AppColors.textSecondary)
          }
          .backgroundColor(Color.Transparent)
          .width(32)
          .height(32)
          .onClick(() => this.onDismiss())
        }
        .width('100%')

        Text($r('app.string.paywall_tts_body'))
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textSecondary)
          .width('100%')

        Button($r('app.string.paywall_upgrade_cta'))
          .width('100%')
          .fontColor(Color.White)
          .backgroundColor('#A78BFA')
          .borderRadius(8)
          .onClick(() => {
            this.onDismiss();
            RouterService.push(RoutePath.SUBSCRIPTIONS);
          })
      }
      .width('100%')
      .padding(AppSpacing.base)
      .backgroundColor(AppColors.bgSecondary)
      .borderRadius(12)
      .shadow({ radius: 8, color: 'rgba(0,0,0,0.10)', offsetX: 0, offsetY: 2 })
    }
  }
}
