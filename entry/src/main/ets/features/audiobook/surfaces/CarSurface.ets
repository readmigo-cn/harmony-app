// L4 Feature - Audiobook - CarSurface
// Massive play/pause/skip controls, no scrolling.

import { AudiobookViewModel } from '../viewmodel/AudiobookViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makePlayAudiobookIntent, makePauseAudiobookIntent } from '../intent/AudiobookIntents';
import type { AudiobookCatalogState } from '../viewmodel/AudiobookViewModel';

const BG = '#000000';
const ACCENT = '#7C3AED';
const TEXT_PRIMARY = '#FFFFFF';
const TEXT_DIM = '#9AA3B2';

@Component
export struct AudiobookCarSurface {
  @ObjectLink vm: AudiobookViewModel;
  @StorageLink('car_lock_active') lockActive: boolean = false;
  @State localState: AudiobookCatalogState | null = null;

  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsub = this.vm.subscribeState((s) => {
      if (s.status === 'data') this.localState = s.data;
    });
  }

  aboutToDisappear(): void {
    this.unsub?.();
    this.unsub = null;
  }

  private toggle(): void {
    if (this.lockActive) return;
    const s = this.localState;
    if (!s) return;
    if (s.playing) {
      IntentBus.getInstance().publish(makePauseAudiobookIntent()).catch(() => {});
    } else {
      IntentBus.getInstance().publish(makePlayAudiobookIntent(s.bookId)).catch(() => {});
    }
  }

  build() {
    Stack() {
      Column({ space: 48 }) {
        Column({ space: 8 }) {
          Text('正在播放')
            .fontSize(28)
            .fontColor(TEXT_DIM)
          Text(this.localState?.bookId ? '有声书' : '请选择有声书')
            .fontSize(48)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`速度 ${this.localState?.speed ?? 1.0}x`)
            .fontSize(28)
            .fontColor(TEXT_DIM)
        }
        .alignItems(HorizontalAlign.Center)
        .width('88%')

        Row({ space: 48 }) {
          Button('|◀')
            .fontSize(40)
            .fontColor('#FFFFFF')
            .width(160)
            .height(160)
            .borderRadius(80)
            .backgroundColor('#1A1A2E')
            .onClick(() => {})

          Button(this.localState?.playing ? '⏸' : '▶')
            .fontSize(64)
            .fontColor('#FFFFFF')
            .width(220)
            .height(220)
            .borderRadius(110)
            .backgroundColor(ACCENT)
            .onClick(() => this.toggle())

          Button('▶|')
            .fontSize(40)
            .fontColor('#FFFFFF')
            .width(160)
            .height(160)
            .borderRadius(80)
            .backgroundColor('#1A1A2E')
            .onClick(() => {})
        }
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
