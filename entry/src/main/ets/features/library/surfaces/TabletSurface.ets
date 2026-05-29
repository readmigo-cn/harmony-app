// L4 Feature - Library - TabletSurface
// 3-column grid layout for tablet/foldable.

import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeOpenBookshelfIntent } from '../intent/LibraryIntents';

const BG = '#FFFFFF';
const TEXT = '#1A1A1A';
const SECONDARY = '#666666';
const BRAND = '#E76F1A';
const BG_CARD = '#F8F8F8';

interface ShelfBook { id: string; title: string; author: string; progress: number; }

const SHELF_BOOKS: ShelfBook[] = [
  { id: '1', title: 'Pride and Prejudice', author: 'Jane Austen', progress: 0.45 },
  { id: '2', title: 'The Great Gatsby', author: 'F. Scott Fitzgerald', progress: 0.22 },
  { id: '3', title: 'Animal Farm', author: 'George Orwell', progress: 0.80 },
  { id: '4', title: 'Brave New World', author: 'Aldous Huxley', progress: 0.10 },
  { id: '5', title: 'The Old Man and the Sea', author: 'Hemingway', progress: 0.60 },
  { id: '6', title: '1984', author: 'George Orwell', progress: 0.35 },
];

@Component
export struct LibraryTabletSurface {
  @ObjectLink vm: LibraryViewModel;

  aboutToAppear(): void {
    IntentBus.getInstance().publish(makeOpenBookshelfIntent()).catch(() => {});
  }

  @Builder
  BookCard(book: ShelfBook) {
    Column({ space: 10 }) {
      Column()
        .width('100%')
        .height(180)
        .backgroundColor(BRAND)
        .borderRadius(8)
        .opacity(0.75)
      Text(book.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(book.author)
        .fontSize(14)
        .fontColor(SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Progress({ value: Math.round(book.progress * 100), total: 100, type: ProgressType.Linear })
        .color(BRAND)
        .backgroundColor('#E0D8C8')
        .style({ strokeWidth: 4 })
        .width('100%')
      Text(`${Math.round(book.progress * 100)}%`)
        .fontSize(12)
        .fontColor(BRAND)
    }
    .padding(16)
    .backgroundColor(BG_CARD)
    .borderRadius(12)
  }

  build() {
    Column() {
      Text('我的书架')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT)
        .padding({ left: 32, right: 32, top: 32, bottom: 16 })
        .width('100%')
      GridRow({ columns: 3, gutter: { x: 20, y: 20 } }) {
        ForEach(SHELF_BOOKS, (book: ShelfBook) => {
          GridCol() {
            this.BookCard(book)
          }
        }, (book: ShelfBook) => book.id)
      }
      .padding({ left: 32, right: 32, bottom: 32 })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
