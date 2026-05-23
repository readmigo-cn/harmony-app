/**
 * Typesetting native bridge wrapper.
 *
 * 与 native 侧绑定关系：
 *   - C++ 静态库          https://gitee.com/readmigo/readmigo-typesetting  (engine.h / page.h / interaction.h)
 *   - NAPI 桥接            https://gitee.com/readmigo/readmigo-napi-bridge  (src/typesetting_napi.cpp)
 *   - 链接产物             entry/libs/arm64-v8a/libreadmigo_native.so
 *
 * NAPI 暴露在 `libreadmigo_native.so` 上的子命名空间 `typesetting`，本文件提供
 * TypeScript-friendly 的强类型封装。`.so` 未编入 HAP 时自动降级到 mock 实现，
 * 让 Reader 页面在 Canvas 上不依赖 native 也能跑通。
 *
 * 切换到真实 .so 步骤：
 *   1. DevEco Studio Build → Make HAP，确认 entry/libs/arm64-v8a/libreadmigo_native.so 已生成
 *   2. 把 NATIVE_AVAILABLE 改为 true
 *   3. tryLoadNative() 仍会捕获加载失败并 fallback 到 mock，所以即使 .so 损坏也不会闪退
 */

// 是否启用真实 native 引擎。.so 进 HAP 后改为 true 即可。
let NATIVE_AVAILABLE: boolean = false;

// ---------------------------------------------------------------------------
// 公共类型 —— 供 Reader 页 / TTS / 长按选择等业务模块复用
// ---------------------------------------------------------------------------

/** 单条 TextRun（page.h: TextRun 的 ArkTS 镜像）。 */
export interface TextRun {
  x: number;
  y: number;
  w: number;
  fontSize: number;
  blockIndex: number;
  inlineIndex: number;
  charOffset: number;
  charLength: number;
  isLink: boolean;
  text: string;
}

/** 单条 Line（page.h: Line 的 ArkTS 镜像）。 */
export interface TextLine {
  x: number;
  y: number;
  w: number;
  h: number;
  ascent: number;
  descent: number;
  runs: TextRun[];
}

/** 非文字装饰元素（HR、图片占位、表格边框）。 */
export interface PageDecoration {
  type: 'hr' | 'img' | 'table';
  x: number;
  y: number;
  w: number;
  h: number;
  src?: string;
  alt?: string;
}

/** 渲染好的一页（renderPage 返回；与 page.h:Page 对应）。 */
export interface TypesetPage {
  pageIndex: number;
  width: number;
  height: number;
  contentX: number;
  contentY: number;
  contentWidth: number;
  contentHeight: number;
  firstBlockIndex: number;
  lastBlockIndex: number;
  lines: TextLine[];
  decorations: PageDecoration[];
}

/** RenderedPage 别名，对外暴露给上层 Canvas 渲染器。 */
export type RenderedPage = TypesetPage;

/** 章节锚点。getChapterAnchors 返回。 */
export interface ChapterAnchor {
  pageIndex: number;
  firstBlockIndex: number;
  lastBlockIndex: number;
}

/** 命中测试结果（hitTest / findWordAt）。 */
export interface HitResult {
  blockIndex: number;
  inlineIndex: number;
  charOffset: number;
  charLength: number;
  text: string;
}

/** word selection（findWordAt 用，比 HitResult 更语义化的别名）。 */
export type WordSelection = HitResult;

/** sentence selection（findSentenceAt 用）。 */
export interface SentenceSelection {
  blockIndex: number;
  charOffset: number;
  charLength: number;
  text: string;
}

/** layout 一次后的 summary（页数 / 块数 / warning 数）。 */
export interface LayoutSummary {
  pageCount: number;
  totalBlocks: number;
  warningCount: number;
}

/** 文档元信息（loadDocument 返回）。 */
export interface DocumentMetadata {
  chapterId: string;
  totalBlocks: number;
  warningCount: number;
  language?: string;
}

/** 单段文字样式（measureText 入参）。 */
export interface TextStyle {
  fontSize: number;
  fontFamily?: string;
  fontWeight?: 'normal' | 'bold' | number;
  fontStyle?: 'normal' | 'italic';
  letterSpacing?: number;
  lineHeight?: number;
}

/** measureText 返回：粗略宽 / 高 / ascent / descent，单位 px。 */
export interface TextMetrics {
  width: number;
  height: number;
  ascent: number;
  descent: number;
}

/** 引擎初始化配置。 */
export interface EngineConfig {
  defaultLocale?: string;
  fontScale?: number;
  lineHeightMultiplier?: number;
}

/** 排版 profile：屏幕尺寸 + 安全区 + 期望字号。 */
export interface LayoutProfile {
  pageWidth: number;
  pageHeight: number;
  safeTop?: number;
  safeBottom?: number;
  safeLeft?: number;
  safeRight?: number;
  fontSize?: number;
  lineHeight?: number;
}

// ---------------------------------------------------------------------------
// Native 模块加载 —— libreadmigo_native.so 的 typesetting 子命名空间
// ---------------------------------------------------------------------------

/** 与 https://gitee.com/readmigo/readmigo-napi-bridge (src/typesetting_napi.cpp) 暴露的 C-side 函数对应。 */
interface NativeTypesettingModule {
  createTypesettingEngine(config?: EngineConfig): object;
  destroyTypesettingEngine(handle: object): void;
  layoutHtml(handle: object, html: string, chapterId: string, w: number, h: number, fs?: number): LayoutSummary;
  getPageJson(handle: object, chapterId: string, pageIndex: number): string | null;
  getChapterAnchorsJson(handle: object, chapterId: string): string | null;
  hitTestJson(handle: object, chapterId: string, pageIndex: number, x: number, y: number): string | null;
}

let cachedNativeModule: NativeTypesettingModule | null = null;

function tryLoadNative(): NativeTypesettingModule | null {
  if (cachedNativeModule) return cachedNativeModule;
  if (!NATIVE_AVAILABLE) return null;
  try {
    // libreadmigo_native.so 在 HAP 中以 NAPI 形式注册。
    // 顶层 module 含 `typesetting` 子命名空间。
    // @ts-ignore — .so 尚未链接进 HAP 时此 import 会失败
    const top: { typesetting?: NativeTypesettingModule } | null =
      typeof globalThis['requireNapi'] === 'function'
        ? globalThis['requireNapi']('libreadmigo_native.so')
        : null;
    const mod = top?.typesetting ?? null;
    if (mod && typeof mod.createTypesettingEngine === 'function') {
      cachedNativeModule = mod;
      return mod;
    }
  } catch (_e) {
    // fall through to mock
  }
  NATIVE_AVAILABLE = false;
  return null;
}

// ---------------------------------------------------------------------------
// TypesettingEngine —— 强类型封装，统一 native + mock
// ---------------------------------------------------------------------------

/**
 * 排版引擎主入口。一个实例对应一本书的一段 reading session，内部缓存最近 5 章
 * 的 LayoutResult（C++ Engine::kMaxChapters）。所有方法均为线程安全（在
 * native 侧由 InteractionManager 保证只读查询安全）。
 */
export class TypesettingEngine {
  private handle: object | null = null;
  private mod: NativeTypesettingModule | null = null;
  private mockCache: Map<string, TypesetPage[]> = new Map();
  private theme: 'day' | 'night' | 'sepia' = 'day';
  private fontSize: number = 17;
  private lineHeight: number = 1.6;
  private profile: LayoutProfile = { pageWidth: 360, pageHeight: 640 };
  private activeChapterId: string = 'default';
  private destroyed: boolean = false;

  /**
   * @param config 可选初始化配置：locale / fontScale / lineHeightMultiplier。
   *   不传时使用 native 默认值（zh-CN / 1.0 / 1.35）。
   */
  constructor(config?: EngineConfig) {
    const native = tryLoadNative();
    if (native) {
      try {
        this.handle = native.createTypesettingEngine(config);
        this.mod = native;
      } catch (_e) {
        // native 初始化失败 → 自动降级 mock
        this.handle = null;
        this.mod = null;
      }
    }
    if (config?.lineHeightMultiplier) this.lineHeight = config.lineHeightMultiplier;
  }

  /**
   * 装载一段 HTML（可选 inline CSS），异步排版后返回章节元信息。
   *
   * @param html  完整 HTML 片段（不需要 <html><body>，但 <p>/<h1>/<img> 必须闭合）
   * @param css   可选 inline 样式表，与 html 合并参与样式解析
   * @returns DocumentMetadata —— 总块数 + warning 数 + 语言
   * @throws  Error('engine_destroyed') 若已 destroy
   */
  async loadDocument(html: string, css?: string): Promise<DocumentMetadata> {
    this.assertAlive();
    return new Promise<DocumentMetadata>((resolve, reject) => {
      try {
        const summary = this.layoutHtml(html, this.activeChapterId, this.profile.pageWidth, this.profile.pageHeight, this.fontSize);
        resolve({
          chapterId: this.activeChapterId,
          totalBlocks: summary.totalBlocks,
          warningCount: summary.warningCount,
          language: 'en',
        });
      } catch (e) {
        reject(e instanceof Error ? e : new Error(String(e)));
      }
    });
  }

  /** 设置 LayoutProfile（屏幕尺寸 / 安全区 / 期望字号）。后续 layout 生效。 */
  setLayoutProfile(profile: LayoutProfile): void {
    this.profile = profile;
    if (profile.fontSize) this.fontSize = profile.fontSize;
    if (profile.lineHeight) this.lineHeight = profile.lineHeight;
  }

  /** 触发当前 active chapter 的 relayout，返回页数。 */
  async layout(): Promise<number> {
    this.assertAlive();
    // 真实 native 侧由 loadDocument 已 layout；此处只读取页数。
    const pages = this.mockCache.get(this.activeChapterId);
    if (pages) return pages.length;
    const anchors = this.getChapterAnchors(this.activeChapterId);
    return anchors.length;
  }

  /**
   * 渲染指定页码的页数据。
   * @param pageIndex 0-based 页码
   * @returns RenderedPage —— 含 lines/runs/decorations，可直接喂给 Canvas
   * @throws  Error('page_not_found') 若 pageIndex 越界
   */
  async renderPage(pageIndex: number): Promise<RenderedPage> {
    this.assertAlive();
    const page = this.getPage(this.activeChapterId, pageIndex);
    if (!page) throw new Error('page_not_found');
    return page;
  }

  /**
   * 测量一段文字的渲染尺寸（不做换行，返回单行宽 + 行高）。
   * 同步实现，主要给上层 ArkUI 计算容器尺寸用。
   */
  measureText(text: string, style: TextStyle): TextMetrics {
    const fs = style.fontSize;
    const lh = (style.lineHeight ?? this.lineHeight) * fs;
    // CJK 与拉丁字符的平均宽估算（仅 mock；native 会调 PlatformAdapter::measureText）
    const avgRatio = /[一-鿿]/.test(text) ? 1.0 : 0.55;
    return {
      width: text.length * fs * avgRatio + (style.letterSpacing ?? 0) * Math.max(0, text.length - 1),
      height: lh,
      ascent: fs * 0.8,
      descent: fs * 0.2,
    };
  }

  /** 命中测试：返回坐标点对应的英文 word（含字符边界）。 */
  findWordAt(pageIndex: number, x: number, y: number): WordSelection | null {
    return this.hitTest(this.activeChapterId, pageIndex, x, y);
  }

  /** 命中测试：返回坐标点对应的整句（mock 用 word 兜底）。 */
  findSentenceAt(pageIndex: number, x: number, y: number): SentenceSelection | null {
    const word = this.findWordAt(pageIndex, x, y);
    if (!word) return null;
    return {
      blockIndex: word.blockIndex,
      charOffset: word.charOffset,
      charLength: word.charLength,
      text: word.text,
    };
  }

  /** 切换主题：影响背景 / 前景色，但不重排（内部保留状态供 Reader 读取）。 */
  setTheme(theme: 'day' | 'night' | 'sepia'): void {
    this.theme = theme;
  }

  /** 获取当前 theme（Reader 渲染用）。 */
  getTheme(): 'day' | 'night' | 'sepia' {
    return this.theme;
  }

  /** 设置全局字号；下次 layout 生效。 */
  setFontSize(size: number): void {
    this.fontSize = Math.max(10, Math.min(36, size));
  }

  /** 设置行高倍数（line-height multiplier，CSS 等价物）。 */
  setLineHeight(height: number): void {
    this.lineHeight = Math.max(1.0, Math.min(3.0, height));
  }

  /** 释放 native 资源；调用后任何方法都将抛 'engine_destroyed'。 */
  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    if (this.handle && this.mod) {
      try {
        this.mod.destroyTypesettingEngine(this.handle);
      } catch (_e) {
        // ignore
      }
    }
    this.handle = null;
    this.mod = null;
    this.mockCache.clear();
  }

  // ---------- Legacy / low-level API（Reader.ets 直接使用） -----------------

  /**
   * 直接对 chapterId 做 layout（同步）。
   * @returns LayoutSummary —— 页数 + 块数 + warning 数
   */
  layoutHtml(html: string, chapterId: string, width: number, height: number, fontSize?: number): LayoutSummary {
    this.assertAlive();
    this.activeChapterId = chapterId;
    if (fontSize) this.fontSize = fontSize;
    if (this.handle && this.mod) {
      return this.mod.layoutHtml(this.handle, html, chapterId, width, height, fontSize ?? this.fontSize);
    }
    return this.mockLayout(html, chapterId, width, height, fontSize ?? this.fontSize);
  }

  /** 取已 layout 的某一页（同步）。 */
  getPage(chapterId: string, pageIndex: number): TypesetPage | null {
    this.assertAlive();
    if (this.handle && this.mod) {
      const json = this.mod.getPageJson(this.handle, chapterId, pageIndex);
      if (!json) return null;
      try {
        return JSON.parse(json) as TypesetPage;
      } catch (_e) {
        return null;
      }
    }
    const pages = this.mockCache.get(chapterId);
    if (!pages || pageIndex < 0 || pageIndex >= pages.length) return null;
    return pages[pageIndex];
  }

  /** 取章节所有页的锚点（同步）。 */
  getChapterAnchors(chapterId: string): ChapterAnchor[] {
    this.assertAlive();
    if (this.handle && this.mod) {
      const json = this.mod.getChapterAnchorsJson(this.handle, chapterId);
      if (!json) return [];
      try {
        return JSON.parse(json) as ChapterAnchor[];
      } catch (_e) {
        return [];
      }
    }
    const pages = this.mockCache.get(chapterId);
    if (!pages) return [];
    return pages.map((p): ChapterAnchor => ({
      pageIndex: p.pageIndex,
      firstBlockIndex: p.firstBlockIndex,
      lastBlockIndex: p.lastBlockIndex,
    }));
  }

  /** 命中测试（同步）。 */
  hitTest(chapterId: string, pageIndex: number, x: number, y: number): HitResult | null {
    this.assertAlive();
    if (this.handle && this.mod) {
      const json = this.mod.hitTestJson(this.handle, chapterId, pageIndex, x, y);
      if (!json) return null;
      try {
        return JSON.parse(json) as HitResult;
      } catch (_e) {
        return null;
      }
    }
    return this.mockHitTest(chapterId, pageIndex, x, y);
  }

  // ---------- 内部辅助 ------------------------------------------------------

  private assertAlive(): void {
    if (this.destroyed) throw new Error('engine_destroyed');
  }

  /** 极简 mock 排版（用于 .so 缺失时 Reader 仍可跑通）。 */
  private mockLayout(html: string, chapterId: string, width: number, height: number, fontSize: number): LayoutSummary {
    const fs = fontSize;
    const lh = fs * this.lineHeight;
    const margin = 24;
    const contentW = width - margin * 2;
    const contentH = height - margin * 2;

    const paragraphs = html
      .replace(/<[^>]+>/g, '\n')
      .split(/\n+/)
      .map((s) => s.trim())
      .filter((s) => s.length > 0);

    const pages: TypesetPage[] = [];
    let pageIndex = 0;
    let cursorY = margin;
    let blockIdx = 0;
    let firstBlockOnPage = 0;
    let currentPage: TypesetPage = TypesettingEngine.makeEmptyPage(pageIndex, width, height, margin, contentW, contentH, firstBlockOnPage);

    for (const text of paragraphs) {
      const charsPerLine = Math.max(10, Math.floor(contentW / (fs * 0.55)));
      const lines = Math.max(1, Math.ceil(text.length / charsPerLine));

      for (let li = 0; li < lines; li++) {
        if (cursorY + lh > margin + contentH) {
          currentPage.lastBlockIndex = blockIdx;
          pages.push(currentPage);
          pageIndex++;
          firstBlockOnPage = blockIdx;
          cursorY = margin;
          currentPage = TypesettingEngine.makeEmptyPage(pageIndex, width, height, margin, contentW, contentH, firstBlockOnPage);
        }
        const slice = text.slice(li * charsPerLine, (li + 1) * charsPerLine);
        const line: TextLine = {
          x: margin,
          y: cursorY + fs,
          w: slice.length * fs * 0.55,
          h: lh,
          ascent: fs * 0.8,
          descent: fs * 0.2,
          runs: [{
            x: margin,
            y: cursorY + fs,
            w: slice.length * fs * 0.55,
            fontSize: fs,
            blockIndex: blockIdx,
            inlineIndex: 0,
            charOffset: li * charsPerLine,
            charLength: slice.length,
            isLink: false,
            text: slice,
          }],
        };
        currentPage.lines.push(line);
        cursorY += lh;
      }
      blockIdx++;
    }
    if (currentPage.lines.length > 0) {
      currentPage.lastBlockIndex = blockIdx;
      pages.push(currentPage);
    }

    this.mockCache.set(chapterId, pages);
    return { pageCount: pages.length, totalBlocks: blockIdx, warningCount: 0 };
  }

  private mockHitTest(chapterId: string, pageIndex: number, x: number, y: number): HitResult | null {
    const page = this.getPage(chapterId, pageIndex);
    if (!page) return null;
    for (const line of page.lines) {
      if (y < line.y - line.ascent || y > line.y + line.descent) continue;
      for (const run of line.runs) {
        if (x < run.x || x > run.x + run.w) continue;
        let charIdx = 0;
        if (run.charLength > 0 && run.w > 0) {
          const ratio = (x - run.x) / run.w;
          charIdx = Math.floor(ratio * run.charLength);
          if (charIdx >= run.text.length) charIdx = run.text.length - 1;
          if (charIdx < 0) charIdx = 0;
        }
        const bounds = TypesettingEngine.findWordBounds(run.text, charIdx);
        return {
          blockIndex: run.blockIndex,
          inlineIndex: run.inlineIndex,
          charOffset: run.charOffset + bounds.start,
          charLength: bounds.length,
          text: run.text.slice(bounds.start, bounds.start + bounds.length),
        };
      }
    }
    return null;
  }

  private static findWordBounds(text: string, charIdx: number): { start: number; length: number } {
    if (!text) return { start: 0, length: 0 };
    if (charIdx < 0) charIdx = 0;
    if (charIdx >= text.length) charIdx = text.length - 1;

    const isWordChar = (c: string): boolean => /[A-Za-z'\-]/.test(c);

    if (!isWordChar(text[charIdx])) {
      let found = false;
      for (let d = 1; d <= 8 && !found; d++) {
        if (charIdx - d >= 0 && isWordChar(text[charIdx - d])) {
          charIdx -= d;
          found = true;
        } else if (charIdx + d < text.length && isWordChar(text[charIdx + d])) {
          charIdx += d;
          found = true;
        }
      }
      if (!found) return { start: charIdx, length: 1 };
    }

    let start = charIdx;
    while (start > 0 && isWordChar(text[start - 1])) start--;
    let end = charIdx;
    while (end + 1 < text.length && isWordChar(text[end + 1])) end++;
    return { start, length: end - start + 1 };
  }

  private static makeEmptyPage(
    pageIndex: number, w: number, h: number, margin: number, cw: number, ch: number, firstBlock: number,
  ): TypesetPage {
    return {
      pageIndex,
      width: w,
      height: h,
      contentX: margin,
      contentY: margin,
      contentWidth: cw,
      contentHeight: ch,
      firstBlockIndex: firstBlock,
      lastBlockIndex: firstBlock,
      lines: [],
      decorations: [],
    };
  }
}

// ---------------------------------------------------------------------------
// 工厂函数 —— 兼容旧 import 风格（Reader.ets 在用）
// ---------------------------------------------------------------------------

/** 创建 TypesettingEngine 实例。等价于 `new TypesettingEngine()`。 */
export function createTypesettingEngine(config?: EngineConfig): TypesettingEngine {
  return new TypesettingEngine(config);
}
