// L4 Feature - Discover - WatchSurface
// Latest 3 picks in a scroll card.

import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeBrowseDiscoverIntent } from '../intent/DiscoverIntents';

const BG = '#0B0F1A';
const ACCENT = '#E76F1A';
const TEXT_PRIMARY = '#FFFFFF';
const TEXT_SECONDARY = '#9AA3B2';

interface Pick { title: string; level: string; }

const PICKS: Pick[] = [
  { title: 'Pride & Prejudice', level: 'B2' },
  { title: 'Animal Farm', level: 'B1' },
  { title: 'The Great Gatsby', level: 'B2' },
];

@Component
export struct DiscoverWatchSurface {
  @ObjectLink vm: DiscoverViewModel;

  private browse(): void {
    IntentBus.getInstance().publish(makeBrowseDiscoverIntent()).catch(() => {});
  }

  @Builder
  PickRow(pick: Pick) {
    Row({ space: 12 }) {
      Column()
        .width(36)
        .height(50)
        .backgroundColor(ACCENT)
        .borderRadius(4)
        .opacity(0.8)
      Column({ space: 4 }) {
        Text(pick.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(pick.level)
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  build() {
    Column({ space: 8 }) {
      Text('今日推荐')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .padding({ top: 16, left: 16 })
        .width('100%')
      Scroll() {
        Column({ space: 4 }) {
          ForEach(PICKS, (p: Pick) => {
            this.PickRow(p)
          }, (p: Pick) => p.title)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      Button('浏览更多')
        .fontSize(14)
        .fontColor('#000000')
        .width(140)
        .height(56)
        .borderRadius(28)
        .backgroundColor(ACCENT)
        .margin({ bottom: 16 })
        .onClick(() => this.browse())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
    .alignItems(HorizontalAlign.Center)
  }
}
