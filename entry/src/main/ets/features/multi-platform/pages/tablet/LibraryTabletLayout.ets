/**
 * LibraryTabletLayout.ets — W14-C3 平板专属书架双栏布局
 *
 * 布局：
 *   - 左侧 (40%)：书架列表（紧凑 list 视图，密集 spacing）
 *   - 右侧 (60%)：选中书的详情（封面大图 + 简介 + 章节 + Action）
 *   - 未选中时右侧显示 EmptyState「请选择一本书」
 *   - 双栏滚动独立，复用现有 BooksApi / ReadingApi / Library 状态管理
 *
 * 与 mobile Library 的关系：
 *   - 共用 BooksApi.getRecommended / ReadingApi.listShelf / updateShelfStatus
 *   - 状态层：直接复用 BooksApi 缓存；不引入额外 store
 *   - 进入 Reader 仍由 RouterService.push(READER) 触发，与手机一致
 */

import { AppColors } from '../../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../../core/theme/AppSpacing';
import { RouterAdapter } from '../../../../core/router/RouterAdapter';
import { BooksApi } from '../../../../api/books/BooksApi';
import { ReadingApi } from '../../../../api/reading/ReadingApi';
import { Book, BookDetail, BookStatus, UserBook } from '../../../../model/Book';
import { Chapter } from '../../../../model/Chapter';
import { ApiError } from '../../../../api/client/HttpClient';
import promptAction from '@ohos.promptAction';

interface LibraryItem {
  bookId: string;
  book: Book;
  status: BookStatus;
  progress: number;
  lastReadAt?: string;
}

type StatusTab = 'all' | BookStatus;

@Component
export struct LibraryTabletLayout {
  // ---- 列表态 -----------------------------------------------------------
  @State items: LibraryItem[] = [];
  @State loading: boolean = false;
  @State errMsg: string = '';
  @State activeTab: StatusTab = 'all';

  // ---- 选中态：右侧详情 -------------------------------------------------
  @State selectedBookId: string = '';
  @State detail: BookDetail | null = null;
  @State chapters: Chapter[] = [];
  @State detailLoading: boolean = false;
  @State detailErrMsg: string = '';

  private readonly tabs: { key: StatusTab; label: string }[] = [
    { key: 'all', label: '全部' },
    { key: 'reading', label: '在读' },
    { key: 'want-to-read', label: '想读' },
    { key: 'finished', label: '读完' },
  ];

  aboutToAppear(): void {
    this.refresh();
  }

  // ---- 数据加载 ---------------------------------------------------------

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
      // 自动选中第一本（如果未选）
      if (!this.selectedBookId && this.items.length > 0) {
        await this.selectBook(this.items[0]);
      }
    } catch (err) {
      this.errMsg = (err as ApiError).message ?? '加载失败';
    } finally {
      this.loading = false;
    }
  }

  private async selectBook(it: LibraryItem): Promise<void> {
    if (this.selectedBookId === it.bookId) return;
    this.selectedBookId = it.bookId;
    this.detail = null;
    this.chapters = [];
    this.detailLoading = true;
    this.detailErrMsg = '';
    try {
      const slug = it.book.slug || it.bookId;
      // 并行：详情 + 章节列表
      const tasks: [Promise<BookDetail>, Promise<Chapter[]>] = [
        BooksApi.getBookBySlug(slug),
        BooksApi.getChapters(slug),
      ];
      const [d, chs] = await Promise.all(tasks);
      this.detail = d;
      this.chapters = chs;
    } catch (err) {
      this.detailErrMsg = (err as ApiError).message ?? '详情加载失败';
    } finally {
      this.detailLoading = false;
    }
  }

  private filteredItems(): LibraryItem[] {
    if (this.activeTab === 'all') return this.items;
    return this.items.filter((it) => it.status === this.activeTab);
  }

  private openCurrentInReader(): void {
    if (!this.selectedBookId || !this.detail) return;
    RouterAdapter.pushReader({ bookId: this.selectedBookId });
  }

  private async markFinished(): Promise<void> {
    if (!this.selectedBookId) return;
    try {
      await ReadingApi.updateShelfStatus(this.selectedBookId, 'finished');
      this.items = this.items.map((it) =>
        it.bookId === this.selectedBookId ? { ...it, status: 'finished' } : it,
      );
      promptAction.showToast({ message: '已标记为读完' });
    } catch (_e) {
      promptAction.showToast({ message: '操作失败' });
    }
  }

  // ---- builders --------------------------------------------------------

  @Builder
  tabBar() {
    Row({ space: AppSpacing.md }) {
      ForEach(this.tabs, (t: { key: StatusTab; label: string }) => {
        Text(t.label)
          .fontSize(AppFontSize.sm)
          .fontWeight(this.activeTab === t.key ? AppFontWeight.bold : AppFontWeight.regular)
          .fontColor(this.activeTab === t.key ? AppColors.brand : AppColors.textSecondary)
          .padding({ top: AppSpacing.xs, bottom: AppSpacing.xs })
          .onClick(() => { this.activeTab = t.key; })
      })
    }
    .width('100%')
    .padding({ left: AppSpacing.base, right: AppSpacing.base })
  }

  @Builder
  listRow(it: LibraryItem) {
    Row({ space: AppSpacing.sm }) {
      Image(it.book.coverUrl ?? $r('app.media.app_icon'))
        .width(48).height(72)
        .borderRadius(AppRadius.sm)
        .alt($r('app.media.app_icon'))
      Column({ space: 2 }) {
        Text(it.book.title)
          .fontSize(AppFontSize.sm)
          .fontWeight(AppFontWeight.medium)
          .fontColor(AppColors.textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(it.book.author)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (it.status === 'reading' && it.progress > 0) {
          Text(`${Math.round(it.progress)}%`)
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.brand)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: AppSpacing.sm, right: AppSpacing.sm, top: AppSpacing.xs, bottom: AppSpacing.xs })
    .backgroundColor(this.selectedBookId === it.bookId ? AppColors.bgSecondary : AppColors.bgPrimary)
    .borderRadius(AppRadius.sm)
    .onClick(() => this.selectBook(it))
  }

  @Builder
  leftPane() {
    Column() {
      // 标题 + tabs
      Text('我的书架')
        .fontSize(AppFontSize.lg)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .padding({ left: AppSpacing.base, top: AppSpacing.sm, bottom: AppSpacing.xs })
        .width('100%')
      this.tabBar()
      Divider().color(AppColors.divider).margin({ top: AppSpacing.xs })

      if (this.loading) {
        Column() {
          LoadingProgress().width(28).height(28).color(AppColors.brand)
        }
        .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      } else if (this.errMsg) {
        Column({ space: AppSpacing.sm }) {
          Text('加载失败').fontSize(AppFontSize.sm).fontColor(AppColors.danger)
          Button('重试').onClick(() => this.refresh())
        }
        .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      } else if (this.filteredItems().length === 0) {
        Column() {
          Text('书架为空')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textTertiary)
        }
        .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      } else {
        // 紧凑列表（密集 spacing）
        List({ space: AppSpacing.xs }) {
          ForEach(this.filteredItems(), (it: LibraryItem) => {
            ListItem() { this.listRow(it) }
          }, (it: LibraryItem) => it.bookId)
        }
        .layoutWeight(1)
        .padding({ left: AppSpacing.sm, right: AppSpacing.sm, top: AppSpacing.xs })
        .scrollBar(BarState.Auto)
      }
    }
    .width('40%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }

  @Builder
  rightPaneEmpty() {
    Column({ space: AppSpacing.base }) {
      Text('📖')
        .fontSize(64)
        .opacity(0.5)
      Text('请选择一本书')
        .fontSize(AppFontSize.md)
        .fontColor(AppColors.textSecondary)
      Text('从左侧书架挑选一本，开始阅读')
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textTertiary)
    }
    .width('100%').height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  rightPaneDetail() {
    Scroll() {
      Column({ space: AppSpacing.md }) {
        // 顶部：封面 + 元信息
        Row({ space: AppSpacing.lg }) {
          Image(this.detail?.coverUrl ?? $r('app.media.app_icon'))
            .width(160).height(232)
            .borderRadius(AppRadius.base)
            .alt($r('app.media.app_icon'))
          Column({ space: AppSpacing.sm }) {
            Text(this.detail?.title ?? '')
              .fontSize(AppFontSize.xl)
              .fontWeight(AppFontWeight.bold)
              .fontColor(AppColors.textPrimary)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.detail?.author ?? '')
              .fontSize(AppFontSize.md)
              .fontColor(AppColors.textSecondary)
            if (this.detail?.cefrLevel) {
              Text(this.detail.cefrLevel)
                .fontSize(AppFontSize.xs)
                .fontColor(AppColors.brand)
                .backgroundColor('#E8F5E9')
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .borderRadius(AppRadius.sm)
            }
            if (this.detail?.wordCount) {
              Text(`约 ${Math.round((this.detail.wordCount ?? 0) / 1000)} 千词`)
                .fontSize(AppFontSize.xs)
                .fontColor(AppColors.textTertiary)
            }
            // Action 按钮
            Row({ space: AppSpacing.sm }) {
              Button('开始阅读')
                .backgroundColor(AppColors.brand)
                .fontColor(AppColors.textInverse)
                .borderRadius(AppRadius.base)
                .height(40)
                .onClick(() => this.openCurrentInReader())
              Button('标为完成')
                .backgroundColor(AppColors.bgSecondary)
                .fontColor(AppColors.textPrimary)
                .borderRadius(AppRadius.base)
                .height(40)
                .onClick(() => this.markFinished())
            }
            .margin({ top: AppSpacing.sm })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Divider().color(AppColors.divider)

        // 简介
        if (this.detail?.description) {
          Column({ space: AppSpacing.sm }) {
            Text('简介')
              .fontSize(AppFontSize.md)
              .fontWeight(AppFontWeight.medium)
              .fontColor(AppColors.textPrimary)
            Text(this.detail.description ?? '')
              .fontSize(AppFontSize.sm)
              .fontColor(AppColors.textSecondary)
              .lineHeight(22)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }

        // 章节
        Column({ space: AppSpacing.sm }) {
          Text(`章节 (${this.chapters.length})`)
            .fontSize(AppFontSize.md)
            .fontWeight(AppFontWeight.medium)
            .fontColor(AppColors.textPrimary)
          if (this.chapters.length === 0) {
            Text('暂无章节')
              .fontSize(AppFontSize.sm)
              .fontColor(AppColors.textTertiary)
          } else {
            ForEach(this.chapters.slice(0, 30), (ch: Chapter) => {
              Row() {
                Text(`${ch.index + 1}. ${ch.title}`)
                  .fontSize(AppFontSize.sm)
                  .fontColor(AppColors.textPrimary)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ top: AppSpacing.xs, bottom: AppSpacing.xs })
              .onClick(() => {
                RouterAdapter.pushReader({
                  bookId: this.selectedBookId,
                  chapterId: ch.id,
                });
              })
            })
            if (this.chapters.length > 30) {
              Text(`...还有 ${this.chapters.length - 30} 章`)
                .fontSize(AppFontSize.xs)
                .fontColor(AppColors.textTertiary)
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .padding(AppSpacing.lg)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Auto)
  }

  @Builder
  rightPane() {
    Column() {
      if (!this.selectedBookId) {
        this.rightPaneEmpty()
      } else if (this.detailLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(AppColors.brand)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else if (this.detailErrMsg) {
        Column({ space: AppSpacing.sm }) {
          Text('详情加载失败')
            .fontSize(AppFontSize.md)
            .fontColor(AppColors.danger)
          Text(this.detailErrMsg)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textTertiary)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else if (this.detail) {
        this.rightPaneDetail()
      }
    }
    .width('60%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }

  build() {
    Row() {
      this.leftPane()
      // 中央分隔线
      Divider()
        .vertical(true)
        .strokeWidth(1)
        .color(AppColors.divider)
        .height('100%')
      this.rightPane()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }
}
