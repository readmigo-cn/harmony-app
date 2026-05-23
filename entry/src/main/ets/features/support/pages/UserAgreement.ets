/**
 * UserAgreement.ets — W19-C5 用户协议页
 *
 * 通过 @ohos.resourceManager 读取 rawfile/legal/user-agreement-zh.md。
 * 简化展示：原文 markdown 直接以 Text 渲染（不解析 markdown）。
 *
 * 入口参数（router.pushUrl 时传入）：
 *   - inOnboarding: boolean   onboarding 流程时显示底部「我已阅读并同意」按钮
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

interface UserAgreementParams {
  inOnboarding?: boolean;
}

@Entry
@Component
struct UserAgreement {
  @State private content: string = '';
  @State private loading: boolean = true;
  @State private inOnboarding: boolean = false;
  @State private isDark: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as UserAgreementParams | undefined;
    if (params && params.inOnboarding) this.inOnboarding = true;
    this.loadContent();
  }

  private async loadContent(): Promise<void> {
    this.loading = true;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const data: Uint8Array = await ctx.resourceManager.getRawFileContent('legal/user-agreement-zh.md');
      // UTF-8 解码（中文需 TextDecoder，不能用 String.fromCharCode）
      const dec = util.TextDecoder.create('utf-8');
      this.content = dec.decodeWithStream(data);
    } catch (_e) {
      this.content = '加载失败，请稍后重试。\n\n如需查看完整版用户协议，请访问 https://readmigo.cn/legal/user-agreement';
    } finally {
      this.loading = false;
    }
  }

  private onAgree(): void {
    // 写入 onboarding flag（store 端在 W19 主 agent 集成时接入）
    router.back();
  }

  @Builder
  topBar() {
    Row() {
      Text('< 返回')
        .fontSize(FontSizeToken.callout)
        .fontColor(useColor(AccentColors.primary, this.isDark))
        .onClick(() => router.back())
      Blank()
      Text('用户协议')
        .fontSize(FontSizeToken.headline)
        .fontWeight(FontWeightToken.bold)
        .fontColor(useColor(TextColors.primary, this.isDark))
      Blank()
      Text('').width(56)
    }
    .width('100%')
    .height(48)
    .padding({ left: Spacing.s4, right: Spacing.s4 })
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
  }

  build() {
    Column() {
      this.topBar()
      Scroll() {
        Column() {
          if (this.loading) {
            LoadingProgress()
              .width(32).height(32)
              .margin({ top: Spacing.s12 })
          } else {
            Text(this.content)
              .fontSize(FontSizeToken.subheadline)
              .lineHeight(LineHeightToken.body)
              .fontColor(useColor(TextColors.primary, this.isDark))
              .padding(Spacing.s4)
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)

      if (this.inOnboarding) {
        Button('我已阅读并同意')
          .width('92%')
          .height(48)
          .fontColor(useColor(TextColors.inverse, this.isDark))
          .backgroundColor(useColor(AccentColors.primary, this.isDark))
          .borderRadius(Radius.lg)
          .margin({ top: Spacing.s3, bottom: Spacing.s4 })
          .onClick(() => this.onAgree())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(useColor(BgColors.primary, this.isDark))
  }
}
