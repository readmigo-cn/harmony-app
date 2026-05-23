import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { AudiobookPlayerParams } from '../../../core/router/RouteConstants';
import { RouterService } from '../../../core/router/RouterService';

@Component
export struct AudiobookPlayer {
  @Prop params: AudiobookPlayerParams;
  @State playing: boolean = false;

  build() {
    NavDestination() {
      Column({ space: AppSpacing.xl }) {
        Row() {
          Text('< ')
            .fontSize(AppFontSize.md)
            .fontColor(AppColors.brand)
            .onClick(() => RouterService.pop())
          Text($r('app.string.audiobook_title'))
            .fontSize(AppFontSize.md)
            .fontColor(AppColors.textInverse)
        }
        .width('100%')
        .padding(AppSpacing.base)

        Text(`audiobookId: ${this.params?.audiobookId ?? ''}`)
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textInverse)

        Button(this.playing ? $r('app.string.audiobook_pause') : $r('app.string.audiobook_play'))
          .width(160)
          .height(48)
          .backgroundColor(AppColors.brand)
          .onClick(() => { this.playing = !this.playing; })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#0F0F1A')
    }
    .hideTitleBar(true)
  }
}
