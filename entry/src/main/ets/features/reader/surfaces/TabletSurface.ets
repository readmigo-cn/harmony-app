// L4 Feature - Reader - TabletSurface
// Two-pane layout: TOC always-visible on right 40%, text on left 60%.

import { ReaderViewModel } from '../viewmodel/ReaderViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeJumpToChapterIntent, makeOpenTocSheetIntent } from '../intent/ReaderIntents';
import type { ReaderData } from '../viewmodel/ReaderViewModel';
import type { Chapter } from '../../../model/Chapter';

const BG = '#FBF7EE';
const TEXT = '#1A1A1A';
const SECONDARY = '#666666';
const BRAND = '#E76F1A';
const DIVIDER = '#E0D8C8';

@Component
export struct ReaderTabletSurface {
  @ObjectLink vm: ReaderViewModel;

  private get data(): ReaderData | null {
    const s = this.vm.getState();
    return s.status === 'data' ? s.data : null;
  }

  private jumpToChapter(ch: Chapter): void {
    IntentBus.getInstance().publish(makeJumpToChapterIntent(ch.id)).catch(() => {});
  }

  @Builder
  TocPane() {
    Column({ space: 0 }) {
      Text('目录')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT)
        .padding({ left: 24, right: 24, top: 24, bottom: 16 })
        .width('100%')
      Divider().color(DIVIDER).strokeWidth(1)
      List() {
        ForEach(this.data?.chapters ?? [], (ch: Chapter) => {
          ListItem() {
            Row() {
              Text(ch.title)
                .fontSize(16)
                .fontColor(this.data?.currentChapterIdx === ch.index ? BRAND : TEXT)
                .layoutWeight(1)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.data?.currentChapterIdx === ch.index) {
                Text('●').fontSize(10).fontColor(BRAND)
              }
            }
            .width('100%')
            .padding({ left: 24, right: 20, top: 14, bottom: 14 })
            .onClick(() => this.jumpToChapter(ch))
          }
        }, (ch: Chapter) => ch.id)
      }
      .divider({ strokeWidth: 1, color: DIVIDER })
      .layoutWeight(1)
    }
    .width('40%')
    .height('100%')
    .backgroundColor('#F4ECD8')
    .border({ width: { left: 1 }, color: DIVIDER })
  }

  @Builder
  ContentPane() {
    Column() {
      if (this.data === null) {
        Column() {
          LoadingProgress().width(40).height(40).color(BRAND)
          Text('加载中…').fontSize(14).fontColor(SECONDARY).margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Column({ space: 0 }) {
          Text(this.data?.chapters?.[this.data.currentChapterIdx ?? 0]?.title ?? '')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT)
            .padding({ left: 40, right: 40, top: 32, bottom: 16 })
            .width('100%')
          Scroll() {
            Text(this.data?.currentContent?.html ?? '正在加载章节内容…')
              .fontSize(18)
              .fontColor(TEXT)
              .lineHeight(30)
              .width('100%')
              .padding({ left: 40, right: 40, bottom: 40 })
          }
          .scrollBar(BarState.Auto)
          .layoutWeight(1)
          .width('100%')
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('60%')
    .height('100%')
    .backgroundColor(BG)
  }

  build() {
    Row() {
      this.ContentPane()
      this.TocPane()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
