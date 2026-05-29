// L4 Feature - Discover - TabletSurface
// 2-column grid layout for tablet/foldable.

import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeBrowseDiscoverIntent } from '../intent/DiscoverIntents';

const TABS = ['精选', '新书', '畅销', 'CEFR-B1', 'CEFR-B2'];
const BRAND = '#E76F1A';
const TEXT = '#1A1A1A';
const SECONDARY = '#666666';
const BG = '#FFFFFF';
const BG_SECONDARY = '#F8F8F8';

interface MockBook {
  id: string;
  title: string;
  author: string;
  level: string;
}

const MOCK_BOOKS: MockBook[] = [
  { id: '1', title: 'Pride and Prejudice', author: 'Jane Austen', level: 'B2' },
  { id: '2', title: 'The Great Gatsby', author: 'F. Scott Fitzgerald', level: 'B2' },
  { id: '3', title: 'Animal Farm', author: 'George Orwell', level: 'B1' },
  { id: '4', title: 'The Old Man and the Sea', author: 'Ernest Hemingway', level: 'B1' },
  { id: '5', title: 'Brave New World', author: 'Aldous Huxley', level: 'C1' },
  { id: '6', title: 'Of Mice and Men', author: 'John Steinbeck', level: 'B1' },
];

@Component
export struct DiscoverTabletSurface {
  @ObjectLink vm: DiscoverViewModel;
  @State activeTab: string = '精选';

  private selectTab(tab: string): void {
    this.activeTab = tab;
    IntentBus.getInstance().publish(makeBrowseDiscoverIntent(tab)).catch(() => {});
  }

  @Builder
  TabBar() {
    Row({ space: 8 }) {
      ForEach(TABS, (tab: string) => {
        Text(tab)
          .fontSize(18)
          .fontColor(this.activeTab === tab ? '#FFFFFF' : TEXT)
          .padding({ left: 20, right: 20, top: 10, bottom: 10 })
          .backgroundColor(this.activeTab === tab ? BRAND : BG_SECONDARY)
          .borderRadius(20)
          .onClick(() => this.selectTab(tab))
      }, (tab: string) => tab)
    }
    .padding({ left: 32, right: 32, top: 16, bottom: 8 })
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
  }

  @Builder
  BookCard(book: MockBook) {
    Column({ space: 8 }) {
      Column()
        .width(140)
        .height(196)
        .backgroundColor(BRAND)
        .borderRadius(8)
        .opacity(0.8)
      Text(book.title)
        .fontSize(16)
        .fontColor(TEXT)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(140)
      Text(book.author)
        .fontSize(13)
        .fontColor(SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(140)
      Text(book.level)
        .fontSize(12)
        .fontColor(BRAND)
    }
    .alignItems(HorizontalAlign.Start)
    .padding(8)
  }

  build() {
    Column() {
      Text('发现好书')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT)
        .padding({ left: 32, right: 32, top: 32, bottom: 8 })
        .width('100%')
      this.TabBar()
      GridRow({ columns: 2, gutter: { x: 24, y: 24 } }) {
        ForEach(MOCK_BOOKS, (book: MockBook) => {
          GridCol() {
            this.BookCard(book)
          }
        }, (book: MockBook) => book.id)
      }
      .padding({ left: 32, right: 32, top: 16, bottom: 32 })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
