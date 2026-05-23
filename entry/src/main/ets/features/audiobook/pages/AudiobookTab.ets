import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import { RoutePath } from '../../../core/router/RouteConstants';

@Component
export struct AudiobookTab {
  build() {
    Column({ space: AppSpacing.lg }) {
      Text($r('app.string.audiobook_title'))
        .fontSize(AppFontSize.xl)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .padding(AppSpacing.base)
        .width('100%')
        .textAlign(TextAlign.Start)

      Text($r('app.string.common_empty'))
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textTertiary)

      Button($r('app.string.audiobook_play'))
        .onClick(() => {
          const params: Record<string, string | number> = { audiobookId: 'demo', chapterIndex: 0 };
          RouterService.push(RoutePath.AUDIOBOOK_PLAYER, params);
        })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(AppColors.bgPrimary)
  }
}
