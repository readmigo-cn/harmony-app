/**
 * ReaderTabletLayout.ets — W14-C4 平板专属阅读双页布局
 *
 * 横屏：左右双页（仿实体书翻页）
 *   - 左页：currentPage     右页：currentPage + 1
 *   - 翻页：一次推进 2 页（next: pageIndex += 2 / prev: pageIndex -= 2）
 *   - 中央装订线效果（细阴影 + 1px divider）
 *   - 翻页动画：用 ArkUI animateTo + rotateY 占位实现 curl-like 翻转
 *
 * 竖屏：单页 fallback（与现有 mobile Reader 一致的视觉，但仍走本组件以保持
 *      路由一致；实际项目里也可在外层 ifElse 直接 push 到现有 Reader）
 *
 * 双页排版策略：
 *   1. 复用现有 TypesettingEngine：调一次 layoutHtml，pageWidth 用「半屏宽」算
 *   2. getPage(idx)   → 左页
 *   3. getPage(idx+1) → 右页（不存在时右页空白，下次翻页跨章）
 *   4. 字号 / 行距 / 主题 与 SettingsStore 共享，与 mobile Reader 状态完全一致
 *
 * 注意：本组件接收 ReaderRouteParams（同 mobile）作为 @Prop；不直接 import
 * mobile Reader.ets，避免循环依赖。Reader-side 状态（高亮 / 笔记 / TTS）
 * 留给 mobile Reader 处理 —— 本布局聚焦「双页阅读」核心。
 */

import { AppColors } from '../../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../../core/theme/AppSpacing';
import { ReaderRouteParams } from '../../../../core/router/RouteConstants';
import { RouterService } from '../../../../core/router/RouterService';
import {
  SettingsStore,
  ReaderTheme,
} from '../../../../store/SettingsStore';
import {
  TypesettingEngine,
  TypesetPage,
  createTypesettingEngine,
} from '../../../../core/native/typesetting';
import { BooksApi } from '../../../../api/books/BooksApi';
import { Chapter, ChapterContent } from '../../../../model/Chapter';
import promptAction from '@ohos.promptAction';

interface ThemeColors {
  bg: string;
  text: string;
  secondary: string;
  spine: string;
}

const THEME_MAP: Record<ReaderTheme, ThemeColors> = {
  day:   { bg: '#FBF7EE', text: '#1A1A1A', secondary: '#666666', spine: '#E0D8C8' },
  night: { bg: '#1A1A1A', text: '#E5E5E5', secondary: '#A0A0A0', spine: '#000000' },
  paper: { bg: '#F4ECD8', text: '#3B2F1E', secondary: '#7A6A52', spine: '#D8CDB0' },
};

const FALLBACK_HTML = `
<h1>Chapter 1</h1>
<p>It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.</p>
`.trim();

@Component
export struct ReaderTabletLayout {
  @Prop params: ReaderRouteParams;

  // ---- 章节 / 排版态 ---------------------------------------------------
  @State chapters: Chapter[] = [];
  @State chapterIndex: number = 0;
  @State chapterTitle: string = '';
  @State chapterHtml: string = FALLBACK_HTML;
  @State chapterCss: string = '';
  @State pageIndex: number = 0;        // 左页 index；右页 = pageIndex+1
  @State pageCount: number = 0;
  @State leftPage: TypesetPage | null = null;
  @State rightPage: TypesetPage | null = null;

  // ---- 设置（与 mobile Reader 共享 SettingsStore） --------------------
  @State fontSize: number = SettingsStore.getReaderFontSize();
  @State lineHeight: number = SettingsStore.getReaderLineHeight();
  @State theme: ReaderTheme = SettingsStore.getReaderTheme();
  @State fontFamily: string = 'HarmonyOS Sans';

  // ---- UI 态 -----------------------------------------------------------
  @State loading: boolean = true;
  @State errMsg: string = '';
  @State toolbarVisible: boolean = false;
  @State isLandscape: boolean = true;
  @State flipAnimation: number = 0;  // -1=向前翻 / 0=静止 / 1=向后翻

  // ---- engine + canvas -------------------------------------------------
  private engine: TypesettingEngine | null = null;
  private bookId: string = 'demo';
  private bookSlug: string = '';
  private chapterId: string = 'chapter-1';

  // 左右页各持有独立 Canvas context
  private leftSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private leftCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.leftSettings);
  private rightSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private rightCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.rightSettings);

  // 半屏页面尺寸：在 onAreaChange 中计算，初始默认值（16:10 平板横屏）
  private halfPageWidth: number = 480;
  private halfPageHeight: number = 720;

  aboutToAppear(): void {
    this.bookId = this.params?.bookId ?? 'demo';
    this.bookSlug = (this.params as Record<string, string> | undefined)?.['slug'] ?? this.bookId;
    this.chapterId = this.params?.chapterId ?? 'chapter-1';
    this.engine = createTypesettingEngine();
    this.engine.setLineHeight(this.lineHeight);
    this.bootstrap();
  }

  aboutToDisappear(): void {
    this.engine?.destroy();
    this.engine = null;
  }

  // ---- 加载 ------------------------------------------------------------

  private async bootstrap(): Promise<void> {
    this.loading = true;
    this.errMsg = '';
    try {
      const chs = await this.loadChapterList();
      this.chapters = chs;
      this.chapterIndex = Math.max(0, Math.min(chs.length - 1, 0));
      await this.loadChapter(this.chapterIndex, 0);
    } catch (err) {
      this.errMsg = (err as Error).message ?? '加载失败';
    } finally {
      this.loading = false;
    }
  }

  private async loadChapterList(): Promise<Chapter[]> {
    try {
      return await BooksApi.getChapters(this.bookSlug);
    } catch (_e) {
      return [{ id: this.chapterId, index: 0, title: 'Chapter 1' }];
    }
  }

  private async loadChapter(index: number, startPage: number = 0): Promise<void> {
    if (!this.engine) return;
    if (index < 0 || index >= this.chapters.length) return;
    this.chapterIndex = index;
    const ch = this.chapters[index];
    this.chapterTitle = ch?.title ?? `Chapter ${index + 1}`;
    this.chapterId = ch?.id ?? `chapter-${index + 1}`;
    let content: ChapterContent | null = null;
    try {
      content = await BooksApi.getChapterContent(this.bookSlug, index);
    } catch (_e) {
      content = null;
    }
    this.chapterHtml = content?.html ?? FALLBACK_HTML;
    this.chapterCss = content?.css ?? '';
    await this.relayout(startPage);
  }

  /**
   * 双页排版：以「半屏宽」作为单页宽度调用 engine.layoutHtml。
   * 排版结果总页数仍是奇偶混合；右页可能不存在（章末单数页），渲染时留白。
   */
  private async relayout(startPage: number = 0): Promise<void> {
    if (!this.engine) return;
    try {
      this.engine.setFontSize(this.fontSize);
      this.engine.setLineHeight(this.lineHeight);
      this.engine.setLayoutProfile({
        pageWidth: this.halfPageWidth,
        pageHeight: this.halfPageHeight,
        fontSize: this.fontSize,
        lineHeight: this.lineHeight,
      });
      const summary = this.engine.layoutHtml(
        this.chapterHtml + (this.chapterCss ? `\n<style>${this.chapterCss}</style>` : ''),
        this.chapterId,
        this.halfPageWidth,
        this.halfPageHeight,
        this.fontSize,
      );
      this.pageCount = summary.pageCount;
      // 双页：startPage 对齐到偶数页（左页）
      const target = Math.max(0, Math.min(this.pageCount - 1, startPage - (startPage % 2)));
      this.loadPagePair(target);
    } catch (e) {
      this.errMsg = (e as Error).message ?? '排版失败';
    }
  }

  private loadPagePair(leftIdx: number): void {
    if (!this.engine) return;
    if (leftIdx < 0 || leftIdx >= this.pageCount) return;
    this.pageIndex = leftIdx;
    this.leftPage = this.engine.getPage(this.chapterId, leftIdx);
    this.rightPage = leftIdx + 1 < this.pageCount
      ? this.engine.getPage(this.chapterId, leftIdx + 1)
      : null;
    this.draw();
  }

  /** 翻到下一对页：一次推进 2 页 */
  private nextPair(): void {
    const nextLeft = this.pageIndex + 2;
    if (nextLeft < this.pageCount) {
      this.playFlip(1);
      this.loadPagePair(nextLeft);
    } else if (this.chapterIndex + 1 < this.chapters.length) {
      this.playFlip(1);
      this.loadChapter(this.chapterIndex + 1, 0);
    } else {
      promptAction.showToast({ message: '已到最后一页' });
    }
  }

  /** 翻到上一对页：一次回退 2 页 */
  private prevPair(): void {
    const prevLeft = this.pageIndex - 2;
    if (prevLeft >= 0) {
      this.playFlip(-1);
      this.loadPagePair(prevLeft);
    } else if (this.chapterIndex > 0) {
      this.playFlip(-1);
      // 跳到上一章末尾 —— 简化为 chapter 起始的最后一对页（需重新 layout）
      this.loadChapter(this.chapterIndex - 1, 0);
    } else {
      promptAction.showToast({ message: '已是第一页' });
    }
  }

  /**
   * 翻页动画占位：通过 flipAnimation 状态触发 rotateY，由 ArkUI 在 .animation
   * 修饰符下自动 tween；240ms 后回到 0 恢复静止态。
   *
   * 真正的 page-curl 需要 SkSL / Canvas 双 buffer，这里仅用 rotateY ±8° 占位
   * 给实体翻页的反馈感。
   */
  private playFlip(dir: number): void {
    this.flipAnimation = dir;
    setTimeout(() => {
      this.flipAnimation = 0;
    }, 240);
  }

  // ---- 渲染 ------------------------------------------------------------

  private draw(): void {
    this.drawSinglePage(this.leftCtx, this.leftPage);
    this.drawSinglePage(this.rightCtx, this.rightPage);
  }

  private drawSinglePage(ctx: CanvasRenderingContext2D, page: TypesetPage | null): void {
    const colors = THEME_MAP[this.theme];
    ctx.fillStyle = colors.bg;
    ctx.fillRect(0, 0, this.halfPageWidth, this.halfPageHeight);
    if (!page) return;
    ctx.fillStyle = colors.text;
    for (const line of page.lines) {
      for (const run of line.runs) {
        ctx.font = `${run.fontSize}px ${this.fontFamily}`;
        ctx.fillText(run.text, run.x, run.y);
      }
    }
  }

  // ---- 手势 ------------------------------------------------------------

  private onTap(event: ClickEvent, isLeftPage: boolean): void {
    const x = event.localX;
    const w = this.halfPageWidth;
    // 左页左 1/3 → prev；右页右 1/3 → next；中部 → 切换工具栏
    if (isLeftPage && x < w * 0.3) {
      this.prevPair();
      return;
    }
    if (!isLeftPage && x > w * 0.7) {
      this.nextPair();
      return;
    }
    this.toolbarVisible = !this.toolbarVisible;
  }

  // ---- 设置回调 --------------------------------------------------------

  private adjustFontSize(delta: number): void {
    const next = Math.max(12, Math.min(28, this.fontSize + delta));
    if (next === this.fontSize) return;
    this.fontSize = next;
    SettingsStore.setReaderFontSize(next);
    this.relayout(this.pageIndex);
  }

  private setTheme(t: ReaderTheme): void {
    this.theme = t;
    SettingsStore.setReaderTheme(t);
    this.engine?.setTheme(t === 'paper' ? 'sepia' : t);
    this.draw();
  }

  // ---- builders --------------------------------------------------------

  @Builder
  topBar() {
    Row({ space: AppSpacing.sm }) {
      Text('< 返回')
        .fontSize(AppFontSize.sm)
        .fontColor(THEME_MAP[this.theme].text)
        .padding(AppSpacing.xs)
        .onClick(() => RouterService.pop())
      Text(this.chapterTitle)
        .fontSize(AppFontSize.sm)
        .fontColor(THEME_MAP[this.theme].text)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`${this.pageIndex + 1}-${Math.min(this.pageIndex + 2, this.pageCount)} / ${this.pageCount}`)
        .fontSize(AppFontSize.xs)
        .fontColor(THEME_MAP[this.theme].secondary)
    }
    .width('100%')
    .padding({ left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.sm, bottom: AppSpacing.sm })
    .backgroundColor(THEME_MAP[this.theme].bg)
  }

  @Builder
  bottomBar() {
    Row({ space: AppSpacing.lg }) {
      Text('A-')
        .fontSize(AppFontSize.md)
        .fontColor(THEME_MAP[this.theme].text)
        .padding(AppSpacing.sm)
        .onClick(() => this.adjustFontSize(-1))
      Text('A+')
        .fontSize(AppFontSize.md)
        .fontColor(THEME_MAP[this.theme].text)
        .padding(AppSpacing.sm)
        .onClick(() => this.adjustFontSize(1))
      Text('日')
        .fontSize(AppFontSize.md)
        .fontColor(this.theme === 'day' ? AppColors.brand : THEME_MAP[this.theme].text)
        .padding(AppSpacing.sm)
        .onClick(() => this.setTheme('day'))
      Text('羊')
        .fontSize(AppFontSize.md)
        .fontColor(this.theme === 'paper' ? AppColors.brand : THEME_MAP[this.theme].text)
        .padding(AppSpacing.sm)
        .onClick(() => this.setTheme('paper'))
      Text('夜')
        .fontSize(AppFontSize.md)
        .fontColor(this.theme === 'night' ? AppColors.brand : THEME_MAP[this.theme].text)
        .padding(AppSpacing.sm)
        .onClick(() => this.setTheme('night'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm })
    .backgroundColor(THEME_MAP[this.theme].bg)
  }

  @Builder
  pageCanvas(isLeft: boolean) {
    Canvas(isLeft ? this.leftCtx : this.rightCtx)
      .width(this.halfPageWidth)
      .height(this.halfPageHeight)
      .backgroundColor(THEME_MAP[this.theme].bg)
      .onReady(() => this.draw())
      .onAreaChange((_old, newArea) => {
        const w = Number(newArea.width);
        const h = Number(newArea.height);
        if (w > 0 && h > 0
          && (Math.abs(w - this.halfPageWidth) > 1 || Math.abs(h - this.halfPageHeight) > 1)) {
          this.halfPageWidth = w;
          this.halfPageHeight = h;
          this.relayout(this.pageIndex);
        }
      })
      .onClick((e: ClickEvent) => this.onTap(e, isLeft))
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal })
          .onActionEnd((e: GestureEvent) => {
            const dx = e.offsetX;
            if (dx < -50) this.nextPair();
            else if (dx > 50) this.prevPair();
          }),
      )
      // curl-like 占位翻页效果：用 rotateY + 透视
      .rotate({
        x: 0,
        y: 1,
        z: 0,
        angle: this.flipAnimation === 0
          ? 0
          : (isLeft ? this.flipAnimation * -8 : this.flipAnimation * 8),
        centerX: isLeft ? '100%' : '0%',
        centerY: '50%',
      })
      .animation({ duration: 220, curve: Curve.EaseInOut })
  }

  /** 双页主体：左页 + 装订线 + 右页 */
  @Builder
  doublePage() {
    Row() {
      // 左页
      Stack() {
        this.pageCanvas(true)
        // 右边缘阴影：模拟装订线侧的纸张厚度
        Column()
          .width(8)
          .height('100%')
          .backgroundColor('#00000020')
          .position({ x: this.halfPageWidth - 8, y: 0 })
      }
      .width(this.halfPageWidth)
      .height(this.halfPageHeight)

      // 中央装订线
      Divider()
        .vertical(true)
        .strokeWidth(1)
        .color(THEME_MAP[this.theme].spine)
        .height('100%')

      // 右页
      Stack() {
        this.pageCanvas(false)
        // 左边缘阴影
        Column()
          .width(8)
          .height('100%')
          .backgroundColor('#00000020')
          .position({ x: 0, y: 0 })
      }
      .width(this.halfPageWidth)
      .height(this.halfPageHeight)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  /** 单页 fallback（竖屏 / 窄屏） */
  @Builder
  singlePage() {
    Canvas(this.leftCtx)
      .width('100%')
      .height('100%')
      .backgroundColor(THEME_MAP[this.theme].bg)
      .onReady(() => this.draw())
      .onAreaChange((_old, newArea) => {
        const w = Number(newArea.width);
        const h = Number(newArea.height);
        if (w > 0 && h > 0
          && (Math.abs(w - this.halfPageWidth) > 1 || Math.abs(h - this.halfPageHeight) > 1)) {
          this.halfPageWidth = w;
          this.halfPageHeight = h;
          this.relayout(this.pageIndex);
        }
      })
      .onClick((e: ClickEvent) => this.onTap(e, true))
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal })
          .onActionEnd((e: GestureEvent) => {
            const dx = e.offsetX;
            // 单页模式：next/prev 仍走 pair 推进，但每次只 +2 / -2 也 OK
            if (dx < -50) this.nextPair();
            else if (dx > 50) this.prevPair();
          }),
      )
  }

  @Builder
  loadingOverlay() {
    Column() {
      LoadingProgress().width(40).height(40).color(AppColors.brand)
      Text('加载中...').fontSize(AppFontSize.sm).fontColor(AppColors.textSecondary)
        .margin({ top: AppSpacing.sm })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(THEME_MAP[this.theme].bg)
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          if (this.toolbarVisible) { this.topBar() }

          Stack() {
            if (this.isLandscape) {
              this.doublePage()
            } else {
              this.singlePage()
            }
            if (this.loading) { this.loadingOverlay() }
            if (this.errMsg && !this.loading) {
              Column({ space: AppSpacing.base }) {
                Text('加载失败').fontSize(AppFontSize.md).fontColor(AppColors.danger)
                Text(this.errMsg).fontSize(AppFontSize.sm).fontColor(AppColors.textTertiary)
                Button('重试').onClick(() => this.bootstrap())
              }
              .width('100%').height('100%').justifyContent(FlexAlign.Center)
            }
          }
          .layoutWeight(1)
          .width('100%')
          .backgroundColor(THEME_MAP[this.theme].bg)
          // 监听容器尺寸切换 横竖屏 fallback
          .onAreaChange((_old, newArea) => {
            const w = Number(newArea.width);
            const h = Number(newArea.height);
            this.isLandscape = w >= h;
          })

          if (this.toolbarVisible) { this.bottomBar() }
        }
        .width('100%').height('100%')
        .backgroundColor(THEME_MAP[this.theme].bg)
      }
      .width('100%').height('100%')
    }
    .hideTitleBar(true)
  }
}
