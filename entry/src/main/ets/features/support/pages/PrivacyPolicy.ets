/**
 * PrivacyPolicy.ets — W19-C5 隐私政策页
 *
 * 通过 @ohos.resourceManager 读取 rawfile/legal/privacy-policy-zh.md。
 * onboarding 流程入口可显示「我已阅读并同意」按钮。
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
import { Spacing, Radius } from '../../../core/theme/AppSpacing';

interface PrivacyPolicyParams {
  inOnboarding?: boolean;
}

@Entry
@Component
struct PrivacyPolicy {
  @State private content: string = '';
  @State private loading: boolean = true;
  @State private inOnboarding: boolean = false;
  @State private isDark: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as PrivacyPolicyParams | undefined;
    if (params && params.inOnboarding) this.inOnboarding = true;
    this.loadContent();
  }

  private async loadContent(): Promise<void> {
    this.loading = true;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const data: Uint8Array = await ctx.resourceManager.getRawFileContent('legal/privacy-policy-zh.md');
      const dec = util.TextDecoder.create('utf-8');
      this.content = dec.decodeWithStream(data);
    } catch (_e) {
      this.content = '加载失败，请稍后重试。\n\n如需查看完整版隐私政策，请访问 https://readmigo.cn/legal/privacy-policy';
    } finally {
      this.loading = false;
    }
  }

  private onAgree(): void {
    router.back();
  }

  build() {
    Column() {
      Row() {
        Text('< 返回')
          .fontSize(FontSizeToken.callout)
          .fontColor(useColor(AccentColors.primary, this.isDark))
          .onClick(() => router.back())
        Blank()
        Text('隐私政策')
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

      if (this.inOnboarding) {
        Button('我已阅读并同意')
          .width('92%').height(48)
          .fontColor(useColor(TextColors.inverse, this.isDark))
          .backgroundColor(useColor(AccentColors.primary, this.isDark))
          .borderRadius(Radius.lg)
          .margin({ top: Spacing.s3, bottom: Spacing.s4 })
          .onClick(() => this.onAgree())
      }
    }
    .width('100%').height('100%')
    .backgroundColor(useColor(BgColors.primary, this.isDark))
  }
}
