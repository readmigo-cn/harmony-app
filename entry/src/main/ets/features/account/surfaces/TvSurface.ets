// L4 Feature - Account - TvSurface
// Full-bleed avatar + menu, big text ≥48sp, focus-traversable.

import { AccountViewModel } from '../viewmodel/AccountViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeOpenAccountIntent, makeOpenSubscriptionsIntent } from '../intent/AccountIntents';

const BG = '#0F1018';
const CARD_BG = '#1A1D28';
const ACCENT = '#E76F1A';
const TEXT_PRIMARY = '#F5F5F7';
const TEXT_SECONDARY = '#9AA3B2';

interface TvMenuEntry { key: string; label: string; desc: string; }

const TV_MENU: TvMenuEntry[] = [
  { key: 'profile', label: '个人信息', desc: '查看和编辑个人资料' },
  { key: 'subscriptions', label: '订阅管理', desc: '管理您的订阅计划' },
  { key: 'stats', label: '阅读统计', desc: '查看阅读数据和成就' },
  { key: 'settings', label: '设置', desc: '应用偏好与通知设置' },
];

@Component
export struct AccountTvSurface {
  @ObjectLink vm: AccountViewModel;
  @State focusedKey: string = '';

  private selectItem(key: string): void {
    if (key === 'subscriptions') {
      IntentBus.getInstance().publish(makeOpenSubscriptionsIntent()).catch(() => {});
    } else {
      IntentBus.getInstance().publish(makeOpenAccountIntent()).catch(() => {});
    }
  }

  @Builder
  AvatarSection() {
    Column({ space: 16 }) {
      Column()
        .width(200)
        .height(200)
        .backgroundColor(ACCENT)
        .borderRadius(100)
        .opacity(0.85)
      Text('用户名')
        .fontSize(48)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
      Text('user@example.com')
        .fontSize(32)
        .fontColor(TEXT_SECONDARY)
      Text('Lv. B2 · 已阅读 42 本')
        .fontSize(28)
        .fontColor(ACCENT)
    }
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 80, bottom: 48 })
    .width('100%')
  }

  @Builder
  MenuSection() {
    Row({ space: 40 }) {
      ForEach(TV_MENU, (item: TvMenuEntry) => {
        Column({ space: 16 }) {
          Text(item.label)
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.focusedKey === item.key ? '#000000' : TEXT_PRIMARY)
          Text(item.desc)
            .fontSize(28)
            .fontColor(this.focusedKey === item.key ? '#1A1A1A' : TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .padding(32)
        .backgroundColor(this.focusedKey === item.key ? ACCENT : CARD_BG)
        .borderRadius(16)
        .border({
          width: this.focusedKey === item.key ? 3 : 0,
          color: ACCENT,
          radius: 16,
        })
        .scale({ x: this.focusedKey === item.key ? 1.05 : 1.0, y: this.focusedKey === item.key ? 1.05 : 1.0 })
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .focusable(true)
        .onFocus(() => { this.focusedKey = item.key; })
        .onBlur(() => { if (this.focusedKey === item.key) this.focusedKey = ''; })
        .onClick(() => this.selectItem(item.key))
      }, (item: TvMenuEntry) => item.key)
    }
    .padding({ left: 80, right: 80, bottom: 60 })
    .width('100%')
  }

  build() {
    Column() {
      this.AvatarSection()
      this.MenuSection()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
