/**
 * SelectionLayer — 选区高亮 + 工具栏（叠加在 Reader Canvas 之上）
 *
 * 行为：
 *   - 长按（400ms）触发 word 选区
 *   - 双击触发 sentence 选区
 *   - 三击触发 paragraph 选区（mock：取整 block 文本）
 *   - 拖拽两端「手柄」(circle markers) 调整选区范围
 *
 * 渲染层叠：
 *   底 → Canvas（文字）
 *        高亮矩形（半透明品牌色）
 *        两端拖拽手柄（实心圆 + 上下竖线）
 *        工具栏（pop-up above selection）
 *
 * 状态由 Reader 通过 @Link 持有；本组件只负责 UI + 手势。
 */

import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeSaveHighlightIntent, makeLookupWordIntent } from '../intent/ReaderIntents';
import type { HighlightColor } from '../../../model/Highlight';

/** 选区范围（屏幕坐标 + 字符偏移，与 typesetting.HitResult 兼容） */
export interface SelectionRange {
  /** 选区起点（屏幕坐标） */
  startX: number;
  startY: number;
  /** 选区终点（屏幕坐标） */
  endX: number;
  endY: number;
  /** 起始字符全局偏移（block 内） */
  startCharOffset: number;
  endCharOffset: number;
  /** 选中的 blockIndex（同 typesetting.TextRun.blockIndex） */
  blockIndex: number;
  /** 选中文字的高度（用于绘制手柄） */
  lineHeight: number;
}

/** 选区状态（Reader 持有） */
export interface SelectionState {
  /** 是否激活（false 时不渲染任何 UI） */
  active: boolean;
  /** 选区粒度 */
  mode: 'word' | 'sentence' | 'paragraph';
  /** 选区范围；active=false 时为 null */
  range: SelectionRange | null;
  /** 选中的文字（去除前后空格） */
  text: string;
}

/** 工厂：创建一个空选区状态（Reader 初始化用） */
export function createEmptySelection(): SelectionState {
  return { active: false, mode: 'word', range: null, text: '' };
}

@Component
export struct SelectionLayer {
  /** Reader 注入的选区状态（双向） */
  @Link selection: SelectionState;
  /** 当前页 index（用于回查 typesetting） */
  @Prop pageIndex: number;
  /** Canvas 实际宽 / 高（vp）—— 决定工具栏 clamp 边界 */
  @Prop canvasWidth: number;
  @Prop canvasHeight: number;
  /** 当前书 ID（用于发布 SaveHighlightIntent） */
  @Prop bookId: string = '';
  /** 当前章节 ID */
  @Prop chapterId: string = '';
  /** 当前章节 index */
  @Prop chapterIndex: number = 0;

  /** 各种工具栏按钮回调 */
  onLookupWord?: (word: string, context: string) => void;
  onExplainSentence?: (sentence: string) => void;
  onTranslate?: (text: string) => void;
  onTtsRead?: (text: string) => void;
  onHighlight?: (range: SelectionRange) => void;
  onAddNote?: (range: SelectionRange) => void;
  onCopy?: (text: string) => void;
  /** 关闭选区（清空 selection） */
  onClose?: () => void;

  // ---------- 内部状态 ----------

  /** 当前是否在拖拽某个手柄（'start' | 'end' | null） */
  @State private draggingHandle: 'start' | 'end' | null = null;
  /** 工具栏自适应位置（紧贴选区上方，距 Canvas 顶部不足时翻到下方） */
  @State private toolbarY: number = 0;
  @State private toolbarFlippedDown: boolean = false;

  // ---------- 工具栏几何计算 ----------

  /**
   * 工具栏 Y 坐标策略：
   *   1. 优先紧贴选区顶部上方 12vp
   *   2. 若不够（< 8vp），翻到选区下方 12vp
   */
  private recalcToolbarY(): void {
    const r = this.selection.range;
    if (!r) return;
    const desiredTop = r.startY - r.lineHeight - 56; // 56 ≈ toolbar 高度
    if (desiredTop > 8) {
      this.toolbarY = desiredTop;
      this.toolbarFlippedDown = false;
    } else {
      this.toolbarY = r.endY + 12;
      this.toolbarFlippedDown = true;
    }
  }

  /** 工具栏 X：选区中点 - 一半宽度，clamp 到 [8, canvasW-toolbarW-8] */
  private get toolbarX(): number {
    const r = this.selection.range;
    if (!r) return 0;
    const toolbarW = 280;
    const center = (r.startX + r.endX) / 2;
    const x = center - toolbarW / 2;
    return Math.max(8, Math.min(this.canvasWidth - toolbarW - 8, x));
  }

  // ---------- 手柄拖拽手势 ----------
  // 简化实现：只更新 startX/endX，行高 + blockIndex 保持不变
  // 真实场景需要回查 typesetting.findWordAt(newX, y)，由父组件接管

  private onStartHandlePanStart(): void {
    this.draggingHandle = 'start';
  }

  private onStartHandlePanUpdate(dx: number, _dy: number): void {
    const r = this.selection.range;
    if (!r) return;
    const newRange: SelectionRange = {
      startX: Math.max(0, r.startX + dx),
      startY: r.startY,
      endX: r.endX,
      endY: r.endY,
      startCharOffset: r.startCharOffset,
      endCharOffset: r.endCharOffset,
      blockIndex: r.blockIndex,
      lineHeight: r.lineHeight,
    };
    this.selection = {
      active: this.selection.active,
      mode: this.selection.mode,
      range: newRange,
      text: this.selection.text,
    };
    this.recalcToolbarY();
  }

  private onEndHandlePanStart(): void {
    this.draggingHandle = 'end';
  }

  private onEndHandlePanUpdate(dx: number, _dy: number): void {
    const r = this.selection.range;
    if (!r) return;
    const newRange: SelectionRange = {
      startX: r.startX,
      startY: r.startY,
      endX: Math.min(this.canvasWidth, r.endX + dx),
      endY: r.endY,
      startCharOffset: r.startCharOffset,
      endCharOffset: r.endCharOffset,
      blockIndex: r.blockIndex,
      lineHeight: r.lineHeight,
    };
    this.selection = {
      active: this.selection.active,
      mode: this.selection.mode,
      range: newRange,
      text: this.selection.text,
    };
    this.recalcToolbarY();
  }

  private onPanEnd(): void {
    this.draggingHandle = null;
  }

  // ---------- 按钮回调 ----------

  private handleClose(): void {
    this.selection = { active: false, mode: 'word', range: null, text: '' };
    this.onClose?.();
  }

  // ---------- 子构造器 ----------

  /**
   * 选区高亮矩形：跨越 startX → endX，y 用 startY - lineHeight，h 用 lineHeight。
   * 简化：仅画一行；多行选择由父组件拆成多段调用（W8-B sentence 高亮可复用）。
   */
  @Builder
  highlightRect() {
    if (this.selection.range) {
      Column()
        .position({ x: this.selection.range.startX, y: this.selection.range.startY - this.selection.range.lineHeight })
        .width(Math.max(2, this.selection.range.endX - this.selection.range.startX))
        .height(this.selection.range.lineHeight)
        .backgroundColor('rgba(167, 139, 250, 0.30)') // brand b400 + 30% alpha
        .borderRadius(AppRadius.xs)
    }
  }

  /** 起始端拖拽手柄（左侧实心圆 + 上方竖线） */
  @Builder
  startHandle() {
    if (this.selection.range) {
      Column() {
        // 上方竖线
        Column()
          .width(2)
          .height(this.selection.range.lineHeight + 4)
          .backgroundColor(AppColors.brand)
        // 下方实心圆
        Column()
          .width(12)
          .height(12)
          .backgroundColor(AppColors.brand)
          .borderRadius(6)
          .margin({ top: 2 })
      }
      .position({
        x: this.selection.range.startX - 6,
        y: this.selection.range.startY - this.selection.range.lineHeight - 2,
      })
      .gesture(
        PanGesture()
          .onActionStart(() => this.onStartHandlePanStart())
          .onActionUpdate((e: GestureEvent) => this.onStartHandlePanUpdate(e.offsetX, e.offsetY))
          .onActionEnd(() => this.onPanEnd()),
      )
    }
  }

  /** 终点端拖拽手柄（右侧实心圆 + 下方竖线） */
  @Builder
  endHandle() {
    if (this.selection.range) {
      Column() {
        Column()
          .width(12)
          .height(12)
          .backgroundColor(AppColors.brand)
          .borderRadius(6)
        Column()
          .width(2)
          .height(this.selection.range.lineHeight + 4)
          .backgroundColor(AppColors.brand)
          .margin({ top: 2 })
      }
      .position({
        x: this.selection.range.endX - 6,
        y: this.selection.range.endY - 4,
      })
      .gesture(
        PanGesture()
          .onActionStart(() => this.onEndHandlePanStart())
          .onActionUpdate((e: GestureEvent) => this.onEndHandlePanUpdate(e.offsetX, e.offsetY))
          .onActionEnd(() => this.onPanEnd()),
      )
    }
  }

  /** 工具栏单按钮 */
  @Builder
  toolbarBtn(label: string, icon: string, onTap: () => void, enabled: boolean = true) {
    Column({ space: 2 }) {
      Text(icon)
        .fontSize(AppFontSize.md)
        .fontColor(enabled ? AppColors.textPrimary : AppColors.textTertiary)
      Text(label)
        .fontSize(AppFontSize.xs)
        .fontColor(enabled ? AppColors.textSecondary : AppColors.textTertiary)
    }
    .padding({ left: AppSpacing.sm, right: AppSpacing.sm, top: AppSpacing.xs, bottom: AppSpacing.xs })
    .opacity(enabled ? 1 : 0.4)
    .onClick(() => {
      if (enabled) onTap();
    })
  }

  /** 工具栏：根据 mode 显示不同按钮（word/sentence 共享 部分） */
  @Builder
  toolbar() {
    Row({ space: 0 }) {
      // 查词（仅 word）— publishes LookupWordIntent
      if (this.selection.mode === 'word') {
        this.toolbarBtn('查词', '🔍', () => {
          IntentBus.getInstance().publish(makeLookupWordIntent(this.selection.text, this.contextText()));
          this.onLookupWord?.(this.selection.text, this.contextText());
        });
      }
      // 解释句子（仅 sentence）— publishes LookupWordIntent with full sentence as context
      if (this.selection.mode === 'sentence') {
        this.toolbarBtn('解释', '💡', () => {
          IntentBus.getInstance().publish(makeLookupWordIntent(this.selection.text, this.selection.text));
          this.onExplainSentence?.(this.selection.text);
        });
      }
      this.toolbarBtn('翻译', '🌐', () => {
        this.onTranslate?.(this.selection.text);
      });
      this.toolbarBtn('朗读', '🔊', () => {
        this.onTtsRead?.(this.selection.text);
      });
      this.toolbarBtn('高亮', '✏', () => {
        if (this.selection.range) {
          // Publish SaveHighlightIntent with default yellow color; HighlightLayer color picker handles re-color.
          IntentBus.getInstance().publish(makeSaveHighlightIntent({
            bookId: this.bookId,
            chapterId: this.chapterId,
            chapterIndex: this.chapterIndex,
            blockIndex: this.selection.range.blockIndex,
            startCharOffset: this.selection.range.startCharOffset,
            endCharOffset: this.selection.range.endCharOffset,
            text: this.selection.text,
            color: 'yellow' as HighlightColor,
          }));
          this.onHighlight?.(this.selection.range);
        }
      });
      this.toolbarBtn('笔记', '📝', () => {
        if (this.selection.range) this.onAddNote?.(this.selection.range);
      });
      this.toolbarBtn('复制', '📋', () => {
        this.onCopy?.(this.selection.text);
      });
      this.toolbarBtn('关闭', '✕', () => this.handleClose());
    }
    .padding({ left: AppSpacing.xs, right: AppSpacing.xs, top: AppSpacing.xs, bottom: AppSpacing.xs })
    .backgroundColor(AppColors.bgPrimary)
    .borderRadius(AppRadius.base)
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.18)', offsetX: 0, offsetY: 2 })
    .position({ x: this.toolbarX, y: this.toolbarY })
  }

  // ---------- 上下文提取（用于 lookupWord） ----------

  /**
   * 简化版本：只把选区文字本身当 context 回传，更精确的上下文取自 Reader.extractContextSentence()
   * （父组件在调用 onLookupWord 时可重写此参数）
   */
  private contextText(): string {
    return this.selection.text;
  }

  // ---------- aboutToAppear / 监听 selection 变化 ----------

  aboutToAppear(): void {
    this.recalcToolbarY();
  }

  // ---------- build ----------

  build() {
    if (this.selection.active && this.selection.range) {
      Stack() {
        this.highlightRect();
        this.startHandle();
        this.endHandle();
        this.toolbar();
      }
      .width(this.canvasWidth)
      .height(this.canvasHeight)
      .hitTestBehavior(HitTestMode.Transparent)
    }
  }
}
