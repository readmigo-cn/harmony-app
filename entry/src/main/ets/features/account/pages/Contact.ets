/**
 * Contact.ets — W19-C5 联系我们 / 联系方式页
 *
 * 内容：
 *   - 客服邮箱（点击复制）
 *   - 客服热线（点击复制）
 *   - 工作时间
 *   - 微信公众号 二维码（占位 Image）
 *   - 「在线反馈」CTA → FeedbackPage
 *
 * 复制使用 @ohos.pasteboard。
 */

import router from '@ohos.router';
import pasteboard from '@ohos.pasteboard';
import promptAction from '@ohos.promptAction';
import {
  useColor,
  TextColors,
  BgColors,
  AccentColors,
  SurfaceColors,
} from '../../../core/theme/AppColors';
import {
  FontSizeToken,
  FontWeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius } from '../../../core/theme/AppSpacing';

interface ContactItem {
  id: string;
  label: string;
  value: string;
  copyable: boolean;
}

const CONTACT_ITEMS: ContactItem[] = [
  { id: 'email',  label: '客服邮箱', value: 'support@readmigo.cn', copyable: true },
  { id: 'phone',  label: '客服热线', value: '400-000-0000（占位）', copyable: true },
  { id: 'hours',  label: '工作时间', value: '周一至周日 9:00 - 21:00', copyable: false },
  { id: 'addr',   label: '公司地址', value: '北京市通州区榆东路 2 号院 6 号楼 1 层 102', copyable: true },
];

@Entry
@Component
struct Contact {
  @State private isDark: boolean = false;

  private async copyToClipboard(text: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const sysBoard = pasteboard.getSystemPasteboard();
      await sysBoard.setData(data);
      promptAction.showToast({ message: '已复制' });
    } catch (_e) {
      promptAction.showToast({ message: '复制失败' });
    }
  }

  private goFeedback(): void {
    router.pushUrl({ url: 'features/support/pages/Feedback' }).catch((_e: Error) => {});
  }

  @Builder
  itemRow(item: ContactItem) {
    Row() {
      Column({ space: Spacing.s1 }) {
        Text(item.label)
          .fontSize(FontSizeToken.footnote)
          .fontColor(useColor(TextColors.secondary, this.isDark))
        Text(item.value)
          .fontSize(FontSizeToken.body)
          .fontColor(useColor(TextColors.primary, this.isDark))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (item.copyable) {
        Text('复制')
          .fontSize(FontSizeToken.subheadline)
          .fontColor(useColor(AccentColors.primary, this.isDark))
          .onClick(() => this.copyToClipboard(item.value))
      }
    }
    .width('92%')
    .padding(Spacing.s4)
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
    .borderRadius(Radius.def)
    .margin({ bottom: Spacing.s2 })
  }

  build() {
    Column() {
      Row() {
        Text('< 返回')
          .fontSize(FontSizeToken.callout)
          .fontColor(useColor(AccentColors.primary, this.isDark))
          .onClick(() => router.back())
        Blank()
        Text('联系我们')
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
        Column() {
          ForEach(CONTACT_ITEMS, (item: ContactItem) => {
            this.itemRow(item)
          }, (item: ContactItem) => item.id)

          Column({ space: Spacing.s2 }) {
            Text('微信公众号')
              .fontSize(FontSizeToken.footnote)
              .fontColor(useColor(TextColors.secondary, this.isDark))
            // 二维码占位：替换为 $r('app.media.wechat_qr')
            Column() {
              Text('[二维码占位]')
                .fontSize(FontSizeToken.caption1)
                .fontColor(useColor(TextColors.tertiary, this.isDark))
            }
            .width(160).height(160)
            .backgroundColor(useColor(SurfaceColors.input, this.isDark))
            .justifyContent(FlexAlign.Center)
            .borderRadius(Radius.def)
            Text('扫码关注「米果智读」获取更新与活动')
              .fontSize(FontSizeToken.caption1)
              .fontColor(useColor(TextColors.tertiary, this.isDark))
          }
          .width('92%')
          .padding(Spacing.s4)
          .backgroundColor(useColor(BgColors.elevated, this.isDark))
          .borderRadius(Radius.def)
          .alignItems(HorizontalAlign.Center)
          .margin({ top: Spacing.s2, bottom: Spacing.s4 })

          Button('在线反馈')
            .width('92%').height(48)
            .fontColor(useColor(TextColors.inverse, this.isDark))
            .backgroundColor(useColor(AccentColors.primary, this.isDark))
            .borderRadius(Radius.lg)
            .onClick(() => this.goFeedback())
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: Spacing.s4, bottom: Spacing.s8 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%').height('100%')
    .backgroundColor(useColor(BgColors.primary, this.isDark))
  }
}
