// L4 Feature - Library - TvSurface
// 4-column grid, big text, D-pad focus traversal.

import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeOpenBookshelfIntent } from '../intent/LibraryIntents';

const BG = '#0F1018';
const CARD_BG = '#1A1D28';
const ACCENT = '#E76F1A';
const TEXT_PRIMARY = '#F5F5F7';
const TEXT_SECONDARY = '#9AA3B2';

interface TvBook { id: string; title: string; author: string; progress: number; }

const TV_BOOKS: TvBook[] = [
  { id: '1', title: 'Pride and Prejudice', author: 'Jane Austen', progress: 0.45 },
  { id: '2', title: 'The Great Gatsby', author: 'F. Scott Fitzgerald', progress: 0.22 },
  { id: '3', title: 'Animal Farm', author: 'George Orwell', progress: 0.80 },
  { id: '4', title: 'Brave New World', author: 'Aldous Huxley', progress: 0.10 },
  { id: '5', title: 'The Old Man and the Sea', author: 'Hemingway', progress: 0.60 },
  { id: '6', title: '1984', author: 'George Orwell', progress: 0.35 },
  { id: '7', title: 'Frankenstein', author: 'Mary Shelley', progress: 0.05 },
  { id: '8', title: 'Jane Eyre', author: 'Charlotte Brontë', progress: 0.15 },
];

@Component
export struct LibraryTvSurface {
  @ObjectLink vm: LibraryViewModel;
  @State focusedId: string = '';

  aboutToAppear(): void {
    IntentBus.getInstance().publish(makeOpenBookshelfIntent()).catch(() => {});
  }

  @Builder
  BookCard(book: TvBook) {
    Column({ space: 12 }) {
      Column()
        .width('100%')
        .height(180)
        .backgroundColor(ACCENT)
        .borderRadius(8)
        .opacity(0.7)
      Text(book.title)
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(book.author)
        .fontSize(24)
        .fontColor(TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Progress({ value: Math.round(book.progress * 100), total: 100, type: ProgressType.Linear })
        .color(ACCENT)
        .backgroundColor('#1F2532')
        .style({ strokeWidth: 4 })
        .width('100%')
      Text(`${Math.round(book.progress * 100)}% 已读`)
        .fontSize(22)
        .fontColor(ACCENT)
    }
    .padding(20)
    .backgroundColor(this.focusedId === book.id ? '#252836' : CARD_BG)
    .borderRadius(12)
    .border({
      width: this.focusedId === book.id ? 3 : 0,
      color: ACCENT,
      radius: 12,
    })
    .scale({ x: this.focusedId === book.id ? 1.04 : 1.0, y: this.focusedId === book.id ? 1.04 : 1.0 })
    .focusable(true)
    .onFocus(() => { this.focusedId = book.id; })
    .onBlur(() => { if (this.focusedId === book.id) this.focusedId = ''; })
  }

  build() {
    Column({ space: 0 }) {
      Text('我的书架')
        .fontSize(56)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .padding({ left: 80, right: 80, top: 60, bottom: 32 })
        .width('100%')
      GridRow({ columns: 4, gutter: { x: 32, y: 32 } }) {
        ForEach(TV_BOOKS, (book: TvBook) => {
          GridCol() {
            this.BookCard(book)
          }
        }, (book: TvBook) => book.id)
      }
      .padding({ left: 80, right: 80, bottom: 60 })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
