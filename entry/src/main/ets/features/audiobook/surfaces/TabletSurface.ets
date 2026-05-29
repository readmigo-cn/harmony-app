// L4 Feature - Audiobook - TabletSurface
// Catalog left + mini-player right split layout.

import { AudiobookViewModel } from '../viewmodel/AudiobookViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makePlayAudiobookIntent, makePauseAudiobookIntent } from '../intent/AudiobookIntents';
import type { AudiobookCatalogState } from '../viewmodel/AudiobookViewModel';
import type { AudiobookItem } from '../../../api/audiobooks/AudiobookApi';

const BG = '#FFFFFF';
const BG_PANEL = '#F8F8F8';
const TEXT = '#1A1A1A';
const SECONDARY = '#666666';
const BRAND = '#7C3AED';
const DIVIDER = '#E8E8E8';

@Component
export struct AudiobookTabletSurface {
  @ObjectLink vm: AudiobookViewModel;
  @State localState: AudiobookCatalogState | null = null;

  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsub = this.vm.subscribeState((s) => {
      if (s.status === 'data') this.localState = s.data;
      else this.localState = null;
    });
  }

  aboutToDisappear(): void {
    this.unsub?.();
    this.unsub = null;
  }

  private playBook(bookId: string): void {
    IntentBus.getInstance().publish(makePlayAudiobookIntent(bookId)).catch(() => {});
  }

  private togglePlay(): void {
    const s = this.localState;
    if (!s) return;
    if (s.playing) {
      IntentBus.getInstance().publish(makePauseAudiobookIntent()).catch(() => {});
    } else {
      IntentBus.getInstance().publish(makePlayAudiobookIntent(s.bookId)).catch(() => {});
    }
  }

  @Builder
  CatalogPane() {
    Column() {
      Text('有声书')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT)
        .padding({ left: 24, right: 24, top: 24, bottom: 16 })
        .width('100%')
      Divider().color(DIVIDER).strokeWidth(1)
      List({ space: 0 }) {
        ForEach(this.localState?.popular ?? [], (book: AudiobookItem) => {
          ListItem() {
            Row({ space: 16 }) {
              Column()
                .width(60)
                .height(80)
                .backgroundColor(BRAND)
                .borderRadius(6)
                .opacity(0.7)
              Column({ space: 4 }) {
                Text(book.title)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(TEXT)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(book.author ?? '')
                  .fontSize(13)
                  .fontColor(SECONDARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            .onClick(() => this.playBook(book.id))
          }
        }, (book: AudiobookItem) => book.id)
      }
      .divider({ strokeWidth: 1, color: DIVIDER })
      .layoutWeight(1)
    }
    .width('60%')
    .height('100%')
    .backgroundColor(BG)
  }

  @Builder
  PlayerPane() {
    Column({ space: 24 }) {
      Column()
        .width(160)
        .height(160)
        .backgroundColor(BRAND)
        .borderRadius(80)
        .opacity(0.8)

      Text(this.localState?.bookId ? '播放中' : '未播放')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT)

      Text(this.localState?.chapterId ?? '')
        .fontSize(14)
        .fontColor(SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('80%')
        .textAlign(TextAlign.Center)

      Row({ space: 24 }) {
        Button(this.localState?.playing ? '⏸ 暂停' : '▶ 播放')
          .fontSize(18)
          .fontColor('#FFFFFF')
          .width(120)
          .height(48)
          .backgroundColor(BRAND)
          .borderRadius(24)
          .onClick(() => this.togglePlay())
      }

      Text(`速度 ${this.localState?.speed ?? 1.0}x`)
        .fontSize(14)
        .fontColor(SECONDARY)
    }
    .width('40%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(BG_PANEL)
    .border({ width: { left: 1 }, color: DIVIDER })
  }

  build() {
    Row() {
      this.CatalogPane()
      this.PlayerPane()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
