// L4 Feature - Reader - TvSurface
// Big text (≥48sp), centered, TOC overlay, remote-key navigation.

import { ReaderViewModel } from '../viewmodel/ReaderViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeJumpToChapterIntent, makeOpenTocSheetIntent } from '../intent/ReaderIntents';
import type { ReaderData } from '../viewmodel/ReaderViewModel';
import type { Chapter } from '../../../model/Chapter';

const BG = '#FBF7EE';
const TEXT = '#1A1A1A';
const SECONDARY = '#7A6A52';
const BRAND = '#E76F1A';
const DIVIDER = '#E0D8C8';

@Component
export struct ReaderTvSurface {
  @ObjectLink vm: ReaderViewModel;
  @State showToc: boolean = false;
  @State fontSize: number = 56;

  private scroller: Scroller = new Scroller();

  private get data(): ReaderData | null {
    const s = this.vm.getState();
    return s.status === 'data' ? s.data : null;
  }

  private get chapterTitle(): string {
    const d = this.data;
    if (!d) return '';
    return d.chapters?.[d.currentChapterIdx ?? 0]?.title ?? '';
  }

  private get progress(): number {
    const d = this.data;
    if (!d?.chapters?.length) return 0;
    return ((d.currentChapterIdx ?? 0) + 1) / d.chapters.length;
  }

  private scrollDown(): void {
    this.scroller.scrollBy(0, 600);
  }

  private scrollUp(): void {
    this.scroller.scrollBy(0, -600);
  }

  private jumpToChapter(ch: Chapter): void {
    IntentBus.getInstance().publish(makeJumpToChapterIntent(ch.id)).catch(() => {});
    this.showToc = false;
  }

  @Builder
  TocOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => { this.showToc = false; })

      Column({ space: 0 }) {
        Text('目录')
          .fontSize(48)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT)
          .padding({ left: 60, right: 60, top: 48, bottom: 24 })
        Divider().color(DIVIDER).strokeWidth(2)
        List() {
          ForEach(this.data?.chapters ?? [], (ch: Chapter) => {
            ListItem() {
              Text(ch.title)
                .fontSize(36)
                .fontColor(this.data?.currentChapterIdx === ch.index ? BRAND : TEXT)
                .width('100%')
                .padding({ left: 60, right: 60, top: 20, bottom: 20 })
                .focusable(true)
                .onClick(() => this.jumpToChapter(ch))
            }
          }, (ch: Chapter) => ch.id)
        }
        .divider({ strokeWidth: 1, color: DIVIDER })
        .layoutWeight(1)
      }
      .width(600)
      .height('100%')
      .backgroundColor(BG)
      .alignSelf(ItemAlign.Start)
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
  }

  build() {
    Stack() {
      Column() {
        Progress({ value: this.progress * 100, total: 100, type: ProgressType.Linear })
          .color(BRAND)
          .backgroundColor(DIVIDER)
          .style({ strokeWidth: 6 })
          .width('100%')

        Scroll(this.scroller) {
          Column({ space: 32 }) {
            Text(this.chapterTitle)
              .fontSize(this.fontSize + 12)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT)
              .width('100%')
            Text(this.data?.currentContent?.html ?? '正在加载…')
              .fontSize(this.fontSize)
              .fontColor(TEXT)
              .lineHeight(this.fontSize * 1.6)
              .width('100%')
            Blank().height(160)
          }
          .padding({ left: 80, right: 80, top: 48 })
          .constraintSize({ maxWidth: 1400 })
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')

        Row({ space: 40 }) {
          Text(`第 ${(this.data?.currentChapterIdx ?? 0) + 1} 章`)
            .fontSize(24)
            .fontColor(SECONDARY)
          Text(`${Math.round(this.progress * 100)}%`)
            .fontSize(24)
            .fontColor(SECONDARY)
          Blank()
          Button('目录')
            .fontSize(28)
            .fontColor('#000000')
            .height(56)
            .padding({ left: 32, right: 32 })
            .backgroundColor(BRAND)
            .borderRadius(8)
            .focusable(true)
            .onClick(() => { this.showToc = !this.showToc; })
          Button('↑')
            .fontSize(28)
            .fontColor('#000000')
            .width(56)
            .height(56)
            .backgroundColor(BRAND)
            .borderRadius(8)
            .focusable(true)
            .onClick(() => this.scrollUp())
          Button('↓')
            .fontSize(28)
            .fontColor('#000000')
            .width(56)
            .height(56)
            .backgroundColor(BRAND)
            .borderRadius(8)
            .focusable(true)
            .onClick(() => this.scrollDown())
        }
        .width('100%')
        .padding({ left: 80, right: 80, top: 16, bottom: 16 })
        .backgroundColor(BG)
        .border({ width: { top: 1 }, color: DIVIDER })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)

      if (this.showToc) {
        this.TocOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
