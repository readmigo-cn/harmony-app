import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { ReaderRouteParams, RoutePath, ComprehensionRouteParams } from '../../../core/router/RouteConstants';
import { RouterService } from '../../../core/router/RouterService';
import {
  SettingsStore,
  ReaderTheme,
  PageTurnMode,
  ReaderFont,
} from '../../../store/SettingsStore';
import { ReadingStore, ReadingProgress as LocalProgress } from '../../../store/ReadingStore';
import {
  TypesettingEngine,
  TypesetPage,
  HitResult,
  createTypesettingEngine,
} from '../../../core/native/typesetting';
import { WordExplainSheet, WordExplainContext } from '../../../features/ai-tools/components/WordExplainSheet';
import { ReaderSettingsSheet } from '../../../features/reader/components/ReaderSettingsSheet';
import { ChapterTocSheet } from '../../../features/reader/components/ChapterTocSheet';
import { ProgressSync } from '../../../features/multi-device/service/ProgressSync';
import { ReadingSession } from '../../../features/reader/service/ReadingSession';
import { EffectiveTheme } from '../../../core/theme/Theme.types';
import { BooksApi } from '../../../api/books/BooksApi';
import { ReadingApi } from '../../../api/reading/ReadingApi';
import { NotesApi, NoteRecord } from '../../../api/notes/NotesApi';
import { Chapter, ChapterContent } from '../../../model/Chapter';
import { Highlight, HighlightColor } from '../../../model/Highlight';
import { ReadingProgressDto } from '../../../model/ReadingProgress';
import promptAction from '@ohos.promptAction';
// W8-C4 / C5 / C6：翻译 / TTS / 句子高亮
import { TranslateService, TranslateResult } from '../../../features/ai-tools/service/TranslateService';
import { TtsService, TtsHandle, Voice } from '../../../features/audiobook/service/TtsService';
import { SentenceHighlight, SentenceRect } from '../../../features/reader/components/SentenceHighlight';
import { ToastManager } from '../../../ui/primitives/Toast';
// W11-C3 / W13-C3：阅读接续（手机 ↔ 平板 多端协同）+ 设备选择
import { ContinuationManager } from '../../../core/atomic/ContinuationManager';
import { DeviceSelectorSheet } from '../../../features/multi-device/components/DeviceSelectorSheet';
import { TrustedDevice } from '../../../features/multi-device/service/distributed/DeviceManager';
// W11-C2 / W11-C4：单词分享 / 划词查询元服务
import { AtomicLauncher } from '../../../core/atomic/AtomicLauncher';
// W13-C2：跨端剪贴板（把选中单词分享到其它设备）
import { DistributedClipboard, VocabPayload } from '../../../features/multi-device/service/distributed/DistributedClipboard';
import common from '@ohos.app.ability.common';
// W14-C4：平板双页阅读布局
import {
  Breakpoint,
  FoldStatus,
  STORAGE_KEY_BREAKPOINT,
  STORAGE_KEY_FOLD_STATUS,
} from '../../../core/theme/Breakpoints';
import { ReaderTabletLayout } from '../../multi-platform/pages/tablet/ReaderTabletLayout';
// W18-C1：Reader 页面曝光埋点
import { Analytics } from '../../../core/analytics/AnalyticsProvider';
import { SaEvents } from '../../../core/analytics/SensorsAnalytics';

const FALLBACK_HTML = `
<h1>Chapter 1 — Sample</h1>
<p>It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.</p>
<p>However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered the rightful property of some one or other of their daughters.</p>
`.trim();

interface ThemeColors {
  bg: string;
  text: string;
  secondary: string;
}

const THEME_MAP: Record<ReaderTheme, ThemeColors> = {
  day:   { bg: '#FBF7EE', text: '#1A1A1A', secondary: '#666666' },
  night: { bg: '#1A1A1A', text: '#E5E5E5', secondary: '#A0A0A0' },
  paper: { bg: '#F4ECD8', text: '#3B2F1E', secondary: '#7A6A52' },
};

const HIGHLIGHT_COLORS: HighlightColor[] = ['yellow', 'green', 'blue', 'pink', 'orange'];
const HIGHLIGHT_HEX: Record<HighlightColor, string> = {
  yellow: '#FFF59D', green: '#C8E6C9', blue: '#BBDEFB', pink: '#F8BBD0', orange: '#FFE0B2',
};

@Component
export struct Reader {
  @Prop params: ReaderRouteParams;

  // ---- chapter state ------------------------------------------------------
  @State chapters: Chapter[] = [];
  @State chapterIndex: number = 0;
  @State chapterTitle: string = '';
  @State chapterHtml: string = FALLBACK_HTML;
  @State chapterCss: string = '';
  @State pageIndex: number = 0;
  @State pageCount: number = 0;
  @State currentPage: TypesetPage | null = null;

  // ---- reader settings ----------------------------------------------------
  @State fontSize: number = SettingsStore.getReaderFontSize();
  @State lineHeight: number = SettingsStore.getReaderLineHeight();
  @State theme: ReaderTheme = SettingsStore.getReaderTheme();
  @State fontFamily: string = 'HarmonyOS Sans';
  @State pageTurnMode: PageTurnMode = SettingsStore.getReaderPageTurnMode();
  @State readerFont: ReaderFont = SettingsStore.getReaderFont();
  /**
   * 监听 ThemeService 推送的 effective theme（'day' | 'night' | 'sepia'）。
   * 用户切换 'system' / 系统暗色变化时由 ThemeService.recompute() 写入。
   * @Watch 在变化时触发 onEffectiveThemeChange 重绘 Canvas。
   */
  @StorageProp('app_theme_mode') @Watch('onEffectiveThemeChange') effectiveTheme: EffectiveTheme = 'day';
  // W14-C4：平板双页阅读判定（lg/xl 或 折叠屏 EXPAND）
  @StorageProp(STORAGE_KEY_BREAKPOINT) currentBp: Breakpoint = Breakpoint.MD;
  @StorageProp(STORAGE_KEY_FOLD_STATUS) foldStatus: FoldStatus = FoldStatus.UNKNOWN;

  // ---- UI state -----------------------------------------------------------
  @State toolbarVisible: boolean = false;
  @State showSettings: boolean = false;
  @State showToc: boolean = false;
  @State showNotes: boolean = false;
  /** W13-C3：设备选择 sheet（接续到其它设备） */
  @State showDeviceSelector: boolean = false;
  @State loading: boolean = true;
  @State errMsg: string = '';

  // ---- highlights / notes -------------------------------------------------
  @State highlights: Highlight[] = [];
  @State notes: NoteRecord[] = [];

  // ---- explain card -------------------------------------------------------
  @State explainCtx: WordExplainContext = {
    word: '', contextSentence: '', bookId: '', chapterId: '',
    blockIndex: 0, charOffset: 0, charLength: 0,
  };

  // ---- W8-C5：TTS 播放状态 -----------------------------------------------
  @State ttsPlaying: boolean = false;
  @State ttsPaused: boolean = false;
  @State ttsCharIndex: number = 0;
  @State ttsTotalChars: number = 0;
  @State ttsSpeed: number = 1.0;
  @State showVoiceSheet: boolean = false;
  @State sentenceRects: SentenceRect[] = [];
  private ttsHandle: TtsHandle | null = null;
  private ttsService: TtsService = TtsService.getInstance();
  private translateService: TranslateService = TranslateService.getInstance();

  // ---- engine + canvas ----------------------------------------------------
  private engine: TypesettingEngine | null = null;
  private bookId: string = 'demo';
  private bookSlug: string = '';
  private chapterId: string = 'chapter-1';
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private pageWidth: number = 360;
  private pageHeight: number = 600;

  // ---- session / progress -------------------------------------------------
  private sessionId: string | null = null;
  private sessionStartedAt: number = 0;
  private pagesReadInSession: number = 0;

  private explainController: CustomDialogController = new CustomDialogController({
    builder: WordExplainSheet({ ctx: this.explainCtx }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: true,
  });

  // ---------- lifecycle ---------------------------------------------------

  // W7-C6：每 30s tick 一次 ReadingSession，更新 activeMs
  private sessionTickTimer: number = -1;

  aboutToAppear(): void {
    this.bookId = this.params?.bookId ?? 'demo';
    this.bookSlug = (this.params as Record<string, string> | undefined)?.['slug'] ?? this.bookId;
    this.chapterId = this.params?.chapterId ?? 'chapter-1';
    this.engine = createTypesettingEngine();
    this.engine.setLineHeight(this.lineHeight);
    this.bootstrap();
    // W7-C6：启动会话；ProgressSync.pull 由 bootstrap 触发
    ReadingSession.start(this.bookId, this.chapterIndex);
    this.startSessionTickTimer();
    // W11-C3：注册接续会话，让附近设备可发现并接管
    ContinuationManager.enableContinuation(
      this.bookId,
      AppStorage.Get<string>('reading_current_title') ?? '',
      this.chapterIndex,
      this.pageIndex,
      this.pageCount > 0 ? Math.round(((this.pageIndex + 1) / this.pageCount) * 100) : 0,
    );
    // W13-C3：监听其它设备发起的接续请求
    this.subscribeIncomingContinuation();
  }

  aboutToDisappear(): void {
    this.stopSessionTickTimer();
    this.persistProgress();
    // W7-C6：结束 session + flush 队列（替代旧 endSessionFireAndForget）
    ReadingSession.end();
    ProgressSync.flush();
    // W11-C3：离开 Reader → 注销接续会话
    ContinuationManager.disableContinuation(this.bookId);
    // W13-C3：取消接续来电监听
    this.unsubscribeIncomingContinuation();
    // W8-C5：停止 TTS（页面销毁不允许后台续播本会话）
    this.stopTts();
    this.engine?.destroy();
    this.engine = null;
  }

  onPageShow(): void {
    // W7-C6：从 background 切回前台（替代旧 startSessionFireAndForget）
    ReadingSession.onForeground(this.bookId);
    this.startSessionTickTimer();
    Analytics.track(SaEvents.PAGE_VIEW, { page: 'reader', book_id: this.bookId });
    // 主动 pull 一次拿云端最新进度
    ProgressSync.pull(this.bookId).then((server) => {
      if (!server) return;
      // 仅当 server 更新且与当前章节不同 → 提示用户（不自动跳）
      if (typeof server.chapterIndex === 'number' && server.chapterIndex !== this.chapterIndex) {
        promptAction.showToast({ message: '检测到云端进度，可在目录中跳转' });
      }
    }).catch(() => {});
  }

  onPageHide(): void {
    this.stopSessionTickTimer();
    this.persistProgress();
    // W7-C6：进入后台 → 暂停会话 + flush（替代旧 endSessionFireAndForget）
    ReadingSession.onBackground();
    ProgressSync.flush();
    // W8-C5：进入后台时如果在播 → 暂停（用户从通知栏 / 后台 ServiceExt 控制续播）
    if (this.ttsPlaying && !this.ttsPaused) {
      this.pauseTts();
    }
  }

  private startSessionTickTimer(): void {
    if (this.sessionTickTimer !== -1) return;
    this.sessionTickTimer = setInterval(() => {
      ReadingSession.tick();
    }, 30_000) as unknown as number;
  }

  private stopSessionTickTimer(): void {
    if (this.sessionTickTimer !== -1) {
      clearInterval(this.sessionTickTimer);
      this.sessionTickTimer = -1;
    }
  }

  // ---------- bootstrap ---------------------------------------------------

  private async bootstrap(): Promise<void> {
    this.loading = true;
    this.errMsg = '';
    try {
      // 并行：章节列表 / 进度 / 高亮
      const tasks: [Promise<Chapter[]>, Promise<ReadingProgressDto | null>, Promise<Highlight[]>] = [
        this.loadChapterList(),
        this.loadProgress(),
        this.loadHighlights(),
      ];
      const [chapters, progress, hl] = await Promise.all(tasks);
      this.chapters = chapters;
      this.highlights = hl;
      const startChapter = progress?.chapterIndex ?? 0;
      this.chapterIndex = Math.max(0, Math.min(chapters.length - 1, startChapter));
      await this.loadChapter(this.chapterIndex, progress?.pageIndex ?? 0);
    } catch (err) {
      this.errMsg = (err as Error).message ?? '加载失败';
      // 排版引擎兜底
      this.fallbackLocalRender();
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

  private async loadProgress(): Promise<ReadingProgressDto | null> {
    try {
      return await ReadingApi.getProgress(this.bookId);
    } catch (_e) {
      return null;
    }
  }

  private async loadHighlights(): Promise<Highlight[]> {
    try {
      return await ReadingApi.listHighlights(this.bookId);
    } catch (_e) {
      return [];
    }
  }

  private async loadChapter(index: number, startPage: number = 0): Promise<void> {
    if (!this.engine) return;
    if (index < 0 || index >= this.chapters.length) return;
    const oldIndex = this.chapterIndex;
    this.chapterIndex = index;
    const ch = this.chapters[index];
    this.chapterTitle = ch?.title ?? `Chapter ${index + 1}`;
    this.chapterId = ch?.id ?? `chapter-${index + 1}`;
    // W7-C5：旧章节标记 finished，新章节标记 reading
    if (oldIndex !== index) {
      ReadingStore.setChapterStatus(this.bookId, oldIndex, 'finished');
      ReadingSession.recordChapterChange(index);
    }
    ReadingStore.setChapterStatus(this.bookId, index, 'reading');
    let content: ChapterContent | null = null;
    try {
      content = await BooksApi.getChapterContent(this.bookSlug, index);
    } catch (_e) {
      content = null;
    }
    this.chapterHtml = content?.html ?? FALLBACK_HTML;
    this.chapterCss = content?.css ?? '';
    await this.relayoutAndRender(startPage);
    this.notes = await this.loadNotesForChapter();
  }

  private async loadNotesForChapter(): Promise<NoteRecord[]> {
    try {
      return await NotesApi.listByBook(this.bookId);
    } catch (_e) {
      return [];
    }
  }

  /**
   * Relayout 流程（layout cache 持有方）：
   *  - TypesettingEngine 内部维护 chapterId → LayoutResult LRU（C++ 5 章 / mock unbounded）
   *  - relayout 触发条件：fontSize / pageWidth / pageHeight / lineHeight 变化，或换章
   *  - relayoutAndRender 是 ArkUI 侧的入口，外部状态变化（如 onAreaChange）调用此处
   */
  private async relayoutAndRender(startPage: number = 0): Promise<void> {
    if (!this.engine) return;
    try {
      this.engine.setFontSize(this.fontSize);
      this.engine.setLineHeight(this.lineHeight);
      this.engine.setLayoutProfile({
        pageWidth: this.pageWidth,
        pageHeight: this.pageHeight,
        fontSize: this.fontSize,
        lineHeight: this.lineHeight,
      });
      const summary = this.engine.layoutHtml(
        this.chapterHtml + (this.chapterCss ? `\n<style>${this.chapterCss}</style>` : ''),
        this.chapterId,
        this.pageWidth,
        this.pageHeight,
        this.fontSize,
      );
      this.pageCount = summary.pageCount;
      const target = Math.max(0, Math.min(this.pageCount - 1, startPage));
      this.loadPage(target);
    } catch (e) {
      this.errMsg = (e as Error).message ?? '排版失败';
      this.fallbackLocalRender();
    }
  }

  /** Engine 崩溃 / 网络失败时的兜底渲染，画一段简单提示文字。 */
  private fallbackLocalRender(): void {
    const ctx = this.context;
    const colors = THEME_MAP[this.theme];
    ctx.fillStyle = colors.bg;
    ctx.fillRect(0, 0, this.pageWidth, this.pageHeight);
    ctx.fillStyle = colors.text;
    ctx.font = `${this.fontSize}px ${this.fontFamily}`;
    const msg = this.errMsg || '正在加载...';
    ctx.fillText(msg, 24, 80);
  }

  private loadPage(index: number): void {
    if (!this.engine) return;
    if (index < 0 || index >= this.pageCount) return;
    this.pageIndex = index;
    this.currentPage = this.engine.getPage(this.chapterId, index);
    this.pagesReadInSession += 1;
    // W7-C6：累加 session 翻页计数
    ReadingSession.recordPageTurn();
    this.draw();
    this.persistProgressDebounced();
  }

  private nextPage(): void {
    if (this.pageIndex + 1 < this.pageCount) {
      this.loadPage(this.pageIndex + 1);
    } else if (this.chapterIndex + 1 < this.chapters.length) {
      this.loadChapter(this.chapterIndex + 1, 0);
    } else {
      promptAction.showToast({ message: '已到最后一章' });
    }
  }

  private prevPage(): void {
    if (this.pageIndex > 0) {
      this.loadPage(this.pageIndex - 1);
    } else if (this.chapterIndex > 0) {
      this.loadChapter(this.chapterIndex - 1, 0);
    } else {
      promptAction.showToast({ message: '已是第一章' });
    }
  }

  // ---------- rendering ---------------------------------------------------

  private draw(): void {
    const ctx = this.context;
    const page = this.currentPage;
    const colors = THEME_MAP[this.theme];
    ctx.fillStyle = colors.bg;
    ctx.fillRect(0, 0, this.pageWidth, this.pageHeight);
    if (!page) return;

    // Highlights underlay —— 在文字之前画
    for (const hl of this.highlights) {
      this.drawHighlight(ctx, hl, page);
    }

    ctx.fillStyle = colors.text;
    for (const line of page.lines) {
      for (const run of line.runs) {
        ctx.font = `${run.fontSize}px ${this.fontFamily}`;
        ctx.fillText(run.text, run.x, run.y);
      }
    }
  }

  private drawHighlight(ctx: CanvasRenderingContext2D, hl: Highlight, page: TypesetPage): void {
    if (hl.chapterId && hl.chapterId !== this.chapterId) return;
    ctx.fillStyle = HIGHLIGHT_HEX[hl.color] ?? HIGHLIGHT_HEX.yellow;
    for (const line of page.lines) {
      for (const run of line.runs) {
        if (run.blockIndex !== hl.blockIndex) continue;
        const runStart = run.charOffset;
        const runEnd = run.charOffset + run.charLength;
        const hlStart = hl.charOffset;
        const hlEnd = hl.charOffset + hl.charLength;
        const overlapStart = Math.max(runStart, hlStart);
        const overlapEnd = Math.min(runEnd, hlEnd);
        if (overlapEnd <= overlapStart) continue;
        const ratio = run.w / Math.max(1, run.charLength);
        const x = run.x + (overlapStart - runStart) * ratio;
        const w = (overlapEnd - overlapStart) * ratio;
        ctx.fillRect(x, run.y - line.ascent, w, line.h);
      }
    }
  }

  // ---------- gestures ----------------------------------------------------

  private onTap(event: ClickEvent): void {
    const x = event.localX;
    const y = event.localY;
    const w = this.pageWidth;
    if (x < w * 0.3) {
      this.prevPage();
      return;
    }
    if (x > w * 0.7) {
      this.nextPage();
      return;
    }
    this.toolbarVisible = !this.toolbarVisible;
  }

  private onLongPress(event: GestureEvent): void {
    if (!this.engine) return;
    const fingers = event.fingerList;
    if (!fingers || fingers.length === 0) return;
    const finger = fingers[0];
    if (!finger) return;
    const x = finger.localX;
    const y = finger.localY;
    const hit: HitResult | null = this.engine.hitTest(this.chapterId, this.pageIndex, x, y);
    if (!hit || !hit.text) return;
    if (!/[A-Za-z]/.test(hit.text)) {
      // 非英文：触发选句模式
      this.tryHighlightSentence(hit);
      return;
    }
    this.openExplainCard(hit);
  }

  private openExplainCard(hit: HitResult): void {
    this.explainCtx = {
      word: hit.text,
      contextSentence: this.extractContextSentence(hit.blockIndex, hit.charOffset),
      bookId: this.bookId,
      chapterId: this.chapterId,
      blockIndex: hit.blockIndex,
      charOffset: hit.charOffset,
      charLength: hit.charLength,
    };
    this.explainController = new CustomDialogController({
      builder: WordExplainSheet({ ctx: this.explainCtx }),
      alignment: DialogAlignment.Bottom,
      customStyle: true,
      autoCancel: true,
    });
    // W7-C6：记一次查词
    ReadingSession.recordWordLookup();
    this.explainController.open();
  }

  /**
   * W11-C4 占位：把当前单词分享到「划词查询元服务」（独立窗口 / 跨设备分享）。
   * 暂未在 UI 暴露按钮（SelectionLayer 还未接入）；
   * 后续接入 SelectionLayer 时在 onLookup 旁加一个「分享到元服务」action 调本方法。
   * 不破坏原 happy path：调用失败仅 toast，不影响阅读流程。
   */
  private async shareWordToAtomic(word: string, contextSentence?: string): Promise<void> {
    if (!word) return;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await AtomicLauncher.launchLookup(ctx, word, contextSentence ?? this.extractContextSentence(0, 0));
    } catch (e) {
      ToastManager.error(`分享到元服务失败: ${(e as Error).message}`);
    }
  }

  private async tryHighlightSentence(hit: HitResult): Promise<void> {
    if (!this.engine) return;
    const sentence = this.engine.findSentenceAt(this.pageIndex, 0, 0) ?? hit;
    try {
      const created = await ReadingApi.createHighlight({
        bookId: this.bookId,
        chapterId: this.chapterId,
        chapterIndex: this.chapterIndex,
        blockIndex: sentence.blockIndex,
        charOffset: sentence.charOffset,
        charLength: sentence.charLength,
        text: sentence.text,
        color: 'yellow',
      });
      this.highlights = [...this.highlights, created];
      this.draw();
      promptAction.showToast({ message: '已添加划线' });
    } catch (_e) {
      promptAction.showToast({ message: '划线保存失败' });
    }
  }

  private extractContextSentence(blockIndex: number, charOffset: number): string {
    if (!this.currentPage) return '';
    const parts: string[] = [];
    for (const line of this.currentPage.lines) {
      for (const run of line.runs) {
        if (run.blockIndex === blockIndex) parts.push(run.text);
      }
    }
    const fullBlock = parts.join(' ');
    const sentEnd = fullBlock.indexOf('.', charOffset);
    const sentStart = Math.max(0, fullBlock.lastIndexOf('.', charOffset - 1));
    const slice = fullBlock.slice(sentStart === 0 ? 0 : sentStart + 1, sentEnd === -1 ? fullBlock.length : sentEnd + 1);
    return slice.trim() || fullBlock.slice(0, 200);
  }

  // ---------- settings actions --------------------------------------------

  private adjustFontSize(delta: number): void {
    const next = Math.max(12, Math.min(28, this.fontSize + delta));
    if (next === this.fontSize) return;
    this.fontSize = next;
    SettingsStore.setReaderFontSize(next);
    this.relayoutAndRender(this.pageIndex);
  }

  private adjustLineHeight(delta: number): void {
    const next = Math.max(1.0, Math.min(2.4, this.lineHeight + delta));
    if (Math.abs(next - this.lineHeight) < 1e-3) return;
    this.lineHeight = next;
    this.relayoutAndRender(this.pageIndex);
  }

  private setTheme(t: ReaderTheme): void {
    this.theme = t;
    SettingsStore.setReaderTheme(t);
    this.engine?.setTheme(t === 'paper' ? 'sepia' : t);
    this.draw();
  }

  /** W9-C7：打开当前章节的阅读理解题。 */
  private openComprehension(): void {
    const params: ComprehensionRouteParams = {
      bookId: this.bookId,
      chapterIndex: this.chapterIndex,
    };
    RouterService.push(RoutePath.READING_COMPREHENSION, params);
  }

  /**
   * W11-C2：分享当前选中的单词到 ShareWordAbility 元服务。
   *
   * 复用 explainCtx 中已经收集好的 word + contextSentence + bookId/chapterId。
   * 走 AtomicLauncher.launchShareWord：触发主包内 ShareWordAbility 渲染分享卡片。
   */
  private async shareSelectedWord(): Promise<void> {
    if (!this.explainCtx.word) {
      promptAction.showToast({ message: '请先长按选词' });
      return;
    }
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await AtomicLauncher.launchShareWord(
        ctx,
        this.explainCtx.word,
        this.explainCtx.contextSentence,
        {
          bookTitle: AppStorage.Get<string>('reading_current_title') ?? '',
          chapterTitle: this.chapterTitle,
        },
      );
    } catch (_e) {
      promptAction.showToast({ message: '分享卡片暂不可用' });
    }
  }

  /**
   * W13-C2：把选中单词写入分布式剪贴板，其它登录同账号设备会自动收到。
   *
   * 与 W11-C2 shareSelectedWord 区别：
   *   - W11-C2 走元服务卡片，目标是「分享出去给别人看」（截图 / 转发）
   *   - W13-C2 走分布式剪贴板，目标是「同步给我的另一台设备继续学」
   */
  private async copySelectedWordToOtherDevice(): Promise<void> {
    if (!this.explainCtx.word) {
      promptAction.showToast({ message: '请先长按选词' });
      return;
    }
    const payload: VocabPayload = {
      word: this.explainCtx.word,
      context: this.explainCtx.contextSentence,
      bookId: AppStorage.Get<string>('reading_current_book_id') ?? undefined,
      bookTitle: AppStorage.Get<string>('reading_current_title') ?? undefined,
      chapterTitle: this.chapterTitle,
      timestamp: Date.now(),
    };
    try {
      await DistributedClipboard.copyVocab(payload);
      promptAction.showToast({ message: '已复制，到其它设备粘贴' });
    } catch (_e) {
      promptAction.showToast({ message: '复制失败' });
    }
  }

  private setFontFamily(name: string): void {
    this.fontFamily = name;
    this.draw();
  }

  // ---------- W13-C3 跨设备接续 ------------------------------------------

  /** 取消监听接续来电的句柄；aboutToDisappear 释放。 */
  private incomingUnsubscribe: (() => void) | null = null;

  /** 打开设备选择 sheet（toolbar 「转到其它设备」按钮）。 */
  private openDeviceSelector(): void {
    if (!ContinuationManager.hasActiveSession()) {
      promptAction.showToast({ message: '当前无活跃阅读会话' });
      return;
    }
    this.showDeviceSelector = true;
  }

  /** DeviceSelectorSheet onSelect 回调：触发 transferTo + toast 反馈。 */
  private async onDeviceSelected(deviceId: string, device: TrustedDevice): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const ok = await ContinuationManager.transferTo(deviceId, ctx);
      if (ok) {
        promptAction.showToast({ message: `已请求转到 ${device.deviceName}` });
      } else {
        promptAction.showToast({ message: '转移失败，请稍后重试' });
      }
    } catch (e) {
      promptAction.showToast({ message: `转移失败: ${(e as Error).message}` });
    }
  }

  /** 注册「来自其它设备的接续请求」回调（aboutToAppear 调用一次）。 */
  private subscribeIncomingContinuation(): void {
    if (this.incomingUnsubscribe) return;
    this.incomingUnsubscribe = ContinuationManager.onIncomingContinuation((req) => {
      const chapterNo = req.session.chapterIndex + 1;
      promptAction.showToast({
        message: `${req.sourceDeviceName}上读到第 ${chapterNo} 章，可在目录跳转接续`,
        duration: 4000,
      });
    });
  }

  private unsubscribeIncomingContinuation(): void {
    if (this.incomingUnsubscribe) {
      this.incomingUnsubscribe();
      this.incomingUnsubscribe = null;
    }
  }

  // ---------- W7-C settings sheet handlers --------------------------------

  /**
   * @StorageProp('app_theme_mode') 变化时被 ArkUI 触发。
   * ThemeService 切换主题时此 callback 会被调用 → 重绘 Canvas（不需要 relayout）。
   */
  private onEffectiveThemeChange(): void {
    // 把 ThemeService 的 effective ('day'/'night'/'sepia') 同步给本地 theme + engine
    const eff = this.effectiveTheme;
    if (eff === 'day' || eff === 'night' || eff === 'sepia') {
      this.theme = eff === 'sepia' ? 'paper' : eff;
      this.engine?.setTheme(eff);
      this.draw();
    }
  }

  /**
   * 保留阅读位置的 relayout：基于 percentComplete 重新定位 pageIndex。
   * 字号 / 行距变化后总页数会变，简单 keep pageIndex 会跳跃。
   */
  private async relayoutPreservingPosition(): Promise<void> {
    const oldPercent = this.pageCount > 0
      ? (this.pageIndex + 1) / this.pageCount
      : 0;
    if (!this.engine) return;
    this.engine.setFontSize(this.fontSize);
    this.engine.setLineHeight(this.lineHeight);
    this.engine.setLayoutProfile({
      pageWidth: this.pageWidth,
      pageHeight: this.pageHeight,
      fontSize: this.fontSize,
      lineHeight: this.lineHeight,
    });
    try {
      const summary = this.engine.layoutHtml(
        this.chapterHtml + (this.chapterCss ? `\n<style>${this.chapterCss}</style>` : ''),
        this.chapterId,
        this.pageWidth,
        this.pageHeight,
        this.fontSize,
      );
      this.pageCount = summary.pageCount;
      const target = Math.max(
        0,
        Math.min(this.pageCount - 1, Math.round(oldPercent * this.pageCount) - 1),
      );
      this.loadPage(target);
    } catch (e) {
      this.errMsg = (e as Error).message ?? '排版失败';
      this.fallbackLocalRender();
    }
  }

  /** ReaderSettingsSheet 字号变化回调 */
  private onSettingsFontSizeChange(size: number): void {
    if (size === this.fontSize) return;
    this.fontSize = size;
    this.relayoutPreservingPosition();
  }

  /** ReaderSettingsSheet 行距变化回调 */
  private onSettingsLineHeightChange(multiplier: number): void {
    if (Math.abs(multiplier - this.lineHeight) < 1e-3) return;
    this.lineHeight = multiplier;
    this.relayoutPreservingPosition();
  }

  /** ReaderSettingsSheet 主题变化回调（ThemeService 已写 SettingsStore） */
  private onSettingsThemeChange(t: ReaderTheme): void {
    this.theme = t;
    // engine 接受 day/night/sepia；'paper' 归一为 sepia；'system' 让 effectiveTheme 推送
    if (t === 'day' || t === 'night') {
      this.engine?.setTheme(t);
    } else if (t === 'paper' || t === 'sepia') {
      this.engine?.setTheme('sepia');
    }
    this.draw();
  }

  /** ReaderSettingsSheet 翻页方式变化回调 */
  private onSettingsPageTurnModeChange(mode: PageTurnMode): void {
    if (this.pageTurnMode === mode) return;
    this.pageTurnMode = mode;
    // 翻页 controller 重置：当前 Canvas + PanGesture 实现是"瞬时翻页"，
    // 三种模式共享同一手势组件，仅在交互动效上有差别（卷页快照 / drag-follow / 整页滚动）。
    // 重新触发一次 draw() 让模式切换立即可见。
    this.draw();
  }

  /** ReaderSettingsSheet 字体变化回调 */
  private onSettingsFontChange(_font: ReaderFont, family: string): void {
    this.fontFamily = family;
    this.draw();
  }

  // ---------- progress / session -----------------------------------------

  private progressDebounceTimer: number | null = null;
  private persistProgressDebounced(): void {
    if (this.progressDebounceTimer !== null) return;
    this.progressDebounceTimer = setTimeout(() => {
      this.progressDebounceTimer = null;
      this.persistProgress();
    }, 800);
  }

  private persistProgress(): void {
    const percent = this.pageCount > 0
      ? ((this.pageIndex + 1) / this.pageCount) * 100
      : 0;
    const local: LocalProgress = {
      bookId: this.bookId,
      chapterId: this.chapterId,
      position: this.pageIndex,
      percent,
      updatedAt: Date.now(),
    };
    ReadingStore.setLastProgress(local);
    ReadingStore.setCurrentBook(this.bookId);

    const dto: ReadingProgressDto = {
      bookId: this.bookId,
      chapterIndex: this.chapterIndex,
      pageIndex: this.pageIndex,
      percent,
      updatedAt: new Date().toISOString(),
    };
    // W7-C6：进入 ProgressSync 队列（debounce 5s + 失败退避 + 持久化崩溃恢复）
    ProgressSync.queueUpdate(this.bookId, dto);
  }

  private startSessionFireAndForget(): void {
    if (this.sessionId) return;
    this.sessionStartedAt = Date.now();
    this.pagesReadInSession = 0;
    ReadingApi.startSession(this.bookId).then((resp) => {
      this.sessionId = resp.sessionId;
    }).catch(() => {
      this.sessionId = null;
    });
  }

  private endSessionFireAndForget(): void {
    const id = this.sessionId;
    if (!id) return;
    this.sessionId = null;
    const duration = Math.max(0, Math.round((Date.now() - this.sessionStartedAt) / 1000));
    ReadingApi.endSession(id, {
      durationSeconds: duration,
      pagesRead: this.pagesReadInSession,
      chapterIndex: this.chapterIndex,
    }).catch(() => {});
  }

  // ---------- W8-C5 TTS 控制 ---------------------------------------------

  /**
   * 启动 TTS：朗读当前页可见文字。
   * 文字来自 currentPage.lines，按行拼成 plain text；句子边界基于 line 的 runs，
   * 提供给 SentenceHighlight。
   */
  private async startTts(text?: string): Promise<void> {
    const speakText = text ?? this.collectPageText();
    if (!speakText) {
      promptAction.showToast({ message: '当前页没有可朗读文字' });
      return;
    }
    try {
      // 重建 sentence rect 列表
      this.sentenceRects = this.buildSentenceRects(speakText);
      this.ttsTotalChars = speakText.length;
      this.ttsCharIndex = 0;
      this.ttsService.setSpeed(this.ttsSpeed);
      const handle = await this.ttsService.speak(speakText, {
        bookId: this.bookId,
        chapterIndex: this.chapterIndex,
        paragraphIndex: 0,
      });
      this.ttsHandle = handle;
      this.ttsPlaying = true;
      this.ttsPaused = false;
      handle.onProgress((idx: number, _total: number) => {
        this.ttsCharIndex = idx;
      });
      handle.onComplete(() => {
        this.ttsPlaying = false;
        this.ttsPaused = false;
        this.ttsHandle = null;
        // 播放结束自动翻下一页继续
        this.nextPage();
      });
      handle.onError((err: Error) => {
        this.ttsPlaying = false;
        this.ttsPaused = false;
        this.ttsHandle = null;
        ToastManager.error(`朗读失败: ${err.message}`);
      });
    } catch (err) {
      ToastManager.error(`朗读启动失败: ${(err as Error).message}`);
    }
  }

  private pauseTts(): void {
    if (!this.ttsHandle) return;
    this.ttsService.pause(this.ttsHandle);
    this.ttsPaused = true;
  }

  private resumeTts(): void {
    if (!this.ttsHandle) return;
    this.ttsService.resume(this.ttsHandle);
    this.ttsPaused = false;
  }

  private stopTts(): void {
    if (this.ttsHandle) {
      this.ttsService.stop(this.ttsHandle);
      this.ttsHandle = null;
    }
    this.ttsPlaying = false;
    this.ttsPaused = false;
    this.ttsCharIndex = 0;
    this.ttsTotalChars = 0;
    this.sentenceRects = [];
  }

  private setTtsSpeed(speed: number): void {
    this.ttsSpeed = speed;
    this.ttsService.setSpeed(speed);
    promptAction.showToast({ message: `朗读速度 ${speed}x` });
  }

  private setTtsVoice(voice: string): void {
    this.ttsService.setVoice(voice);
    this.showVoiceSheet = false;
    promptAction.showToast({ message: '已切换音色' });
  }

  /** 收集当前页所有文字（按 line 顺序拼接，line 间用空格分隔）。 */
  private collectPageText(): string {
    if (!this.currentPage) return '';
    const parts: string[] = [];
    for (const line of this.currentPage.lines) {
      for (const run of line.runs) {
        parts.push(run.text);
      }
    }
    return parts.join(' ').trim();
  }

  /**
   * 把当前页的 line.runs 转成 sentence rect 列表，给 SentenceHighlight 使用。
   * 简化版：按 line 切分，每行一个 sentence rect；起止 charIndex 根据 line 累计字数。
   */
  private buildSentenceRects(speakText: string): SentenceRect[] {
    if (!this.currentPage) return [];
    const rects: SentenceRect[] = [];
    let cursor = 0;
    for (const line of this.currentPage.lines) {
      let lineText = '';
      let xMin = Number.MAX_VALUE;
      let xMax = 0;
      for (const run of line.runs) {
        lineText += run.text;
        xMin = Math.min(xMin, run.x);
        xMax = Math.max(xMax, run.x + run.w);
      }
      lineText = lineText.trim();
      if (!lineText) continue;
      const start = cursor;
      const end = Math.min(speakText.length, cursor + lineText.length + 1); // +1 for join space
      rects.push({
        blockIndex: line.runs.length > 0 ? line.runs[0].blockIndex : 0,
        charOffset: line.runs.length > 0 ? line.runs[0].charOffset : 0,
        charLength: lineText.length,
        x: xMin,
        y: line.y - line.ascent,
        w: Math.max(1, xMax - xMin),
        h: line.h,
        globalCharStart: start,
        globalCharEnd: end,
      });
      cursor = end;
    }
    return rects;
  }

  // W8-A 提供的 SelectionLayer callback 桥接（即使 SelectionLayer 还没接入也保留接口）
  private onTranslateRequest(text: string): void {
    if (!text) return;
    const lang = /[一-鿿]/.test(text) ? 'zh' : 'en';
    const target = lang === 'zh' ? 'en' : 'zh';
    this.translateService.translate(text, lang, target).then((res: TranslateResult) => {
      ToastManager.info(res.translated || '(无译文)', 4000);
    }).catch((err: Error) => {
      ToastManager.error(`翻译失败: ${err.message}`);
    });
  }

  private onTtsReadRequest(text: string): void {
    if (!text) return;
    this.startTts(text);
  }

  // ---------- builders ----------------------------------------------------

  @Builder
  topBar() {
    Row({ space: AppSpacing.sm }) {
      Text('< 返回')
        .fontSize(AppFontSize.sm)
        .fontColor(THEME_MAP[this.theme].text)
        .padding(AppSpacing.xs)
        .onClick(() => RouterService.pop())
      Column({ space: 2 }) {
        Text(this.chapterTitle)
          .fontSize(AppFontSize.sm)
          .fontColor(THEME_MAP[this.theme].text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.pageCount > 0 ? Math.round(((this.pageIndex + 1) / this.pageCount) * 100) : 0}%`)
          .fontSize(AppFontSize.xs)
          .fontColor(THEME_MAP[this.theme].secondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      // W7-C5：目录按钮
      Text('☰')
        .fontSize(AppFontSize.lg)
        .fontColor(THEME_MAP[this.theme].text)
        .padding(AppSpacing.xs)
        .onClick(() => { this.showToc = true; })
      Text('⚙')
        .fontSize(AppFontSize.lg)
        .fontColor(THEME_MAP[this.theme].text)
        .padding(AppSpacing.xs)
        .onClick(() => { this.showSettings = !this.showSettings; })
    }
    .width('100%')
    .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.sm, bottom: AppSpacing.sm })
    .backgroundColor(THEME_MAP[this.theme].bg)
  }

  @Builder
  bottomBar() {
    Row() {
      this.bottomBtn('A-', () => this.adjustFontSize(-1))
      this.bottomBtn('A+', () => this.adjustFontSize(1))
      this.bottomBtn('☀', () => this.setTheme(this.theme === 'day' ? 'night' : 'day'))
      this.bottomBtn('☰', () => { this.showToc = !this.showToc; })
      this.bottomBtn('✎', () => { this.showNotes = !this.showNotes; })
      this.bottomBtn('▶', () => this.startTts())
      this.bottomBtn('?', () => this.openComprehension())
      // W11-C2：分享选中单词到元服务卡片（划词后才显示）
      if (this.explainCtx.word.length > 0) {
        this.bottomBtn('↗', () => this.shareSelectedWord())
        // W13-C2：写入分布式剪贴板（同账号其它设备直接收到）
        this.bottomBtn('⎘', () => this.copySelectedWordToOtherDevice())
      }
      // W13-C3：转到其它设备（仅当存在 active continuation session）
      this.bottomBtn('📲', () => this.openDeviceSelector())
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceAround)
    .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm })
    .backgroundColor(THEME_MAP[this.theme].bg)
  }

  @Builder
  bottomBtn(label: string, onTap: () => void) {
    Text(label)
      .fontSize(AppFontSize.md)
      .fontColor(THEME_MAP[this.theme].text)
      .padding(AppSpacing.sm)
      .onClick(onTap)
  }

  @Builder
  settingsDrawer() {
    Column({ space: AppSpacing.base }) {
      Text('阅读设置').fontSize(AppFontSize.md).fontWeight(AppFontWeight.bold).fontColor(AppColors.textPrimary)
      // 字号
      Row({ space: AppSpacing.sm }) {
        Text('字号').fontSize(AppFontSize.sm).fontColor(AppColors.textSecondary).layoutWeight(1)
        Button('A-').width(40).height(32).onClick(() => this.adjustFontSize(-1))
        Text(`${this.fontSize}`).fontSize(AppFontSize.sm).width(40).textAlign(TextAlign.Center)
        Button('A+').width(40).height(32).onClick(() => this.adjustFontSize(1))
      }.width('100%')
      // 行距
      Row({ space: AppSpacing.sm }) {
        Text('行距').fontSize(AppFontSize.sm).fontColor(AppColors.textSecondary).layoutWeight(1)
        Button('-').width(40).height(32).onClick(() => this.adjustLineHeight(-0.1))
        Text(this.lineHeight.toFixed(1)).fontSize(AppFontSize.sm).width(40).textAlign(TextAlign.Center)
        Button('+').width(40).height(32).onClick(() => this.adjustLineHeight(0.1))
      }.width('100%')
      // 字体
      Row({ space: AppSpacing.sm }) {
        Text('字体').fontSize(AppFontSize.sm).fontColor(AppColors.textSecondary).layoutWeight(1)
        Text('系统').fontSize(AppFontSize.sm)
          .fontColor(this.fontFamily === 'HarmonyOS Sans' ? AppColors.brand : AppColors.textTertiary)
          .padding(AppSpacing.xs)
          .onClick(() => this.setFontFamily('HarmonyOS Sans'))
        Text('阅读').fontSize(AppFontSize.sm)
          .fontColor(this.fontFamily === 'HarmonyOS Reading' ? AppColors.brand : AppColors.textTertiary)
          .padding(AppSpacing.xs)
          .onClick(() => this.setFontFamily('HarmonyOS Reading'))
      }.width('100%')
      // 主题
      Row({ space: AppSpacing.sm }) {
        Text('主题').fontSize(AppFontSize.sm).fontColor(AppColors.textSecondary).layoutWeight(1)
        ForEach(['day', 'paper', 'night'] as ReaderTheme[], (t: ReaderTheme) => {
          Text(t === 'day' ? '日' : t === 'paper' ? '羊皮' : '夜')
            .fontSize(AppFontSize.sm)
            .fontColor(this.theme === t ? AppColors.brand : AppColors.textTertiary)
            .padding(AppSpacing.xs)
            .border({
              width: this.theme === t ? 1 : 0,
              color: AppColors.brand,
              radius: AppRadius.sm,
            })
            .onClick(() => this.setTheme(t))
        })
      }.width('100%')

      Button('关闭').width('100%').height(40)
        .backgroundColor(AppColors.bgSecondary)
        .fontColor(AppColors.textPrimary)
        .borderRadius(AppRadius.base)
        .onClick(() => { this.showSettings = false; })
    }
    .padding(AppSpacing.lg)
    .backgroundColor(AppColors.bgPrimary)
    .borderRadius({ topLeft: AppRadius.xl, topRight: AppRadius.xl })
    .width('100%')
  }

  @Builder
  tocDrawer() {
    Column({ space: AppSpacing.sm }) {
      Text('目录').fontSize(AppFontSize.md).fontWeight(AppFontWeight.bold).fontColor(AppColors.textPrimary)
        .padding(AppSpacing.base)
      List({ space: AppSpacing.xs }) {
        ForEach(this.chapters, (ch: Chapter) => {
          ListItem() {
            Row() {
              Text(ch.title)
                .fontSize(AppFontSize.sm)
                .fontColor(this.chapterIndex === ch.index ? AppColors.brand : AppColors.textPrimary)
                .layoutWeight(1)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.chapterIndex === ch.index) {
                Text('●').fontSize(AppFontSize.xs).fontColor(AppColors.brand)
              }
            }
            .width('100%')
            .padding(AppSpacing.sm)
            .onClick(() => {
              this.showToc = false;
              this.loadChapter(ch.index, 0);
            })
          }
        })
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 1, color: AppColors.divider })
    }
    .height('80%')
    .width('100%')
    .backgroundColor(AppColors.bgPrimary)
    .borderRadius({ topLeft: AppRadius.xl, topRight: AppRadius.xl })
  }

  @Builder
  notesDrawer() {
    Column({ space: AppSpacing.sm }) {
      Text(`笔记 (${this.notes.length})`).fontSize(AppFontSize.md).fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary).padding(AppSpacing.base)
      if (this.notes.length === 0) {
        Text('还没有笔记').fontSize(AppFontSize.sm).fontColor(AppColors.textTertiary)
          .padding(AppSpacing.lg)
      } else {
        List({ space: AppSpacing.xs }) {
          ForEach(this.notes, (n: NoteRecord) => {
            ListItem() {
              Column({ space: AppSpacing.xs }) {
                Text(n.originalText).fontSize(AppFontSize.sm).fontWeight(AppFontWeight.medium)
                  .fontColor(AppColors.textPrimary)
                if (n.noteText) {
                  Text(n.noteText).fontSize(AppFontSize.xs).fontColor(AppColors.textSecondary).maxLines(3)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(AppSpacing.sm)
            }
          })
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: AppColors.divider })
      }
      Button('关闭').width('90%').height(40)
        .backgroundColor(AppColors.bgSecondary)
        .fontColor(AppColors.textPrimary)
        .borderRadius(AppRadius.base)
        .onClick(() => { this.showNotes = false; })
        .margin({ bottom: AppSpacing.base })
    }
    .height('70%')
    .width('100%')
    .backgroundColor(AppColors.bgPrimary)
    .borderRadius({ topLeft: AppRadius.xl, topRight: AppRadius.xl })
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

  @Builder
  errorView() {
    Column({ space: AppSpacing.base }) {
      Text('加载失败').fontSize(AppFontSize.md).fontColor(AppColors.danger)
      Text(this.errMsg).fontSize(AppFontSize.sm).fontColor(AppColors.textTertiary)
      Button('重试').onClick(() => this.bootstrap())
        .backgroundColor(AppColors.brand)
        .fontColor(AppColors.textInverse)
        .borderRadius(AppRadius.base)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** W14-C4：是否走平板双页布局 */
  private isTabletLayout(): boolean {
    if (this.currentBp === Breakpoint.LG || this.currentBp === Breakpoint.XL) return true;
    return this.foldStatus === FoldStatus.EXPAND;
  }

  build() {
    NavDestination() {
      if (this.isTabletLayout()) {
        // W14-C4：平板双页阅读布局；mobile 状态（高亮 / 笔记 / TTS）暂不
        // 在双页布局中暴露，由 ReaderTabletLayout 自管最小态。Settings 仍然
        // 通过 SettingsStore 共享 —— 字号 / 主题修改在 mobile / tablet 切回时立即生效。
        ReaderTabletLayout({ params: this.params })
      } else {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          if (this.toolbarVisible) { this.topBar() }

          Stack() {
            Canvas(this.context)
              .width(this.pageWidth)
              .height(this.pageHeight)
              .backgroundColor(THEME_MAP[this.theme].bg)
              .onReady(() => this.draw())
              .onAreaChange((_old, newArea) => {
                const w = Number(newArea.width);
                const h = Number(newArea.height);
                if (w > 0 && h > 0
                  && (Math.abs(w - this.pageWidth) > 1 || Math.abs(h - this.pageHeight) > 1)) {
                  this.pageWidth = w;
                  this.pageHeight = h;
                  this.relayoutAndRender(this.pageIndex);
                }
              })
              .onClick((e: ClickEvent) => this.onTap(e))
              .gesture(
                GestureGroup(GestureMode.Exclusive,
                  LongPressGesture({ repeat: false, duration: 400 })
                    .onAction((e: GestureEvent) => this.onLongPress(e)),
                  PanGesture({ direction: PanDirection.Horizontal })
                    .onActionEnd((e: GestureEvent) => {
                      const dx = e.offsetX;
                      if (dx < -50) this.nextPage();
                      else if (dx > 50) this.prevPage();
                    }),
                ),
              )

            if (this.loading) { this.loadingOverlay() }
            if (this.errMsg && !this.loading) { this.errorView() }
          }
          .layoutWeight(1)
          .alignContent(Alignment.Center)
          .backgroundColor(THEME_MAP[this.theme].bg)

          if (this.toolbarVisible) { this.bottomBar() }
        }
        .width('100%').height('100%')
        .backgroundColor(THEME_MAP[this.theme].bg)

        // W7-C：阅读视觉设置面板（替代旧 settingsDrawer @Builder）
        ReaderSettingsSheet({
          visible: $showSettings,
          isDark: this.theme === 'night',
          onFontSizeChange: (size: number) => this.onSettingsFontSizeChange(size),
          onLineHeightChange: (m: number) => this.onSettingsLineHeightChange(m),
          onThemeChange: (t: ReaderTheme) => this.onSettingsThemeChange(t),
          onPageTurnModeChange: (m: PageTurnMode) => this.onSettingsPageTurnModeChange(m),
          onFontChange: (f: ReaderFont, family: string) => this.onSettingsFontChange(f, family),
        })
        // W7-C5：章节目录底部弹窗
        ChapterTocSheet({
          visible: $showToc,
          bookSlug: this.bookSlug,
          bookId: this.bookId,
          bookTitle: this.chapterTitle,
          currentChapterIndex: this.chapterIndex,
          isDark: this.theme === 'night',
          onChapterSelect: (idx: number) => this.loadChapter(idx, 0),
        })
        // W13-C3：设备选择 sheet（接续到其它设备）
        DeviceSelectorSheet({
          visible: $showDeviceSelector,
          isDark: this.theme === 'night',
          onSelect: (deviceId: string, device: TrustedDevice) =>
            this.onDeviceSelected(deviceId, device),
        })
        if (this.showNotes) { this.notesDrawer() }
      }
      .width('100%').height('100%')
      } // end else (mobile branch)
    }
    .hideTitleBar(true)
  }
}
