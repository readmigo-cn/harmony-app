/**
 * OssLicenses.ets — W19-C5 第三方开源声明页
 *
 * 通过 @ohos.resourceManager 读取 rawfile/legal/oss-licenses.md。
 * 各 SDK / 库及其 license 占位列表，后续随依赖变化更新。
 */

import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import util from '@ohos.util';
import {
  useColor,
  TextColors,
  BgColors,
  AccentColors,
} from '../../../core/theme/AppColors';
import {
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing } from '../../../core/theme/AppSpacing';

@Entry
@Component
struct OssLicenses {
  @State private content: string = '';
  @State private loading: boolean = true;
  @State private isDark: boolean = false;

  aboutToAppear(): void {
    this.loadContent();
  }

  private async loadContent(): Promise<void> {
    this.loading = true;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const data: Uint8Array = await ctx.resourceManager.getRawFileContent('legal/oss-licenses.md');
      const dec = util.TextDecoder.create('utf-8');
      this.content = dec.decodeWithStream(data);
    } catch (_e) {
      this.content = '加载失败。\n\n完整开源声明：https://readmigo.cn/legal/oss-licenses';
    } finally {
      this.loading = false;
    }
  }

  build() {
    Column() {
      Row() {
        Text('< 返回')
          .fontSize(FontSizeToken.callout)
          .fontColor(useColor(AccentColors.primary, this.isDark))
          .onClick(() => router.back())
        Blank()
        Text('第三方开源声明')
          .fontSize(FontSizeToken.headline)
          .fontWeight(FontWeightToken.bold)
          .fontColor(useColor(TextColors.primary, this.isDark))
        Blank()
        Text('').width(56)
      }
      .width('100%').height(48)
      .padding({ left: Spacing.s4, right: Spacing.s4 })
      .backgroundColor(useColor(BgColors.elevated, this.isDark))

      Scroll() {
        if (this.loading) {
          LoadingProgress().width(32).height(32).margin({ top: Spacing.s12 })
        } else {
          Text(this.content)
            .fontSize(FontSizeToken.subheadline)
            .lineHeight(LineHeightToken.body)
            .fontColor(useColor(TextColors.primary, this.isDark))
            .padding(Spacing.s4)
            .width('100%')
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%').height('100%')
    .backgroundColor(useColor(BgColors.primary, this.isDark))
  }
}
