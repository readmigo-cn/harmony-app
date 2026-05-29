// L4 Feature - Account - WatchSurface
// Avatar + 3 menu rows, big touch targets ≥56dp.

import { AccountViewModel } from '../viewmodel/AccountViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeOpenAccountIntent, makeOpenSubscriptionsIntent } from '../intent/AccountIntents';

const BG = '#0B0F1A';
const ACCENT = '#E76F1A';
const TEXT_PRIMARY = '#FFFFFF';
const TEXT_SECONDARY = '#9AA3B2';

@Component
export struct AccountWatchSurface {
  @ObjectLink vm: AccountViewModel;

  private openProfile(): void {
    IntentBus.getInstance().publish(makeOpenAccountIntent()).catch(() => {});
  }

  private openSubs(): void {
    IntentBus.getInstance().publish(makeOpenSubscriptionsIntent()).catch(() => {});
  }

  @Builder
  MenuRow(label: string, handler: () => void) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .layoutWeight(1)
      Text('›')
        .fontSize(20)
        .fontColor(TEXT_SECONDARY)
    }
    .width('100%')
    .height(56)
    .padding({ left: 20, right: 20 })
    .backgroundColor('#1F2532')
    .borderRadius(12)
    .onClick(handler)
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 6 }) {
        Column()
          .width(64)
          .height(64)
          .backgroundColor(ACCENT)
          .borderRadius(32)
          .opacity(0.9)
          .margin({ top: 20 })
        Text('我的')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
      }
      .alignItems(HorizontalAlign.Center)

      Column({ space: 8 }) {
        this.MenuRow('个人信息', () => this.openProfile())
        this.MenuRow('订阅管理', () => this.openSubs())
        this.MenuRow('阅读统计', () => {})
      }
      .width('88%')
      .padding({ bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
    .alignItems(HorizontalAlign.Center)
  }
}
