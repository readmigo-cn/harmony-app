/**
 * DiscoverTabletLayout.ets — W14-C3 平板专属发现双栏布局
 *
 * 布局：
 *   - 顶部：搜索 bar 横跨两栏
 *   - 左侧 (30%)：分类导航（推荐 / 分级 / 主题 / 作者 / 系列）
 *   - 右侧 (70%)：选中分类的网格（AdaptiveGrid，4-6 列自适应）
 *
 * 说明：
 *   - 分类暂用静态列表 + BooksApi.listBooks(category=) 过滤
 *   - 与 mobile Discover 共用 BooksApi 缓存
 */

import { AppColors } from '../../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../../core/theme/AppSpacing';
import { RouterAdapter } from '../../../../core/router/RouterAdapter';
import { BooksApi } from '../../../../api/books/BooksApi';
import { Book } from '../../../../model/Book';
import { ApiError } from '../../../../api/client/HttpClient';
import { AdaptiveGrid } from '../../../../ui/responsive/AdaptiveGrid';

interface CategoryItem {
  key: string;
  label: string;
  /** 'recommend' 走 BooksApi.getRecommended；其它走 listBooks(category=) */
  mode: 'recommend' | 'category' | 'cefr';
  /** mode='cefr' 时透传给 listBooks(cefrLevel=) */
  cefr?: string;
}

@Component
export struct DiscoverTabletLayout {
  @State activeCategory: string = 'recommend';
  @State books: Book[] = [];
  @State loading: boolean = false;
  @State errMsg: string = '';
  @State searchKeyword: string = '';

  private readonly categories: CategoryItem[] = [
    { key: 'recommend', label: '推荐', mode: 'recommend' },
    { key: 'a1-a2', label: 'A1-A2 入门', mode: 'cefr', cefr: 'A1' },
    { key: 'b1-b2', label: 'B1-B2 进阶', mode: 'cefr', cefr: 'B1' },
    { key: 'c1', label: 'C1 高级', mode: 'cefr', cefr: 'C1' },
    { key: 'novel', label: '小说', mode: 'category' },
    { key: 'history', label: '历史', mode: 'category' },
    { key: 'science', label: '科学', mode: 'category' },
    { key: 'philosophy', label: '哲学', mode: 'category' },
    { key: 'biography', label: '传记', mode: 'category' },
  ];

  aboutToAppear(): void {
    this.loadCategory(this.activeCategory);
  }

  private async loadCategory(key: string): Promise<void> {
    this.activeCategory = key;
    this.loading = true;
    this.errMsg = '';
    try {
      const cat = this.categories.find((c) => c.key === key);
      if (!cat) {
        this.books = [];
        return;
      }
      if (cat.mode === 'recommend') {
        this.books = await BooksApi.getRecommended(24);
      } else if (cat.mode === 'cefr' && cat.cefr) {
        const resp = await BooksApi.listBooks({ page: 1, limit: 24, cefrLevel: cat.cefr });
        this.books = resp.items;
      } else {
        const resp = await BooksApi.listBooks({ page: 1, limit: 24, category: cat.key });
        this.books = resp.items;
      }
    } catch (err) {
      this.errMsg = (err as ApiError).message ?? '加载失败';
      this.books = [];
    } finally {
      this.loading = false;
    }
  }

  private async doSearch(): Promise<void> {
    const q = this.searchKeyword.trim();
    if (!q) {
      this.loadCategory(this.activeCategory);
      return;
    }
    this.loading = true;
    this.errMsg = '';
    try {
      this.books = await BooksApi.searchBooks(q, 24);
    } catch (err) {
      this.errMsg = (err as ApiError).message ?? '搜索失败';
      this.books = [];
    } finally {
      this.loading = false;
    }
  }

  // ---- builders --------------------------------------------------------

  @Builder
  searchHeader() {
    Row({ space: AppSpacing.sm }) {
      Text('🔍')
        .fontSize(AppFontSize.md)
        .fontColor(AppColors.textTertiary)
      TextInput({ placeholder: '搜索书名、作者...', text: this.searchKeyword })
        .layoutWeight(1)
        .height(40)
        .fontSize(AppFontSize.sm)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.lg)
        .onChange((v: string) => { this.searchKeyword = v; })
        .onSubmit(() => this.doSearch())
      Button('搜索')
        .height(40)
        .fontSize(AppFontSize.sm)
        .backgroundColor(AppColors.brand)
        .fontColor(AppColors.textInverse)
        .borderRadius(AppRadius.base)
        .onClick(() => this.doSearch())
    }
    .width('100%')
    .padding({
      left: AppSpacing.lg, right: AppSpacing.lg,
      top: AppSpacing.sm, bottom: AppSpacing.sm,
    })
    .backgroundColor(AppColors.bgPrimary)
  }

  @Builder
  categoryItem(c: CategoryItem) {
    Row() {
      Text(c.label)
        .fontSize(AppFontSize.sm)
        .fontWeight(this.activeCategory === c.key ? AppFontWeight.bold : AppFontWeight.regular)
        .fontColor(this.activeCategory === c.key ? AppColors.brand : AppColors.textPrimary)
        .layoutWeight(1)
      if (this.activeCategory === c.key) {
        Text('▶').fontSize(AppFontSize.xs).fontColor(AppColors.brand)
      }
    }
    .width('100%')
    .padding({
      left: AppSpacing.base, right: AppSpacing.base,
      top: AppSpacing.sm, bottom: AppSpacing.sm,
    })
    .backgroundColor(this.activeCategory === c.key ? AppColors.bgSecondary : AppColors.bgPrimary)
    .borderRadius(AppRadius.sm)
    .onClick(() => this.loadCategory(c.key))
  }

  @Builder
  leftPane() {
    Column({ space: AppSpacing.xs }) {
      Text('分类')
        .fontSize(AppFontSize.md)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .padding({ left: AppSpacing.base, top: AppSpacing.sm, bottom: AppSpacing.xs })
        .width('100%')
      Scroll() {
        Column({ space: AppSpacing.xs }) {
          ForEach(this.categories, (c: CategoryItem) => {
            this.categoryItem(c)
          }, (c: CategoryItem) => c.key)
        }
        .width('100%')
        .padding({ left: AppSpacing.sm, right: AppSpacing.sm })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('30%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }

  @Builder
  bookCard(b: Book, _index: number) {
    Column({ space: AppSpacing.xs }) {
      Image(b.coverUrl ?? $r('app.media.app_icon'))
        .width('100%')
        .aspectRatio(0.7)
        .borderRadius(AppRadius.base)
        .alt($r('app.media.app_icon'))
      Text(b.title)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(b.author)
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (b.cefrLevel) {
        Text(b.cefrLevel)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.brand)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.xs)
    .onClick(() => RouterAdapter.pushReader({ bookId: b.id }))
  }

  @Builder
  rightPane() {
    Column() {
      if (this.loading) {
        Column() {
          LoadingProgress().width(40).height(40).color(AppColors.brand)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.errMsg) {
        Column({ space: AppSpacing.sm }) {
          Text('加载失败').fontSize(AppFontSize.md).fontColor(AppColors.danger)
          Text(this.errMsg).fontSize(AppFontSize.sm).fontColor(AppColors.textTertiary)
          Button('重试').onClick(() => this.loadCategory(this.activeCategory))
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.books.length === 0) {
        Column() {
          Text('暂无书籍')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textTertiary)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            // AdaptiveGrid：lg 12 列 / span 2 → 一行 6 个；md 8 / span 2 → 4 个
            AdaptiveGrid({
              items: this.books,
              columns: { md: 8, lg: 12, xl: 12 },
              childSpan: { md: 2, lg: 2, xl: 2 },
              itemBuilder: (b: Book, i: number) => {
                this.bookCard(b, i)
              },
              keyExtractor: (b: Book) => b.id,
            })
          }
          .width('100%')
          .padding(AppSpacing.lg)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('70%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }

  build() {
    Column() {
      // 顶部搜索栏（横跨两栏）
      this.searchHeader()
      Divider().color(AppColors.divider)

      // 双栏主体
      Row() {
        this.leftPane()
        Divider().vertical(true).strokeWidth(1).color(AppColors.divider).height('100%')
        this.rightPane()
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }
}
