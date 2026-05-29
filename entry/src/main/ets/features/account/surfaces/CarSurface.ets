// L4 Feature - Account - CarSurface
// Minimal: just "log out" + avatar. Car context = no complex account ops.

import { AccountViewModel } from '../viewmodel/AccountViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeOpenAccountIntent } from '../intent/AccountIntents';

const BG = '#000000';
const ACCENT = '#7C3AED';
const TEXT_PRIMARY = '#FFFFFF';
const TEXT_DIM = '#9AA3B2';

@Component
export struct AccountCarSurface {
  @ObjectLink vm: AccountViewModel;
  @StorageLink('car_lock_active') lockActive: boolean = false;

  private openAccount(): void {
    if (this.lockActive) return;
    IntentBus.getInstance().publish(makeOpenAccountIntent()).catch(() => {});
  }

  build() {
    Stack() {
      Column({ space: 40 }) {
        Column({ space: 12 }) {
          Column()
            .width(120)
            .height(120)
            .backgroundColor(ACCENT)
            .borderRadius(60)
            .opacity(0.8)
          Text('用户账户')
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
          Text('请在手机端管理账户')
            .fontSize(28)
            .fontColor(TEXT_DIM)
        }
        .alignItems(HorizontalAlign.Center)

        Button('账户详情')
          .fontSize(36)
          .fontColor('#FFFFFF')
          .width(300)
          .height(120)
          .borderRadius(16)
          .backgroundColor(ACCENT)
          .onClick(() => this.openAccount())
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(BG)

      if (this.lockActive) {
        Column() {
          Text('行驶中，请使用语音操控')
            .fontSize(44)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('rgba(0,0,0,0.55)')
        .onClick(() => {})
      }
    }
    .width('100%')
    .height('100%')
  }
}
