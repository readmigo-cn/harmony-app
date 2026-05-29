// L4 Feature - Discover - TvSurface
// 5x3 focus-traversable grid, big text ≥48sp.

import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeBrowseDiscoverIntent } from '../intent/DiscoverIntents';

const BG = '#0F1018';
const CARD_BG = '#1A1D28';
const ACCENT = '#E76F1A';
const TEXT_PRIMARY = '#F5F5F7';
const TEXT_SECONDARY = '#9AA3B2';
const FOCUS_BORDER = ACCENT;

interface TvBook { id: string; title: string; author: string; level: string; }

const TV_BOOKS: TvBook[] = [
  { id: '1', title: 'Pride and Prejudice', author: 'Jane Austen', level: 'B2' },
  { id: '2', title: 'The Great Gatsby', author: 'F. Scott Fitzgerald', level: 'B2' },
  { id: '3', title: 'Animal Farm', author: 'George Orwell', level: 'B1' },
  { id: '4', title: 'The Old Man and the Sea', author: 'Hemingway', level: 'B1' },
  { id: '5', title: 'Brave New World', author: 'Aldous Huxley', level: 'C1' },
  { id: '6', title: 'Of Mice and Men', author: 'John Steinbeck', level: 'B1' },
  { id: '7', title: '1984', author: 'George Orwell', level: 'B2' },
  { id: '8', title: 'The Catcher in the Rye', author: 'J.D. Salinger', level: 'B2' },
  { id: '9', title: 'To Kill a Mockingbird', author: 'Harper Lee', level: 'B1' },
  { id: '10', title: 'Lord of the Flies', author: 'William Golding', level: 'B2' },
  { id: '11', title: 'Jane Eyre', author: 'Charlotte Brontë', level: 'C1' },
  { id: '12', title: 'Wuthering Heights', author: 'Emily Brontë', level: 'C1' },
  { id: '13', title: 'Great Expectations', author: 'Charles Dickens', level: 'C1' },
  { id: '14', title: 'Frankenstein', author: 'Mary Shelley', level: 'B2' },
  { id: '15', title: 'Moby-Dick', author: 'Herman Melville', level: 'C2' },
];

@Component
export struct DiscoverTvSurface {
  @ObjectLink vm: DiscoverViewModel;
  @State focusedId: string = '';

  private selectBook(book: TvBook): void {
    IntentBus.getInstance().publish(makeBrowseDiscoverIntent(book.id)).catch(() => {});
  }

  @Builder
  BookCard(book: TvBook) {
    Column({ space: 12 }) {
      Column()
        .width('100%')
        .height(200)
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
      Text(book.level)
        .fontSize(22)
        .fontColor(ACCENT)
    }
    .padding(20)
    .backgroundColor(this.focusedId === book.id ? '#252836' : CARD_BG)
    .borderRadius(12)
    .border({
      width: this.focusedId === book.id ? 3 : 0,
      color: FOCUS_BORDER,
      radius: 12,
    })
    .scale({ x: this.focusedId === book.id ? 1.04 : 1.0, y: this.focusedId === book.id ? 1.04 : 1.0 })
    .focusable(true)
    .onFocus(() => { this.focusedId = book.id; })
    .onBlur(() => { if (this.focusedId === book.id) this.focusedId = ''; })
    .onClick(() => this.selectBook(book))
  }

  build() {
    Column({ space: 0 }) {
      Text('发现好书')
        .fontSize(56)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .padding({ left: 80, right: 80, top: 60, bottom: 32 })
        .width('100%')

      GridRow({ columns: 5, gutter: { x: 32, y: 32 } }) {
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
