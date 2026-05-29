// L4 Feature - Library - WatchSurface
// 3 recent books with progress, big touch targets.

import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeOpenBookshelfIntent } from '../intent/LibraryIntents';

const BG = '#0B0F1A';
const ACCENT = '#E76F1A';
const TEXT_PRIMARY = '#FFFFFF';
const TEXT_SECONDARY = '#9AA3B2';

interface RecentBook { id: string; title: string; progress: number; }

const RECENT: RecentBook[] = [
  { id: '1', title: 'Pride and Prejudice', progress: 0.45 },
  { id: '2', title: 'The Great Gatsby', progress: 0.22 },
  { id: '3', title: 'Animal Farm', progress: 0.80 },
];

@Component
export struct LibraryWatchSurface {
  @ObjectLink vm: LibraryViewModel;

  private openShelf(): void {
    IntentBus.getInstance().publish(makeOpenBookshelfIntent()).catch(() => {});
  }

  @Builder
  BookRow(book: RecentBook) {
    Row({ space: 10 }) {
      Column()
        .width(32)
        .height(44)
        .backgroundColor(ACCENT)
        .borderRadius(4)
        .opacity(0.8)
      Column({ space: 4 }) {
        Text(book.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Progress({ value: Math.round(book.progress * 100), total: 100, type: ProgressType.Linear })
          .color(ACCENT)
          .backgroundColor('#1F2532')
          .style({ strokeWidth: 3 })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  build() {
    Column({ space: 0 }) {
      Text('书架')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .padding({ top: 16, left: 16, bottom: 8 })
        .width('100%')
      Scroll() {
        Column({ space: 4 }) {
          ForEach(RECENT, (book: RecentBook) => {
            this.BookRow(book)
          }, (book: RecentBook) => book.id)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      Button('全部书架')
        .fontSize(14)
        .fontColor('#000000')
        .width(140)
        .height(56)
        .borderRadius(28)
        .backgroundColor(ACCENT)
        .margin({ bottom: 16 })
        .onClick(() => this.openShelf())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
    .alignItems(HorizontalAlign.Center)
  }
}
