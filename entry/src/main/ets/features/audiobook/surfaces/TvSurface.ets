// L4 Feature - Audiobook - TvSurface
// Hero artwork + big controls, focus-traversable.

import { AudiobookViewModel } from '../viewmodel/AudiobookViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makePlayAudiobookIntent, makePauseAudiobookIntent, makeSetSpeedIntent } from '../intent/AudiobookIntents';
import type { AudiobookCatalogState } from '../viewmodel/AudiobookViewModel';
import type { PlaybackSpeed } from '../../../model/Audiobook';
import type { AudiobookItem } from '../../../api/audiobooks/AudiobookApi';

const BG = '#0F1018';
const CARD_BG = '#1A1D28';
const ACCENT = '#7C3AED';
const TEXT_PRIMARY = '#F5F5F7';
const TEXT_SECONDARY = '#9AA3B2';

@Component
export struct AudiobookTvSurface {
  @ObjectLink vm: AudiobookViewModel;
  @State localState: AudiobookCatalogState | null = null;
  @State focusedId: string = '';

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

  private playBook(bookId: string): void {
    IntentBus.getInstance().publish(makePlayAudiobookIntent(bookId)).catch(() => {});
  }

  private bumpSpeed(): void {
    const speeds: PlaybackSpeed[] = [0.75, 1.0, 1.25, 1.5, 2.0];
    const cur = this.localState?.speed ?? 1.0;
    const idx = speeds.indexOf(cur as PlaybackSpeed);
    const next = speeds[(idx + 1) % speeds.length] ?? 1.0;
    IntentBus.getInstance().publish(makeSetSpeedIntent(next)).catch(() => {});
  }

  @Builder
  HeroSection() {
    Row({ space: 80 }) {
      Column()
        .width(320)
        .height(320)
        .backgroundColor(ACCENT)
        .borderRadius(16)
        .opacity(0.8)

      Column({ space: 24 }) {
        Text(this.localState?.bookId ? '有声书' : '请选择有声书')
          .fontSize(56)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.localState?.chapterId ?? '')
          .fontSize(36)
          .fontColor(TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 32 }) {
          Button('|◀')
            .fontSize(36)
            .fontColor('#FFFFFF')
            .width(100)
            .height(100)
            .borderRadius(50)
            .backgroundColor(CARD_BG)
            .focusable(true)
            .onClick(() => {})

          Button(this.localState?.playing ? '⏸' : '▶')
            .fontSize(48)
            .fontColor('#FFFFFF')
            .width(140)
            .height(140)
            .borderRadius(70)
            .backgroundColor(ACCENT)
            .focusable(true)
            .onClick(() => this.toggle())

          Button('▶|')
            .fontSize(36)
            .fontColor('#FFFFFF')
            .width(100)
            .height(100)
            .borderRadius(50)
            .backgroundColor(CARD_BG)
            .focusable(true)
            .onClick(() => {})

          Button(`${this.localState?.speed ?? 1.0}x`)
            .fontSize(32)
            .fontColor('#FFFFFF')
            .width(100)
            .height(60)
            .borderRadius(8)
            .backgroundColor(CARD_BG)
            .focusable(true)
            .onClick(() => this.bumpSpeed())
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .padding({ left: 80, right: 80, top: 60, bottom: 40 })
    .width('100%')
  }

  @Builder
  CatalogSection() {
    Column({ space: 16 }) {
      Text('更多有声书')
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .padding({ left: 80 })
        .width('100%')
      List({ space: 0 }) {
        ForEach(this.localState?.popular ?? [], (book: AudiobookItem) => {
          ListItem() {
            Row({ space: 24 }) {
              Column()
                .width(80)
                .height(100)
                .backgroundColor(ACCENT)
                .borderRadius(8)
                .opacity(0.7)
              Column({ space: 8 }) {
                Text(book.title)
                  .fontSize(32)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(TEXT_PRIMARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(book.author ?? '')
                  .fontSize(24)
                  .fontColor(TEXT_SECONDARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 80, right: 80, top: 16, bottom: 16 })
            .backgroundColor(this.focusedId === book.id ? '#252836' : BG)
            .focusable(true)
            .onFocus(() => { this.focusedId = book.id; })
            .onBlur(() => { if (this.focusedId === book.id) this.focusedId = ''; })
            .onClick(() => this.playBook(book.id))
          }
        }, (book: AudiobookItem) => book.id)
      }
      .divider({ strokeWidth: 1, color: '#252836' })
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Column() {
      this.HeroSection()
      Divider().color('#252836').strokeWidth(1).width('100%').padding({ left: 80, right: 80 })
      this.CatalogSection()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
