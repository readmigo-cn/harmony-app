/**
 * SentenceHighlight.ets — W8-C6 句子高亮 overlay
 *
 * 职责：在 Reader 的 Canvas 之上绘制一层半透明黄色高亮框，跟随 TTS 当前播放
 * charIndex 实时移动；过渡 200ms ease-in-out；高亮移出视口时通过
 * onPageTurnNeeded 回调请求 Reader 翻页。
 *
 * 与 typesetting engine 的协作：
 *   - Reader 把当前 page 的 sentence range list 传进来（{ blockIndex, charOffset,
 *     charLength, rect }），SentenceHighlight 根据 charIndex 找到包含它的句子矩形
 *     并 draw。
 *   - rect 由 Reader 调 engine.getRectsForRange / 自带 line.runs 计算得出，
 *     避免本组件再重复跑 hitTest。
 *
 * 暂停时高亮静止；resume 时通过 charIndex 变化继续动画。
 *
 * 实现要点：
 *   - 用 Canvas 而不是 Stack + 多个 absolute Box，避免 ArkUI diff 抖动
 *   - 触摸穿透：本组件不接收 click/gesture，只是叠加显示层
 */

import { AppColors } from '../../../core/theme/AppColors';

/** 单个句子矩形。Reader 计算后传入。 */
export interface SentenceRect {
  blockIndex: number;
  charOffset: number;
  charLength: number;
  /** 屏幕坐标（vp） */
  x: number;
  y: number;
  w: number;
  h: number;
  /** 该 sentence 起点对应的全局 charIndex（含本句之前所有字符） */
  globalCharStart: number;
  /** 该 sentence 结尾对应的全局 charIndex（exclusive） */
  globalCharEnd: number;
}

/** 高亮渲染配置 */
export interface SentenceHighlightTheme {
  /** 高亮填充色（半透明） */
  fill: string;
  /** 边框色（可选） */
  stroke?: string;
  /** 边框宽度，0 表示无 */
  strokeWidth: number;
  /** 圆角 */
  radius: number;
}

const DEFAULT_THEME: SentenceHighlightTheme = {
  fill: 'rgba(255, 235, 59, 0.35)',
  stroke: 'rgba(255, 193, 7, 0.55)',
  strokeWidth: 1.5,
  radius: 4,
};

@Component
export struct SentenceHighlight {
  /** 是否激活：TTS playing 时为 true，stopped 时为 false（false 直接清空） */
  @Prop active: boolean = false;
  /** 当前播放字符位置（全局 charIndex，含 page 之前已播过的字符） */
  @Prop charIndex: number = 0;
  /** 总字符数（用于计算翻页边界） */
  @Prop totalChars: number = 0;
  /** Reader 当前页 index（变化时清掉旧 sentence rect） */
  @Prop pageIndex: number = 0;
  /** 当前页所有 sentence 矩形 */
  @Prop sentenceRects: SentenceRect[] = [];
  /** 视口尺寸（用于 Canvas 大小） */
  @Prop viewWidth: number = 360;
  @Prop viewHeight: number = 600;
  /** 主题色，外部可覆盖 */
  @Prop theme: SentenceHighlightTheme = DEFAULT_THEME;

  /** 当 charIndex 移出当前页 sentence range，要求 Reader 翻页 */
  onPageTurnNeeded: (newPageIndex: number) => void = () => {};

  // 内部 Canvas 上下文
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  // 上一帧绘制的高亮矩形，用于平滑过渡
  @State private animatedRect: SentenceRect | null = null;
  // 动画帧句柄
  private rafTimer: number = -1;
  private animDuration: number = 200; // ms

  aboutToAppear(): void {
    this.recompute();
  }

  aboutToDisappear(): void {
    this.cancelAnim();
  }

  private recompute(): void {
    if (!this.active || this.sentenceRects.length === 0) {
      this.animatedRect = null;
      this.draw();
      return;
    }
    const target = this.findRectForChar(this.charIndex);
    if (!target) {
      // 当前 charIndex 已超出本页 → 请求翻页
      const lastRect = this.sentenceRects[this.sentenceRects.length - 1];
      if (lastRect && this.charIndex >= lastRect.globalCharEnd) {
        this.onPageTurnNeeded(this.pageIndex + 1);
      }
      return;
    }
    this.animateTo(target);
  }

  private findRectForChar(idx: number): SentenceRect | null {
    for (const r of this.sentenceRects) {
      if (idx >= r.globalCharStart && idx < r.globalCharEnd) return r;
    }
    return null;
  }

  /**
   * 200ms ease-in-out 过渡到目标矩形。简易实现：直接用 ArkUI animateTo 修改
   * @State，再在 onReady/draw 重画。
   */
  private animateTo(target: SentenceRect): void {
    this.cancelAnim();
    const from = this.animatedRect;
    if (!from) {
      this.animatedRect = target;
      this.draw();
      return;
    }
    const start = Date.now();
    const tick = (): void => {
      const t = Math.min(1, (Date.now() - start) / this.animDuration);
      const e = SentenceHighlight.easeInOut(t);
      this.animatedRect = {
        blockIndex: target.blockIndex,
        charOffset: target.charOffset,
        charLength: target.charLength,
        globalCharStart: target.globalCharStart,
        globalCharEnd: target.globalCharEnd,
        x: from.x + (target.x - from.x) * e,
        y: from.y + (target.y - from.y) * e,
        w: from.w + (target.w - from.w) * e,
        h: from.h + (target.h - from.h) * e,
      };
      this.draw();
      if (t < 1) {
        this.rafTimer = setTimeout(tick, 16) as unknown as number;
      } else {
        this.rafTimer = -1;
      }
    };
    tick();
  }

  private cancelAnim(): void {
    if (this.rafTimer !== -1) {
      clearTimeout(this.rafTimer);
      this.rafTimer = -1;
    }
  }

  private static easeInOut(t: number): number {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
  }

  /** 把当前 animatedRect 画到 Canvas 上。 */
  private draw(): void {
    const ctx = this.context;
    const w = this.viewWidth;
    const h = this.viewHeight;
    ctx.clearRect(0, 0, w, h);
    if (!this.active) return;
    const rect = this.animatedRect;
    if (!rect) return;
    const r = Math.max(0, this.theme.radius);
    ctx.fillStyle = this.theme.fill;
    SentenceHighlight.fillRoundedRect(ctx, rect.x, rect.y, rect.w, rect.h, r);
    if (this.theme.strokeWidth > 0 && this.theme.stroke) {
      ctx.strokeStyle = this.theme.stroke;
      ctx.lineWidth = this.theme.strokeWidth;
      SentenceHighlight.strokeRoundedRect(ctx, rect.x, rect.y, rect.w, rect.h, r);
    }
  }

  private static fillRoundedRect(
    ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number,
  ): void {
    const rr = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + rr, y);
    ctx.lineTo(x + w - rr, y);
    ctx.arcTo(x + w, y, x + w, y + rr, rr);
    ctx.lineTo(x + w, y + h - rr);
    ctx.arcTo(x + w, y + h, x + w - rr, y + h, rr);
    ctx.lineTo(x + rr, y + h);
    ctx.arcTo(x, y + h, x, y + h - rr, rr);
    ctx.lineTo(x, y + rr);
    ctx.arcTo(x, y, x + rr, y, rr);
    ctx.closePath();
    ctx.fill();
  }

  private static strokeRoundedRect(
    ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number,
  ): void {
    const rr = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + rr, y);
    ctx.lineTo(x + w - rr, y);
    ctx.arcTo(x + w, y, x + w, y + rr, rr);
    ctx.lineTo(x + w, y + h - rr);
    ctx.arcTo(x + w, y + h, x + w - rr, y + h, rr);
    ctx.lineTo(x + rr, y + h);
    ctx.arcTo(x, y + h, x, y + h - rr, rr);
    ctx.lineTo(x, y + rr);
    ctx.arcTo(x, y, x + rr, y, rr);
    ctx.closePath();
    ctx.stroke();
  }

  build() {
    Canvas(this.context)
      .width(this.viewWidth)
      .height(this.viewHeight)
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.Transparent)
      .onReady(() => {
        this.recompute();
      })
      .onAreaChange((_old, newArea) => {
        const w = Number(newArea.width);
        const h = Number(newArea.height);
        if (w > 0 && h > 0) {
          this.viewWidth = w;
          this.viewHeight = h;
          this.draw();
        }
      })
  }
}
