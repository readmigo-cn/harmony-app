// L4 Feature - Library - CarSurface
// 5 most recent books, big titles, no scrolling.

import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeOpenBookshelfIntent } from '../intent/LibraryIntents';

const BG = '#000000';
const ACCENT = '#7C3AED';
const TEXT_PRIMARY = '#FFFFFF';
const TEXT_DIM = '#9AA3B2';

interface CarBook { id: string; title: string; author: string; }

const CAR_BOOKS: CarBook[] = [
  { id: '1', title: 'Pride and Prejudice', author: 'Jane Austen' },
  { id: '2', title: 'The Great Gatsby', author: 'F. Scott Fitzgerald' },
  { id: '3', title: 'Animal Farm', author: 'George Orwell' },
  { id: '4', title: 'The Old Man and the Sea', author: 'Ernest Hemingway' },
  { id: '5', title: 'Brave New World', author: 'Aldous Huxley' },
];

@Component
export struct LibraryCarSurface {
  @ObjectLink vm: LibraryViewModel;
  @StorageLink('car_lock_active') lockActive: boolean = false;

  private open(): void {
    if (this.lockActive) return;
    IntentBus.getInstance().publish(makeOpenBookshelfIntent()).catch(() => {});
  }

  @Builder
  BookRow(book: CarBook) {
    Row({ space: 24 }) {
      Column()
        .width(60)
        .height(80)
        .backgroundColor(ACCENT)
        .borderRadius(6)
        .opacity(0.8)
      Column({ space: 6 }) {
        Text(book.title)
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(book.author)
          .fontSize(24)
          .fontColor(TEXT_DIM)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('88%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => this.open())
  }

  build() {
    Stack() {
      Column({ space: 8 }) {
        Text('我的书架')
          .fontSize(48)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .padding({ left: 80, top: 48, bottom: 16 })
          .width('100%')
        Column({ space: 0 }) {
          ForEach(CAR_BOOKS, (book: CarBook) => {
            this.BookRow(book)
          }, (book: CarBook) => book.id)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)

      if (this.lockActive) {
        Column() {
          Text('行驶中，请使用语音操控')
            .fontSize(44)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('rgba(0,0,0,0.55)')
        .onClick(() => {})
      }
    }
    .width('100%')
    .height('100%')
  }
}
