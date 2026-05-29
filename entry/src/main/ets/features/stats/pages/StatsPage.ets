// L4 Feature - Stats - Page entry
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { StatsPageAdapter } from './StatsPageAdapter';

@Entry
@Component
export struct StatsPage {
  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('阅读统计')
            .fontSize(AppFontSize.lg)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textPrimary)
        }
        .width('100%')
        .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.sm, bottom: AppSpacing.sm })

        StatsPageAdapter()
      }
      .width('100%').height('100%')
      .backgroundColor(AppColors.bgPrimary)
    }
    .hideTitleBar(true)
  }
}
