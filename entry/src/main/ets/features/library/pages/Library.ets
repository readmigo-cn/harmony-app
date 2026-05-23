import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import { RoutePath } from '../../../core/router/RouteConstants';
import { BooksApi } from '../../../api/books/BooksApi';
import { ReadingApi } from '../../../api/reading/ReadingApi';
import { ApiError } from '../../../api/client/HttpClient';
import { Book, BookStatus, SortBy, UserBook } from '../../../model/Book';
import promptAction from '@ohos.promptAction';
// W14-C2：自适应栅格列数 by 当前断点 / 折叠屏展开
import { Breakpoint, FoldStatus, STORAGE_KEY_BREAKPOINT, STORAGE_KEY_FOLD_STATUS } from '../../../core/theme/Breakpoints';
// W14-C3：平板双栏布局
import { LibraryTabletLayout } from '../../multi-platform/pages/tablet/LibraryTabletLayout';

type StatusTab = 'all' | BookStatus;
type ViewMode = 'grid' | 'list';

interface LibraryItem {
  bookId: string;
  book: Book;
  status: BookStatus;
  progress: number;
  lastReadAt?: string;
}

/**
 * Library 页 —— 「书架」入口。
 *
 * 数据流：
 *  1. ReadingApi.listShelf() 拉 UserBook[]，本地按 status / language / cefr / sortBy 过滤
 *  2. 当 books.length === 0 时调 BooksApi.getRecommended() 给空态推荐
 *  3. 长按弹 ActionSheet → ReadingApi.updateShelfStatus / 移除（占位）
 *
 * 注意：这里不直接调 BooksApi.listBooks（那是 Discover 页的事）；
 * Library 仅展示用户已收藏的书。
 */
@Component
export struct Library {
  @State items: LibraryItem[] = [];
  @State recommendedBooks: Book[] = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State loadingMore: boolean = false;
  @State errMsg: string = '';

  @State activeTab: StatusTab = 'all';
  @State filterLanguage: string = '';
  @State filterCefr: string = '';
  @State sortBy: SortBy = 'recent';
  @State viewMode: ViewMode = 'grid';
  @State searchKeyword: string = '';

  @State page: number = 1;
  private readonly pageSize: number = 20;
  @State hasMore: boolean = true;

  // W14-C2：自适应栅格依赖的全局 breakpoint / fold status
  @StorageProp(STORAGE_KEY_BREAKPOINT) currentBp: Breakpoint = Breakpoint.MD;
  @StorageProp(STORAGE_KEY_FOLD_STATUS) foldStatus: FoldStatus = FoldStatus.UNKNOWN;

  private readonly tabs: { key: StatusTab; label: string }[] = [
    { key: 'all', label: '书架' },
    { key: 'want-to-read', label: '想读' },
    { key: 'reading', label: '在读' },
    { key: 'finished', label: '读完' },
  ];
  private readonly languages: { key: string; label: string }[] = [
    { key: '', label: '全部' },
    { key: 'en', label: 'EN' },
    { key: 'zh', label: '中' },
  ];
  private readonly cefrLevels: string[] = ['', 'A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
  private readonly sortOptions: { key: SortBy; label: string }[] = [
    { key: 'recent', label: '最近添加' },
    { key: 'lastRead', label: '最近阅读' },
    { key: 'title', label: '标题' },
  ];

  aboutToAppear(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.errMsg = '';
    try {
      const shelf: UserBook[] = await ReadingApi.listShelf();
      this.items = shelf.map((u): LibraryItem => ({
        bookId: u.bookId,
        book: u.book,
        status: u.status,
        progress: u.progress,
        lastReadAt: u.lastReadAt,
      }));
      if (this.items.length === 0) {
        await this.loadRecommended();
      }
    } catch (err) {
      const e = err as ApiError;
      this.errMsg = e.message ?? 'common_error_unknown';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private async loadRecommended(): Promise<void> {
    try {
      this.recommendedBooks = await BooksApi.getRecommended(8);
    } catch (_e) {
      // 推荐失败静默
    }
  }

  private async loadMore(): Promise<void> {
    if (!this.hasMore || this.loadingMore) return;
    this.loadingMore = true;
    try {
      // Library 只显示书架的书，不分页扩展；保留接口给将来 server 分页 shelf
      this.hasMore = false;
    } finally {
      this.loadingMore = false;
    }
  }

  // ---------- filtering -----------------------------------------------------

  private filteredItems(): LibraryItem[] {
    let list = this.items.slice();
    if (this.activeTab !== 'all') {
      list = list.filter((it) => it.status === this.activeTab);
    }
    if (this.filterLanguage) {
      list = list.filter((it) => it.book.language === this.filterLanguage);
    }
    if (this.filterCefr) {
      list = list.filter((it) => it.book.cefrLevel === this.filterCefr);
    }
    if (this.searchKeyword) {
      const q = this.searchKeyword.toLowerCase();
      list = list.filter((it) =>
        it.book.title.toLowerCase().includes(q)
          || it.book.author.toLowerCase().includes(q),
      );
    }
    list.sort((a, b) => {
      if (this.sortBy === 'title') return a.book.title.localeCompare(b.book.title);
      if (this.sortBy === 'lastRead') {
        const ta = a.lastReadAt ? Date.parse(a.lastReadAt) : 0;
        const tb = b.lastReadAt ? Date.parse(b.lastReadAt) : 0;
        return tb - ta;
      }
      // recent: lastReadAt fallback to status add order (kept)
      return 0;
    });
    return list;
  }

  // ---------- actions -------------------------------------------------------

  private openBook(it: LibraryItem): void {
    const params: Record<string, string> = {
      bookId: it.bookId,
      slug: it.book.slug,
    };
    RouterService.push(RoutePath.READER, params);
  }

  private async markFinished(it: LibraryItem): Promise<void> {
    try {
      await ReadingApi.updateShelfStatus(it.bookId, 'finished');
      it.status = 'finished';
      this.items = this.items.slice();
      promptAction.showToast({ message: '已标记为读完' });
    } catch (_e) {
      promptAction.showToast({ message: '操作失败，请重试' });
    }
  }

  private async removeFromShelf(it: LibraryItem): Promise<void> {
    // Server 暂未提供 DELETE /bookshelf/:id；先本地移除 + 提示
    this.items = this.items.filter((x) => x.bookId !== it.bookId);
    promptAction.showToast({ message: '已从书架移除' });
  }

  private showActionSheet(it: LibraryItem): void {
    promptAction.showActionMenu({
      title: it.book.title,
      buttons: [
        { text: '移除', color: AppColors.danger },
        { text: '标记完成', color: AppColors.textPrimary },
        { text: '分享', color: AppColors.textPrimary },
      ],
    }).then((result) => {
      if (result.index === 0) this.removeFromShelf(it);
      else if (result.index === 1) this.markFinished(it);
      else if (result.index === 2) {
        promptAction.showToast({ message: '分享功能即将上线' });
      }
    }).catch(() => {});
  }

  private goSearch(): void {
    promptAction.showToast({ message: '搜索页即将上线' });
  }

  /**
   * W14-C2：根据当前断点 + 折叠屏状态决定书库 Grid 的列数
   *   - 手机 (XS/SM)：2 列
   *   - 折叠屏内屏 / 平板 (MD)：4 列
   *   - 折叠屏完全展开 / 大平板 (LG/XL)：6 列
   */
  private gridColumnsTemplate(): string {
    const expanded: boolean = this.foldStatus === FoldStatus.EXPAND;
    let cols: number = 2;
    if (this.currentBp === Breakpoint.LG || this.currentBp === Breakpoint.XL || expanded) {
      cols = 6;
    } else if (this.currentBp === Breakpoint.MD) {
      cols = 4;
    }
    return Array(cols).fill('1fr').join(' ');
  }

  /** W14-C2：空态推荐区 Grid 列数（与上面同一规则但少一列） */
  private recommendedColumnsTemplate(): string {
    let cols: number = 4;
    if (this.currentBp === Breakpoint.LG || this.currentBp === Breakpoint.XL) {
      cols = 6;
    } else if (this.currentBp === Breakpoint.MD) {
      cols = 4;
    } else if (this.currentBp === Breakpoint.SM || this.currentBp === Breakpoint.XS) {
      cols = 4;
    }
    return Array(cols).fill('1fr').join(' ');
  }

  // ---------- builders ------------------------------------------------------

  @Builder
  searchBar() {
    Row({ space: AppSpacing.sm }) {
      Image($r('app.media.app_icon'))
        .width(20).height(20)
        .objectFit(ImageFit.Contain)
      Text('搜索书架...')
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textTertiary)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({
      left: AppSpacing.md,
      right: AppSpacing.md,
      top: AppSpacing.sm,
      bottom: AppSpacing.sm,
    })
    .backgroundColor(AppColors.bgSecondary)
    .borderRadius(AppRadius.lg)
    .onClick(() => this.goSearch())
  }

  @Builder
  tabBar() {
    Row({ space: AppSpacing.md }) {
      ForEach(this.tabs, (t: { key: StatusTab; label: string }) => {
        Column() {
          Text(t.label)
            .fontSize(AppFontSize.md)
            .fontWeight(this.activeTab === t.key ? AppFontWeight.bold : AppFontWeight.regular)
            .fontColor(this.activeTab === t.key ? AppColors.brand : AppColors.textSecondary)
          if (this.activeTab === t.key) {
            Divider()
              .width(20).strokeWidth(2)
              .color(AppColors.brand)
              .margin({ top: 4 })
          }
        }
        .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm })
        .onClick(() => { this.activeTab = t.key; })
      })
    }
    .width('100%')
    .padding({ left: AppSpacing.base, right: AppSpacing.base })
  }

  @Builder
  filterChips() {
    Row({ space: AppSpacing.sm }) {
      // Language chips
      ForEach(this.languages, (lang: { key: string; label: string }) => {
        Text(lang.label)
          .fontSize(AppFontSize.xs)
          .fontColor(this.filterLanguage === lang.key ? AppColors.textInverse : AppColors.textSecondary)
          .backgroundColor(this.filterLanguage === lang.key ? AppColors.brand : AppColors.bgSecondary)
          .padding({ left: AppSpacing.sm, right: AppSpacing.sm, top: 4, bottom: 4 })
          .borderRadius(AppRadius.round)
          .onClick(() => { this.filterLanguage = lang.key; })
      })
      Divider().vertical(true).strokeWidth(1).color(AppColors.divider).height(16)
      // CEFR chips
      ForEach(this.cefrLevels, (lvl: string) => {
        Text(lvl || '级')
          .fontSize(AppFontSize.xs)
          .fontColor(this.filterCefr === lvl ? AppColors.textInverse : AppColors.textSecondary)
          .backgroundColor(this.filterCefr === lvl ? AppColors.brand : AppColors.bgSecondary)
          .padding({ left: AppSpacing.sm, right: AppSpacing.sm, top: 4, bottom: 4 })
          .borderRadius(AppRadius.round)
          .onClick(() => { this.filterCefr = lvl; })
      })
    }
    .width('100%')
    .padding({ left: AppSpacing.base, right: AppSpacing.base })
  }

  @Builder
  sortAndViewBar() {
    Row() {
      Row({ space: AppSpacing.xs }) {
        ForEach(this.sortOptions, (opt: { key: SortBy; label: string }) => {
          Text(opt.label)
            .fontSize(AppFontSize.xs)
            .fontColor(this.sortBy === opt.key ? AppColors.brand : AppColors.textTertiary)
            .padding({ left: AppSpacing.xs, right: AppSpacing.xs })
            .onClick(() => { this.sortBy = opt.key; })
        })
      }
      Blank()
      Text(this.viewMode === 'grid' ? '☰ 列表' : '⚏ 网格')
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textSecondary)
        .padding({ left: AppSpacing.sm, right: AppSpacing.sm })
        .onClick(() => { this.viewMode = this.viewMode === 'grid' ? 'list' : 'grid'; })
    }
    .width('100%')
    .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.sm })
  }

  @Builder
  bookCard(it: LibraryItem) {
    Column({ space: AppSpacing.xs }) {
      Stack({ alignContent: Alignment.Bottom }) {
        Image(it.book.coverUrl ?? $r('app.media.app_icon'))
          .width('100%')
          .aspectRatio(0.7)
          .borderRadius(AppRadius.base)
          .alt($r('app.media.app_icon'))
        if (it.status === 'reading' && it.progress > 0) {
          Column() {
            Row()
              .height(3)
              .width(`${Math.min(100, it.progress)}%`)
              .backgroundColor(AppColors.brand)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .backgroundColor('#33000000')
          .borderRadius({ bottomLeft: AppRadius.base, bottomRight: AppRadius.base })
        }
      }
      Text(it.book.title)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(it.book.author)
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (it.book.cefrLevel) {
        Text(it.book.cefrLevel)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.brand)
          .backgroundColor('#E8F5E9')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(AppRadius.sm)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .onClick(() => this.openBook(it))
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => this.showActionSheet(it)),
    )
  }

  @Builder
  bookListRow(it: LibraryItem) {
    Row({ space: AppSpacing.md }) {
      Image(it.book.coverUrl ?? $r('app.media.app_icon'))
        .width(64).height(96)
        .borderRadius(AppRadius.sm)
        .alt($r('app.media.app_icon'))
      Column({ space: AppSpacing.xs }) {
        Text(it.book.title)
          .fontSize(AppFontSize.base)
          .fontWeight(AppFontWeight.medium)
          .fontColor(AppColors.textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(it.book.author)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textTertiary)
        Row({ space: AppSpacing.xs }) {
          if (it.book.cefrLevel) {
            Text(it.book.cefrLevel)
              .fontSize(AppFontSize.xs)
              .fontColor(AppColors.brand)
          }
          if (it.status === 'reading') {
            Text(`${Math.round(it.progress)}%`)
              .fontSize(AppFontSize.xs)
              .fontColor(AppColors.textSecondary)
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(AppSpacing.sm)
    .onClick(() => this.openBook(it))
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => this.showActionSheet(it)),
    )
  }

  @Builder
  loadingSkeleton() {
    Column({ space: AppSpacing.base }) {
      ForEach([1, 2, 3], (i: number) => {
        Row({ space: AppSpacing.md }) {
          Column().width(64).height(96).backgroundColor(AppColors.bgSecondary).borderRadius(AppRadius.sm)
          Column({ space: AppSpacing.xs }) {
            Column().width('60%').height(16).backgroundColor(AppColors.bgSecondary).borderRadius(AppRadius.sm)
            Column().width('40%').height(12).backgroundColor(AppColors.bgSecondary).borderRadius(AppRadius.sm)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(AppSpacing.sm)
      })
    }
    .padding(AppSpacing.base)
  }

  @Builder
  emptyView() {
    Column({ space: AppSpacing.base }) {
      Image($r('app.media.app_icon'))
        .width(96).height(96).opacity(0.4)
      Text('书架空空如也')
        .fontSize(AppFontSize.md)
        .fontColor(AppColors.textSecondary)
      Text('去发现页找一本')
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.brand)
        .padding({
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.sm,
          bottom: AppSpacing.sm,
        })
        .border({ width: 1, color: AppColors.brand, radius: AppRadius.round })
        .onClick(() => RouterService.push(RoutePath.DISCOVER))

      if (this.recommendedBooks.length > 0) {
        Divider().margin({ top: AppSpacing.lg }).color(AppColors.divider)
        Text('为你推荐')
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.medium)
          .fontColor(AppColors.textPrimary)
          .width('100%')
          .padding({ left: AppSpacing.base })
        Grid() {
          ForEach(this.recommendedBooks, (b: Book) => {
            GridItem() {
              Column({ space: AppSpacing.xs }) {
                Image(b.coverUrl ?? $r('app.media.app_icon'))
                  .width('100%').aspectRatio(0.7).borderRadius(AppRadius.base)
                Text(b.title)
                  .fontSize(AppFontSize.xs)
                  .fontColor(AppColors.textPrimary)
                  .maxLines(2)
              }
              .onClick(() => {
                const params: Record<string, string> = { bookId: b.id, slug: b.slug };
                RouterService.push(RoutePath.READER, params);
              })
            }
          })
        }
        // W14-C2：空态推荐 Grid 同样响应断点
        .columnsTemplate(this.recommendedColumnsTemplate())
        .columnsGap(AppSpacing.sm)
        .rowsGap(AppSpacing.sm)
        .padding(AppSpacing.base)
      }
    }
    .width('100%')
    .padding({ top: AppSpacing.xl })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  errorView() {
    Column({ space: AppSpacing.base }) {
      Text('加载失败')
        .fontSize(AppFontSize.md)
        .fontColor(AppColors.danger)
      Text(this.errMsg)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textTertiary)
        .maxLines(3)
      Button('重试')
        .onClick(() => this.refresh())
        .backgroundColor(AppColors.brand)
        .fontColor(AppColors.textInverse)
        .borderRadius(AppRadius.base)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(AppSpacing.lg)
  }

  @Builder
  contentArea() {
    if (this.loading) {
      this.loadingSkeleton()
    } else if (this.errMsg) {
      this.errorView()
    } else {
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column() {
            if (this.filteredItems().length === 0) {
              this.emptyView()
            } else if (this.viewMode === 'grid') {
              Grid() {
                LazyForEach(
                  {
                    totalCount: () => this.filteredItems().length,
                    getData: (i: number) => this.filteredItems()[i],
                    registerDataChangeListener: () => {},
                    unregisterDataChangeListener: () => {},
                  },
                  (it: LibraryItem) => {
                    GridItem() { this.bookCard(it) }
                  },
                  (it: LibraryItem) => it.bookId,
                )
              }
              // W14-C2：列数随断点切换（mobile=2, tablet/MD=4, desktop/LG/折叠展开=6）
              .columnsTemplate(this.gridColumnsTemplate())
              .columnsGap(AppSpacing.sm)
              .rowsGap(AppSpacing.base)
              .padding(AppSpacing.base)
            } else {
              List({ space: AppSpacing.xs }) {
                LazyForEach(
                  {
                    totalCount: () => this.filteredItems().length,
                    getData: (i: number) => this.filteredItems()[i],
                    registerDataChangeListener: () => {},
                    unregisterDataChangeListener: () => {},
                  },
                  (it: LibraryItem) => {
                    ListItem() { this.bookListRow(it) }
                  },
                  (it: LibraryItem) => it.bookId,
                )
              }
              .padding({ left: AppSpacing.base, right: AppSpacing.base })
              .divider({ strokeWidth: 1, color: AppColors.divider })
            }
            if (this.loadingMore) {
              Row() {
                LoadingProgress().width(20).height(20).color(AppColors.brand)
              }
              .width('100%').justifyContent(FlexAlign.Center).padding(AppSpacing.base)
            }
          }
          .width('100%')
        }
        .width('100%').height('100%')
        .scrollBar(BarState.Off)
        .onReachEnd(() => this.loadMore())
      }
      .onRefreshing(() => { this.refresh(); })
    }
  }

  /**
   * W14-C3：平板（lg / xl）或折叠屏 EXPAND 状态走双栏布局；其余走手机版。
   */
  private isTabletLayout(): boolean {
    if (this.currentBp === Breakpoint.LG || this.currentBp === Breakpoint.XL) return true;
    return this.foldStatus === FoldStatus.EXPAND;
  }

  @Builder
  mobileBuilder() {
    Column() {
      // Header
      Row({ space: AppSpacing.sm }) {
        Text('我的书架')
          .fontSize(AppFontSize.xl)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.sm,
        bottom: AppSpacing.sm,
      })

      // Search bar
      Column() {
        this.searchBar()
      }
      .padding({ left: AppSpacing.base, right: AppSpacing.base })

      // Tabs
      this.tabBar()
      Divider().color(AppColors.divider)

      // Filters + sort + view toggle
      Scroll() { this.filterChips() }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      this.sortAndViewBar()

      // Content
      Stack() { this.contentArea() }
        .layoutWeight(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }

  build() {
    if (this.isTabletLayout()) {
      LibraryTabletLayout()
    } else {
      this.mobileBuilder()
    }
  }
}
