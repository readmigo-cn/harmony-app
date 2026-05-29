// L4 Feature - Account - TabletSurface
// Profile/menu sidebar on left + content panel on right.

import { AccountViewModel } from '../viewmodel/AccountViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeOpenAccountIntent, makeOpenSubscriptionsIntent } from '../intent/AccountIntents';
import type { AccountData } from '../viewmodel/AccountViewModel';

const BG = '#FFFFFF';
const BG_SIDEBAR = '#F8F8F8';
const TEXT = '#1A1A1A';
const SECONDARY = '#666666';
const BRAND = '#E76F1A';
const DIVIDER = '#E8E8E8';

interface MenuEntry { key: string; label: string; }

const MENU_ITEMS: MenuEntry[] = [
  { key: 'profile', label: '个人信息' },
  { key: 'subscriptions', label: '订阅管理' },
  { key: 'stats', label: '阅读统计' },
  { key: 'settings', label: '设置' },
];

@Component
export struct AccountTabletSurface {
  @ObjectLink vm: AccountViewModel;
  @State activeSection: string = 'profile';

  private get data(): AccountData | null {
    const s = this.vm.getState();
    return s.status === 'data' ? s.data : null;
  }

  private selectSection(key: string): void {
    this.activeSection = key;
    if (key === 'subscriptions') {
      IntentBus.getInstance().publish(makeOpenSubscriptionsIntent()).catch(() => {});
    } else {
      IntentBus.getInstance().publish(makeOpenAccountIntent()).catch(() => {});
    }
  }

  @Builder
  Sidebar() {
    Column({ space: 0 }) {
      Column({ space: 8 }) {
        Column()
          .width(80)
          .height(80)
          .backgroundColor(BRAND)
          .borderRadius(40)
          .opacity(0.8)
        Text('用户名')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT)
        Text('user@example.com')
          .fontSize(13)
          .fontColor(SECONDARY)
      }
      .padding({ top: 32, bottom: 24 })
      .alignItems(HorizontalAlign.Center)
      .width('100%')

      Divider().color(DIVIDER).strokeWidth(1)

      ForEach(MENU_ITEMS, (item: MenuEntry) => {
        Row() {
          Text(item.label)
            .fontSize(16)
            .fontColor(this.activeSection === item.key ? BRAND : TEXT)
            .fontWeight(this.activeSection === item.key ? FontWeight.Bold : FontWeight.Regular)
            .layoutWeight(1)
          if (this.activeSection === item.key) {
            Text('●').fontSize(10).fontColor(BRAND)
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 18, bottom: 18 })
        .backgroundColor(this.activeSection === item.key ? '#FFF3EB' : 'transparent')
        .onClick(() => this.selectSection(item.key))
      }, (item: MenuEntry) => item.key)
    }
    .width('35%')
    .height('100%')
    .backgroundColor(BG_SIDEBAR)
    .border({ width: { right: 1 }, color: DIVIDER })
  }

  @Builder
  ContentPanel() {
    Column({ space: 24 }) {
      if (this.activeSection === 'profile') {
        Text('个人信息').fontSize(24).fontWeight(FontWeight.Bold).fontColor(TEXT)
        Column({ space: 16 }) {
          this.InfoRow('用户名', '用户名')
          this.InfoRow('邮箱', 'user@example.com')
          this.InfoRow('注册时间', '2024-01-01')
          this.InfoRow('等级', 'B2')
        }
      } else if (this.activeSection === 'subscriptions') {
        Text('订阅管理').fontSize(24).fontWeight(FontWeight.Bold).fontColor(TEXT)
        Column({ space: 16 }) {
          Text('当前订阅：标准版').fontSize(16).fontColor(TEXT)
          Text('到期时间：2025-12-31').fontSize(16).fontColor(SECONDARY)
          Button('升级订阅').fontSize(16).fontColor('#FFFFFF').backgroundColor(BRAND)
            .borderRadius(8).padding({ left: 24, right: 24, top: 12, bottom: 12 })
        }
        .alignItems(HorizontalAlign.Start)
      } else {
        Text(this.activeSection).fontSize(24).fontWeight(FontWeight.Bold).fontColor(TEXT)
        Text('内容开发中…').fontSize(16).fontColor(SECONDARY)
      }
    }
    .padding(40)
    .width('65%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(BG)
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row({ space: 16 }) {
      Text(label).fontSize(15).fontColor(SECONDARY).width(80)
      Text(value).fontSize(15).fontColor(TEXT).layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: 1 }, color: DIVIDER })
  }

  build() {
    Row() {
      this.Sidebar()
      this.ContentPanel()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
