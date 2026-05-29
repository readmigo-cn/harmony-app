// L4 Feature - Audiobook - WatchSurface
// Now-playing + big play/pause button.

import { AudiobookViewModel } from '../viewmodel/AudiobookViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makePlayAudiobookIntent, makePauseAudiobookIntent } from '../intent/AudiobookIntents';
import type { AudiobookCatalogState } from '../viewmodel/AudiobookViewModel';

const BG = '#0B0F1A';
const ACCENT = '#7C3AED';
const TEXT_PRIMARY = '#FFFFFF';
const TEXT_SECONDARY = '#9AA3B2';

@Component
export struct AudiobookWatchSurface {
  @ObjectLink vm: AudiobookViewModel;
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
    const s = this.localState;
    if (!s) return;
    if (s.playing) {
      IntentBus.getInstance().publish(makePauseAudiobookIntent()).catch(() => {});
    } else {
      IntentBus.getInstance().publish(makePlayAudiobookIntent(s.bookId)).catch(() => {});
    }
  }

  build() {
    Column({ space: 16 }) {
      Column()
        .width(100)
        .height(100)
        .backgroundColor(ACCENT)
        .borderRadius(50)
        .opacity(0.8)
        .margin({ top: 24 })

      Text(this.localState?.bookId ? '有声书' : '未播放')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('80%')

      Text(`${this.localState?.speed ?? 1.0}x`)
        .fontSize(13)
        .fontColor(TEXT_SECONDARY)

      Button(this.localState?.playing ? '⏸' : '▶')
        .fontSize(28)
        .fontColor('#FFFFFF')
        .width(80)
        .height(80)
        .borderRadius(40)
        .backgroundColor(ACCENT)
        .onClick(() => this.toggle())
        .margin({ bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(BG)
  }
}
