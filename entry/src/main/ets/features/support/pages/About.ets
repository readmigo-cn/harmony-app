/**
 * About.ets — W19-C4 关于页
 *
 * 内容：
 *   - App logo + 名称 + 版本号 + Build 号
 *   - Slogan
 *   - 公司信息
 *   - 跳转：官网 / 用户协议 / 隐私政策 / 第三方开源声明 / 检查更新
 *   - ICP 备案号
 *
 * 版本号读取：bundleManager.getBundleInfoForSelf() 异步取，失败 fallback 到常量。
 */

import router from '@ohos.router';
import bundleManager from '@ohos.bundle.bundleManager';
import common from '@ohos.app.ability.common';
import promptAction from '@ohos.promptAction';
import {
  useColor,
  TextColors,
  BgColors,
  AccentColors,
  SurfaceColors,
  BrandPalette,
} from '../../../core/theme/AppColors';
import {
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius } from '../../../core/theme/AppSpacing';

interface AboutLink {
  id: string;
  label: string;
  /** route URL 或 'placeholder' 表示尚未实现 */
  url: string;
  external?: boolean;
}

const ABOUT_LINKS: AboutLink[] = [
  { id: 'website',  label: '官网', url: 'https://readmigo.cn', external: true },
  { id: 'agreement', label: '用户协议', url: 'features/support/pages/UserAgreement' },
  { id: 'privacy',   label: '隐私政策', url: 'features/support/pages/PrivacyPolicy' },
  { id: 'oss',       label: '第三方开源声明', url: 'features/support/pages/OssLicenses' },
  { id: 'contact',   label: '联系我们', url: 'features/account/pages/Contact' },
  { id: 'update',    label: '检查更新', url: 'placeholder' },
];

const COMPANY_NAME: string = '北京瑞光科技有限公司';
const SLOGAN: string = 'AI 时代的英语阅读伴侣';
const ICP_NUMBER: string = '冀ICP备2026009459号';

@Entry
@Component
struct About {
  @State private versionName: string = '0.1.0';
  @State private versionCode: number = 1;
  @State private isDark: boolean = false;

  aboutToAppear(): void {
    this.loadBundleInfo();
  }

  private async loadBundleInfo(): Promise<void> {
    try {
      const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT;
      const info = await bundleManager.getBundleInfoForSelf(flags);
      if (info.versionName) this.versionName = info.versionName;
      if (info.versionCode) this.versionCode = info.versionCode;
    } catch (_e) {
      // fallback 已在 @State 默认值中处理
    }
  }

  private onLinkTap(link: AboutLink): void {
    if (link.url === 'placeholder') {
      promptAction.showToast({ message: '已是最新版本' });
      return;
    }
    if (link.external) {
      // 外部 URL：占位提示，后续接入 want.startAbility 打开浏览器
      promptAction.showToast({ message: link.url });
      return;
    }
    router.pushUrl({ url: link.url }).catch((_e: Error) => {});
  }

  @Builder
  topBar() {
    Row() {
      Text('< 返回')
        .fontSize(FontSizeToken.callout)
        .fontColor(useColor(AccentColors.primary, this.isDark))
        .onClick(() => router.back())
      Blank()
      Text('关于')
        .fontSize(FontSizeToken.headline)
        .fontWeight(FontWeightToken.bold)
        .fontColor(useColor(TextColors.primary, this.isDark))
      Blank()
      Text('')
        .width(56)
    }
    .width('100%')
    .height(48)
    .padding({ left: Spacing.s4, right: Spacing.s4 })
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
  }

  @Builder
  header() {
    Column({ space: Spacing.s2 }) {
      Image($r('app.media.app_icon'))
        .width(96).height(96)
        .borderRadius(Radius.xl)
      Text($r('app.string.app_name'))
        .fontSize(FontSizeToken.title2)
        .fontWeight(FontWeightToken.bold)
        .fontColor(useColor(TextColors.primary, this.isDark))
      Text(SLOGAN)
        .fontSize(FontSizeToken.subheadline)
        .fontColor(useColor(TextColors.secondary, this.isDark))
      Text(`Version ${this.versionName} (Build ${this.versionCode})`)
        .fontSize(FontSizeToken.footnote)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
    }
    .width('100%')
    .padding({ top: Spacing.s8, bottom: Spacing.s8 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  linkRow(link: AboutLink) {
    Row() {
      Text(link.label)
        .fontSize(FontSizeToken.body)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .layoutWeight(1)
      if (link.external) {
        Text('↗')
          .fontSize(FontSizeToken.callout)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
          .margin({ right: Spacing.s2 })
      }
      Text('›')
        .fontSize(FontSizeToken.title3)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
    }
    .width('92%')
    .height(52)
    .padding({ left: Spacing.s4, right: Spacing.s4 })
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
    .borderRadius(Radius.def)
    .margin({ bottom: Spacing.s2 })
    .onClick(() => this.onLinkTap(link))
  }

  @Builder
  footer() {
    Column({ space: Spacing.s1 }) {
      Text(COMPANY_NAME)
        .fontSize(FontSizeToken.footnote)
        .fontColor(useColor(TextColors.secondary, this.isDark))
      Text(ICP_NUMBER)
        .fontSize(FontSizeToken.caption1)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
      Text('Copyright © 2026 Readmigo CN. All rights reserved.')
        .fontSize(FontSizeToken.caption2)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
    }
    .width('100%')
    .padding({ top: Spacing.s6, bottom: Spacing.s8 })
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      this.topBar()
      Scroll() {
        Column() {
          this.header()
          ForEach(ABOUT_LINKS, (link: AboutLink) => {
            this.linkRow(link)
          }, (link: AboutLink) => link.id)
          this.footer()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(useColor(BgColors.primary, this.isDark))
  }
}
