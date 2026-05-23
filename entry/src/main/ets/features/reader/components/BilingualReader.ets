/**
 * BilingualReader.ets — W8 中英双语对照阅读组件
 *
 * 4 种显示模式：
 *   - 'en-only'   仅英文原文
 *   - 'zh-only'   仅中文译文
 *   - 'parallel'  左右分栏对照（左英右中）
 *   - 'inline'    段落穿插（英文段落 → 中文译文 → 英文段落 …）
 *
 * 数据流：
 *   父组件传入 chapterContent（HTML 或纯文本），组件按 <p>...</p>
 *   或换行规则切分为段落数组，每段生成稳定 segmentId（djb2 hash）。
 *   翻译缓存（@Prop translations: Map<segmentId, zhText>）由父组件集中
 *   管理（W8 TranslateService）；未命中则显示「点击翻译」按钮，回调
 *   onTranslateSegment 让父组件去请求翻译。
 *
 * 滚动同步（仅 parallel 模式）：
 *   左右两个 Scroller 互绑 onScroll，通过比例换算保持等高位置同步。
 *
 * 字号：
 *   fontSize 影响双栏正文，行高自动按 1.6 倍计算。
 *
 * 模式切换：
 *   onModeChange 回调通知父组件持久化偏好；模式切换时使用 fade 过渡动画。
 */

import {
  TextColors,
  BgColors,
  AccentColors,
  BorderColors,
  SurfaceColors,
  StateColors,
  useColor,
} from '../../../core/theme/AppColors';
import {
  FontFamily,
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius, MotionDuration, MotionEasing } from '../../../core/theme/AppSpacing';
import { ToastManager } from './Toast';

// ─────────────────────────────────────────────
// 类型导出
// ─────────────────────────────────────────────

/** 双语显示模式 */
export type BilingualMode = 'en-only' | 'zh-only' | 'parallel' | 'inline';

/** 解析后的段落 */
interface Segment {
  /** 稳定 ID（基于内容 hash + index）*/
  id: string;
  /** 英文原文段落 */
  en: string;
  /** 段落 index（用于 fallback 排序） */
  index: number;
}

// ─────────────────────────────────────────────
// 工具函数
// ─────────────────────────────────────────────

/**
 * djb2 hash —— 把段落正文映射成稳定的 32-bit 字符串 ID。
 * 同一段文本在多次渲染、多端、多次冷启动间保持 ID 一致，
 * 便于翻译缓存命中。
 */
function hashSegment(text: string): string {
  let hash = 5381;
  for (let i = 0; i < text.length; i++) {
    hash = ((hash << 5) + hash + text.charCodeAt(i)) | 0;
  }
  // 转无符号 + 补零 8 位 hex
  const u = hash >>> 0;
  return u.toString(16).padStart(8, '0');
}

/**
 * 把章节正文切分成段落数组。
 * 支持两种格式：
 *   - HTML：按 <p>...</p> 抽取
 *   - 纯文本：按双换行 / 单换行兜底
 */
function parseSegments(content: string): Segment[] {
  if (!content || content.length === 0) return [];

  const segments: Segment[] = [];
  const trimmed = content.trim();

  // 优先识别 <p> 标签
  const pMatches = trimmed.match(/<p[^>]*>([\s\S]*?)<\/p>/gi);
  if (pMatches && pMatches.length > 0) {
    pMatches.forEach((raw, idx) => {
      // 剥掉所有 HTML 标签，保留纯文本
      const text = raw.replace(/<[^>]+>/g, '').trim();
      if (text.length === 0) return;
      segments.push({
        id: `${hashSegment(text)}-${idx}`,
        en: text,
        index: idx,
      });
    });
    return segments;
  }

  // 兜底：按双换行切分，再按单换行细分
  const blocks = trimmed
    .split(/\n\s*\n/)
    .map((b) => b.trim())
    .filter((b) => b.length > 0);
  blocks.forEach((block, idx) => {
    segments.push({
      id: `${hashSegment(block)}-${idx}`,
      en: block,
      index: idx,
    });
  });
  return segments;
}

// ─────────────────────────────────────────────
// BilingualReader 组件
// ─────────────────────────────────────────────

@Component
export struct BilingualReader {
  // ── 输入 Props ──
  @Prop bookId: string = '';
  @Prop chapterIndex: number = 0;
  /** 章节正文（HTML 或纯文本）*/
  @Prop @Watch('onContentChange') chapterContent: string = '';
  /** 正文字号 */
  @Prop fontSize: number = 17;
  /** 当前显示模式 */
  @Prop @Watch('onModeWatch') displayMode: BilingualMode = 'en-only';
  /** 翻译缓存：segmentId → 中文译文 */
  @Prop translations: Map<string, string> = new Map<string, string>();
  /** 是否暗色 */
  @Prop isDark: boolean = false;

  // ── 事件 ──
  /** 请求翻译某段（父组件调用 W8 TranslateService）*/
  onTranslateSegment?: (segmentId: string, enText: string) => void;
  /** 模式切换回调 */
  onModeChange?: (mode: BilingualMode) => void;

  // ── 内部状态 ──
  @State private segments: Segment[] = [];
  /** 正在请求翻译中的段 ID（避免重复点击）*/
  @State private translatingIds: Set<string> = new Set<string>();
  /** 模式切换淡入淡出透明度 */
  @State private contentOpacity: number = 1.0;
  /** 滚动同步互锁，避免 onScroll 互相递归触发 */
  private syncing: boolean = false;

  // ── 滚动控制器（parallel 模式左右独立） ──
  private leftScroller: Scroller = new Scroller();
  private rightScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.segments = parseSegments(this.chapterContent);
  }

  /** 章节内容变化 → 重新切分 */
  private onContentChange(): void {
    this.segments = parseSegments(this.chapterContent);
  }

  /** 模式 Prop 变化 → 播放淡入淡出 */
  private onModeWatch(): void {
    this.playFadeAnimation();
  }

  private playFadeAnimation(): void {
    this.contentOpacity = 0.4;
    animateTo({
      duration: MotionDuration.normal,
      curve: MotionEasing.decelerate,
    }, () => {
      this.contentOpacity = 1.0;
    });
  }

  /** 行高 = 字号 × 1.6 */
  private get lineHeight(): number {
    return Math.round(this.fontSize * 1.6);
  }

  /** 中文字号略小一点 */
  private get zhFontSize(): number {
    return Math.max(12, this.fontSize - 1);
  }

  /** 切换模式 */
  private switchMode(next: BilingualMode): void {
    if (next === this.displayMode) return;
    this.displayMode = next;
    this.playFadeAnimation();
    this.onModeChange?.(next);
  }

  /** 请求翻译某段 */
  private requestTranslate(seg: Segment): void {
    if (this.translatingIds.has(seg.id)) return;
    if (this.translations.has(seg.id)) return;
    if (!this.onTranslateSegment) {
      ToastManager.warning('翻译服务未接入');
      return;
    }
    this.translatingIds.add(seg.id);
    this.onTranslateSegment(seg.id, seg.en);
    // 父组件回填 translations 后会触发 @Prop 重新赋值，
    // 这里用 setTimeout 兜底解锁（防止父组件 reject 后永久卡住）
    setTimeout(() => {
      this.translatingIds.delete(seg.id);
    }, 8000);
  }

  /** 重译某段（清掉 translatingIds，再次回调）*/
  private retranslate(seg: Segment): void {
    this.translatingIds.delete(seg.id);
    this.requestTranslate(seg);
  }

  // ─────────────────────────────────────────────
  // Builder 区
  // ─────────────────────────────────────────────

  /** 顶部模式切换栏 */
  @Builder
  private modeSwitcher() {
    Row({ space: Spacing.s1 }) {
      this.modeChip('en-only', '英文')
      this.modeChip('zh-only', '中文')
      this.modeChip('parallel', '对照')
      this.modeChip('inline', '段落穿插')
    }
    .width('100%')
    .padding({
      left: Spacing.s4,
      right: Spacing.s4,
      top: Spacing.s3,
      bottom: Spacing.s3,
    })
    .backgroundColor(useColor(BgColors.secondary, this.isDark))
    .borderRadius(Radius.lg)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  private modeChip(mode: BilingualMode, label: string) {
    Text(label)
      .fontSize(FontSizeToken.footnote)
      .fontFamily(FontFamily.ui)
      .fontWeight(
        this.displayMode === mode
          ? FontWeightToken.semibold
          : FontWeightToken.regular,
      )
      .fontColor(
        this.displayMode === mode
          ? '#FFFFFF'
          : useColor(TextColors.secondary, this.isDark),
      )
      .backgroundColor(
        this.displayMode === mode
          ? useColor(AccentColors.primary, this.isDark)
          : 'transparent',
      )
      .padding({
        left: Spacing.s3,
        right: Spacing.s3,
        top: Spacing.s2,
        bottom: Spacing.s2,
      })
      .borderRadius(Radius.full)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .onClick(() => this.switchMode(mode))
  }

  /** 单段英文 */
  @Builder
  private enParagraph(seg: Segment) {
    Text(seg.en)
      .fontSize(this.fontSize)
      .fontFamily(FontFamily.body)
      .lineHeight(this.lineHeight)
      .fontColor(useColor(TextColors.primary, this.isDark))
      .width('100%')
      .margin({ bottom: Spacing.s4 })
  }

  /** 单段中文（已翻译态） */
  @Builder
  private zhParagraphTranslated(seg: Segment, zh: string) {
    Column({ space: Spacing.s1 }) {
      Text(zh)
        .fontSize(this.zhFontSize)
        .fontFamily(FontFamily.body)
        .lineHeight(Math.round(this.zhFontSize * 1.6))
        .fontColor(useColor(TextColors.secondary, this.isDark))
        .width('100%')

      // 重译按钮
      Row({ space: Spacing.s2 }) {
        Text('AI 翻译')
          .fontSize(FontSizeToken.caption2)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
        Text('· 重译')
          .fontSize(FontSizeToken.caption2)
          .fontColor(useColor(AccentColors.primary, this.isDark))
          .onClick(() => this.retranslate(seg))
      }
      .width('100%')
    }
    .width('100%')
    .padding(Spacing.s3)
    .backgroundColor(useColor(BgColors.secondary, this.isDark))
    .borderRadius(Radius.md)
    .margin({ bottom: Spacing.s4 })
  }

  /** 单段中文（未翻译态，显示「点击翻译」按钮） */
  @Builder
  private zhParagraphPending(seg: Segment) {
    Row({ space: Spacing.s2 }) {
      if (this.translatingIds.has(seg.id)) {
        LoadingProgress()
          .width(14)
          .height(14)
          .color(useColor(AccentColors.primary, this.isDark))
        Text('翻译中…')
          .fontSize(FontSizeToken.footnote)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
      } else {
        Text('点击翻译')
          .fontSize(FontSizeToken.footnote)
          .fontColor(useColor(AccentColors.primary, this.isDark))
          .fontWeight(FontWeightToken.medium)
      }
    }
    .width('100%')
    .padding(Spacing.s3)
    .backgroundColor(useColor(BgColors.secondary, this.isDark))
    .borderRadius(Radius.md)
    .border({
      width: 1,
      color: useColor(BorderColors.primary, this.isDark),
      style: BorderStyle.Dashed,
    })
    .margin({ bottom: Spacing.s4 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.requestTranslate(seg))
  }

  /** 选择渲染中文段落（已译 / 未译） */
  @Builder
  private zhParagraph(seg: Segment) {
    if (this.translations.has(seg.id)) {
      this.zhParagraphTranslated(seg, this.translations.get(seg.id) ?? '')
    } else {
      this.zhParagraphPending(seg)
    }
  }

  // ── en-only / zh-only：单栏 Scroll ──
  @Builder
  private singleColumnView(showEn: boolean) {
    Scroll() {
      Column() {
        ForEach(this.segments, (seg: Segment) => {
          if (showEn) {
            this.enParagraph(seg)
          } else {
            this.zhParagraph(seg)
          }
        }, (seg: Segment) => seg.id)
      }
      .width('100%')
      .padding(Spacing.s4)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  // ── parallel：左右分栏 ──
  @Builder
  private parallelView() {
    Row() {
      // 左：英文
      Scroll(this.leftScroller) {
        Column() {
          ForEach(this.segments, (seg: Segment) => {
            this.enParagraph(seg)
          }, (seg: Segment) => `${seg.id}-en`)
        }
        .width('100%')
        .padding(Spacing.s3)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .onScroll(() => {
        if (this.syncing) return;
        this.syncing = true;
        try {
          const offset = this.leftScroller.currentOffset();
          // 双栏直接同步等量偏移；不同高度时仍能保持视觉相对位置
          this.rightScroller.scrollTo({
            xOffset: 0,
            yOffset: offset?.yOffset ?? 0,
            animation: false,
          });
        } finally {
          this.syncing = false;
        }
      })

      // 分割线
      Column()
        .width(0.5)
        .height('100%')
        .backgroundColor(useColor(SurfaceColors.divider, this.isDark))

      // 右：中文
      Scroll(this.rightScroller) {
        Column() {
          ForEach(this.segments, (seg: Segment) => {
            this.zhParagraph(seg)
          }, (seg: Segment) => `${seg.id}-zh`)
        }
        .width('100%')
        .padding(Spacing.s3)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .onScroll(() => {
        if (this.syncing) return;
        this.syncing = true;
        try {
          const offset = this.rightScroller.currentOffset();
          this.leftScroller.scrollTo({
            xOffset: 0,
            yOffset: offset?.yOffset ?? 0,
            animation: false,
          });
        } finally {
          this.syncing = false;
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(VerticalAlign.Top)
  }

  // ── inline：段落穿插 ──
  @Builder
  private inlineView() {
    Scroll() {
      Column() {
        ForEach(this.segments, (seg: Segment) => {
          // 每个段落：英文 + 紧随其后的中文
          Column() {
            this.enParagraph(seg)
            this.zhParagraph(seg)
          }
          .width('100%')
        }, (seg: Segment) => `${seg.id}-inline`)
      }
      .width('100%')
      .padding(Spacing.s4)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  build() {
    Column() {
      // 顶部模式切换
      this.modeSwitcher()

      // 内容区（带淡入淡出）
      Column() {
        if (this.segments.length === 0) {
          // 空态
          Column() {
            Text('暂无章节内容')
              .fontSize(FontSizeToken.callout)
              .fontColor(useColor(TextColors.tertiary, this.isDark))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.displayMode === 'en-only') {
          this.singleColumnView(true)
        } else if (this.displayMode === 'zh-only') {
          this.singleColumnView(false)
        } else if (this.displayMode === 'parallel') {
          this.parallelView()
        } else {
          this.inlineView()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .opacity(this.contentOpacity)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(useColor(BgColors.primary, this.isDark))
  }
}
