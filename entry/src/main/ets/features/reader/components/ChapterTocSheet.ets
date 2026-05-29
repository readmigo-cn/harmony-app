/**
 * ChapterTocSheet.ets — W7-C5 章节目录底部弹窗
 *
 * 基于 W6 AppSheet，snap [0.4, 0.8]。
 * Body：搜索框 + 章节列表 + 状态指示。
 *   ✓  finished
 *   ◐  reading（当前章 / 进度中）
 *   ○  unread
 * 当前章高亮品牌色背景。
 * 状态来源：ReadingStore.getChapterStatuses(bookId)（client-side 维护，
 * 来自 setChapterStatus 写入 + ProgressSync.pull 后的批量回灌）。
 */

import {
  TextColors,
  BgColors,
  AccentColors,
  BorderColors,
  SurfaceColors,
  useColor,
} from '../../../core/theme/AppColors';
import {
  FontFamily,
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius } from '../../../core/theme/AppSpacing';
import { AppSheet } from '../../../ui/primitives/Modal';
import { AppSkeleton } from '../../../ui/primitives/Loading';
import { AppEmptyState } from '../../../ui/primitives/EmptyState';
import { Chapter } from '../../../model/Chapter';
import { BooksApi } from '../../../api/books/BooksApi';
import { ChapterStatus, ReadingStore } from '../../../store/ReadingStore';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeJumpToChapterIntent } from '../intent/ReaderIntents';

/** 视图模型：在 Chapter 基础上挂状态。 */
interface ChapterRow {
  chapter: Chapter;
  status: ChapterStatus;
}

@Component
export struct ChapterTocSheet {
  /** 是否显示（双向绑定） */
  @Link @Watch('onVisibleChange') visible: boolean;
  /** 书 slug，用于拉章节列表 */
  @Prop bookSlug: string;
  /** 书 id，用于读章节状态表 */
  @Prop bookId: string;
  /** 书标题（顶部副标题） */
  @Prop bookTitle: string;
  /** 当前阅读章节 index */
  @Prop currentChapterIndex: number;
  /** 是否暗色模式 */
  @Prop isDark: boolean;
  /** 选中章节回调 */
  onChapterSelect?: (index: number) => void;

  @State private chapters: Chapter[] = [];
  @State private statusMap: Record<string, ChapterStatus> = {};
  @State private loading: boolean = false;
  @State private errMsg: string = '';
  @State private keyword: string = '';

  aboutToAppear(): void {
    this.refresh();
  }

  /** visible 变化时如果重新打开，重新拉数据（章节列表通常不变，但状态会变）。 */
  onVisibleChange(): void {
    if (this.visible) {
      this.refresh();
    }
  }

  private async refresh(): Promise<void> {
    this.errMsg = '';
    this.statusMap = ReadingStore.getChapterStatuses(this.bookId);
    if (this.chapters.length > 0) {
      // 仅刷新状态
      return;
    }
    if (!this.bookSlug) return;
    this.loading = true;
    try {
      const list = await BooksApi.getChapters(this.bookSlug);
      this.chapters = list;
    } catch (e) {
      this.errMsg = (e as Error).message ?? '加载失败';
    } finally {
      this.loading = false;
    }
  }

  private get filtered(): ChapterRow[] {
    const kw = this.keyword.trim().toLowerCase();
    const rows: ChapterRow[] = [];
    for (const ch of this.chapters) {
      if (kw.length > 0 && !(ch.title ?? '').toLowerCase().includes(kw)) continue;
      const key = ch.index.toString();
      const status = this.statusMap[key] ?? (ch.index === this.currentChapterIndex ? 'reading' : 'unread');
      rows.push({ chapter: ch, status });
    }
    return rows;
  }

  private statusGlyph(status: ChapterStatus): string {
    if (status === 'finished') return '✓';
    if (status === 'reading') return '◐';
    return '○';
  }

  private statusColor(status: ChapterStatus): ResourceColor {
    if (status === 'finished') return useColor(AccentColors.primary, this.isDark);
    if (status === 'reading') return useColor(AccentColors.primary, this.isDark);
    return useColor(TextColors.tertiary, this.isDark);
  }

  private handleTap(index: number): void {
    this.visible = false;
    const ch = this.chapters[index];
    if (ch) {
      IntentBus.getInstance().publish(makeJumpToChapterIntent(ch.id ?? String(index)));
    }
    this.onChapterSelect?.(index);
  }

  @Builder
  searchBar() {
    Row({ space: Spacing.s2 }) {
      Text('🔎')
        .fontSize(FontSizeToken.callout)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
      TextInput({ text: this.keyword, placeholder: '搜索章节…' })
        .layoutWeight(1)
        .fontSize(FontSizeToken.callout)
        .fontFamily(FontFamily.ui)
        .backgroundColor('transparent')
        .padding({ left: Spacing.s1, right: Spacing.s1, top: Spacing.s2, bottom: Spacing.s2 })
        .onChange((v: string) => { this.keyword = v; })
    }
    .width('100%')
    .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s2, bottom: Spacing.s2 })
    .margin({ bottom: Spacing.s3 })
    .borderRadius(Radius.lg)
    .backgroundColor(useColor(BgColors.secondary, this.isDark))
    .border({ width: 0.5, color: useColor(BorderColors.secondary, this.isDark) })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  rowView(row: ChapterRow) {
    Row({ space: Spacing.s3 }) {
      // 状态指示
      Text(this.statusGlyph(row.status))
        .fontSize(FontSizeToken.callout)
        .fontColor(this.statusColor(row.status))
        .width(20)
        .textAlign(TextAlign.Center)

      // 序号 + 标题
      Column({ space: Spacing.s0_5 }) {
        Text(`第 ${row.chapter.index + 1} 章`)
          .fontSize(FontSizeToken.footnote)
          .fontFamily(FontFamily.ui)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
        Text(row.chapter.title || `Chapter ${row.chapter.index + 1}`)
          .fontSize(FontSizeToken.callout)
          .fontFamily(FontFamily.ui)
          .fontWeight(
            row.chapter.index === this.currentChapterIndex
              ? FontWeightToken.semibold
              : FontWeightToken.regular,
          )
          .lineHeight(LineHeightToken.callout)
          .fontColor(
            row.chapter.index === this.currentChapterIndex
              ? useColor(AccentColors.primary, this.isDark)
              : useColor(TextColors.primary, this.isDark),
          )
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 当前章节小圆点
      if (row.chapter.index === this.currentChapterIndex) {
        Text('●')
          .fontSize(FontSizeToken.footnote)
          .fontColor(useColor(AccentColors.primary, this.isDark))
      }
    }
    .width('100%')
    .padding({
      left: Spacing.s4,
      right: Spacing.s4,
      top: Spacing.s3,
      bottom: Spacing.s3,
    })
    .backgroundColor(
      row.chapter.index === this.currentChapterIndex
        ? useColor(BgColors.tertiary, this.isDark)
        : 'transparent',
    )
    .borderRadius(Radius.md)
    .onClick(() => this.handleTap(row.chapter.index))
  }

  private readonly skeletonIdx: number[] = [0, 1, 2, 3, 4, 5];

  @Builder
  loadingView() {
    Column({ space: Spacing.s2 }) {
      ForEach(this.skeletonIdx, (i: number) => {
        AppSkeleton({ variant: 'list-item' })
      }, (i: number) => `s-${i}`)
    }
    .width('100%')
  }

  @Builder
  errorView() {
    AppEmptyState({
      variant: 'error',
      description: this.errMsg,
      actionLabel: '重试',
      onAction: () => this.refresh(),
    })
  }

  @Builder
  emptyView() {
    AppEmptyState({
      variant: 'no-results',
      title: '没有匹配的章节',
      description: '试试换个关键词',
    })
  }

  @Builder
  sheetBody() {
    Column() {
      // 顶部 subtitle（书名）
      if (this.bookTitle && this.bookTitle.length > 0) {
        Text(this.bookTitle)
          .fontSize(FontSizeToken.footnote)
          .fontFamily(FontFamily.ui)
          .fontColor(useColor(TextColors.secondary, this.isDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ bottom: Spacing.s2 })
      }

      this.searchBar()

      if (this.loading) {
        this.loadingView()
      } else if (this.errMsg.length > 0) {
        this.errorView()
      } else if (this.filtered.length === 0) {
        this.emptyView()
      } else {
        List({ space: Spacing.s1 }) {
          ForEach(this.filtered, (row: ChapterRow) => {
            ListItem() {
              this.rowView(row)
            }
          }, (row: ChapterRow) => row.chapter.id || `${row.chapter.index}`)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({
          strokeWidth: 0.5,
          color: useColor(SurfaceColors.divider, this.isDark),
          startMargin: Spacing.s4,
          endMargin: Spacing.s4,
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    AppSheet({
      visible: $visible,
      title: '目录',
      snapPoints: [0.4, 0.8],
      isDark: this.isDark,
      sheetBody: () => this.sheetBody(),
    })
  }
}
