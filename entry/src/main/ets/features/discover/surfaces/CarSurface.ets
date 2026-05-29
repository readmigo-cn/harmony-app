// L4 Feature - Discover - CarSurface
// Voice command list: "read newest", "open library". Minimal UI.

import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeBrowseDiscoverIntent } from '../intent/DiscoverIntents';

const BG = '#000000';
const ACCENT = '#7C3AED';
const TEXT_PRIMARY = '#FFFFFF';
const TEXT_DIM = '#9AA3B2';

interface VoiceCmd { label: string; hint: string; tab?: string; }

const COMMANDS: VoiceCmd[] = [
  { label: '阅读最新', hint: '说"阅读最新"', tab: '新书' },
  { label: '打开书架', hint: '说"我的书架"' },
  { label: '精选推荐', hint: '说"精选推荐"', tab: '精选' },
];

@Component
export struct DiscoverCarSurface {
  @ObjectLink vm: DiscoverViewModel;
  @StorageLink('car_lock_active') lockActive: boolean = false;

  private browse(tab?: string): void {
    if (this.lockActive) return;
    IntentBus.getInstance().publish(makeBrowseDiscoverIntent(tab)).catch(() => {});
  }

  @Builder
  CmdButton(cmd: VoiceCmd) {
    Column({ space: 8 }) {
      Button(cmd.label)
        .fontSize(40)
        .fontColor('#FFFFFF')
        .width('88%')
        .height(120)
        .borderRadius(16)
        .backgroundColor(ACCENT)
        .onClick(() => this.browse(cmd.tab))
      Text(cmd.hint)
        .fontSize(24)
        .fontColor(TEXT_DIM)
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }

  build() {
    Stack() {
      Column({ space: 32 }) {
        Text('发现好书')
          .fontSize(48)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
        Text('请选择或使用语音')
          .fontSize(32)
          .fontColor(TEXT_DIM)
        Column({ space: 24 }) {
          ForEach(COMMANDS, (cmd: VoiceCmd) => {
            this.CmdButton(cmd)
          }, (cmd: VoiceCmd) => cmd.label)
        }
        .width('100%')
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
