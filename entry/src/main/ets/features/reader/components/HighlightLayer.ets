/**
 * HighlightLayer.ets — W8-C8 高亮渲染叠加层
 *
 * 在 Reader Canvas 之上叠加，渲染当前页所有高亮的「半透明色块」+ 暴露
 * 颜色选择 / 删除 / 添加笔记 / 复制 等交互。
 *
 * 渲染策略：
 *   - 由 Reader 注入 highlights 列表 + 当前 typesetting 引擎 → getRectsForRange
 *     无该 API 时，组件自身用 Canvas 绘制矩形（基于 Highlight 已自带的页内坐标）。
 *   - 这里我们不直接绘制（Reader Canvas 已绘制），仅渲染交互层：颜色选择 popover +
 *     action sheet。
 *
 * 颜色：'yellow' | 'green' | 'blue' | 'pink' | 'orange'，与 model/Highlight.ets 对齐。
 *
 * 交互：
 *   1. SelectionLayer onHighlight callback → 弹出颜色选择 popover（4 色 chips）
 *      → onCreate(range, color) → 持久化 + 闭合
 *   2. 点击已存在的 highlight → 弹出 action sheet（修改颜色 / 删除 / 添加笔记 / 复制）
 *      → onUpdate / onDelete / onAddNote
 */

import { TextColors, BgColors, useColor, ReaderHighlightColors, BorderColors } from '../../../core/theme/AppColors';
import { BodyStyles, LabelStyles } from '../../../core/theme/AppTypography';
import { Spacing, Radius, Elevation } from '../../../core/theme/AppSpacing';
import { Highlight, HighlightColor } from '../../../model/Highlight';
import { SelectionRange } from './SelectionLayer';
import { AppButton } from './Button';

/** 4 色对照（顺序与 Reader 现有配置一致） */
const HIGHLIGHT_COLORS: HighlightColor[] = ['yellow', 'green', 'blue', 'pink'];

/** 色块预览（chip 用，浅一点的填充） */
const COLOR_CHIP_HEX: Record<HighlightColor, string> = {
  yellow: '#FFD600',
  green:  '#4AD98D',
  blue:   '#64B5F6',
  pink:   '#F87171',
  orange: '#FFB74D',
};

/** action sheet 操作类型 */
type HighlightAction = 'recolor' | 'delete' | 'note' | 'copy';

@Component
export struct HighlightLayer {
  /** 当前页 index（用于按页过滤） */
  @Prop pageIndex: number;
  /** 当前书所有 highlights（Reader 注入） */
  @Prop highlights: Highlight[];
  /** 暗色 */
  @Prop isDark: boolean;
  /** 颜色选择 popover 是否显示（由父组件通过 selectionRange 触发） */
  @Link colorPickerVisible: boolean;
  /** 触发颜色选择的选区（用来生成 highlight） */
  @Link pendingRange: SelectionRange | null;

  /** Action sheet 当前选中的 highlight id */
  @State private actionTargetId: string = '';
  @State private actionSheetVisible: boolean = false;

  // ── 父注入回调 ────────────────────────────
  onCreate?: (range: SelectionRange, color: HighlightColor) => Promise<void>;
  onDelete?: (id: string) => Promise<void>;
  onUpdate?: (id: string, partial: Partial<Highlight>) => Promise<void>;
  onAddNote?: (id: string) => void;
  onCopy?: (text: string) => void;

  // ── 暴露给 Reader 用（点击 highlight 时父调用） ──
  /** Reader 通过 hitTest 命中某 highlight 后调本方法弹出 action sheet。 */
  openActionSheet(id: string): void {
    this.actionTargetId = id;
    this.actionSheetVisible = true;
  }

  // ──────────────────────────────────────────
  //   颜色选择 popover
  // ──────────────────────────────────────────

  @Builder
  colorPicker() {
    Row({ space: Spacing.s2 }) {
      ForEach(HIGHLIGHT_COLORS, (c: HighlightColor) => {
        Stack() {
          Column()
            .width(28).height(28)
            .borderRadius(14)
            .backgroundColor(COLOR_CHIP_HEX[c])
            .border({ width: 1, color: useColor(BorderColors.primary, this.isDark) })
        }
        .onClick(() => this.handlePickColor(c))
      })
      Text('×')
        .fontSize(LabelStyles.large.fontSize)
        .fontColor(useColor(TextColors.secondary, this.isDark))
        .padding(Spacing.s2)
        .onClick(() => this.dismissColorPicker())
    }
    .padding({ left: Spacing.s3, right: Spacing.s3, top: Spacing.s2, bottom: Spacing.s2 })
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
    .borderRadius(Radius.lg)
    .shadow({ radius: Elevation.e2.blurRadius, color: '#22000000', offsetY: 2 })
  }

  private async handlePickColor(c: HighlightColor): Promise<void> {
    const range = this.pendingRange;
    this.colorPickerVisible = false;
    this.pendingRange = null;
    if (!range) return;
    if (this.onCreate) {
      await this.onCreate(range, c);
    }
  }

  private dismissColorPicker(): void {
    this.colorPickerVisible = false;
    this.pendingRange = null;
  }

  // ──────────────────────────────────────────
  //   Action sheet（点击已存在的 highlight）
  // ──────────────────────────────────────────

  private currentHighlight(): Highlight | null {
    if (!this.actionTargetId) return null;
    for (const h of this.highlights) {
      if (h.id === this.actionTargetId) return h;
    }
    return null;
  }

  @Builder
  actionSheet() {
    Column({ space: Spacing.s2 }) {
      // 颜色切换条
      Row({ space: Spacing.s2 }) {
        Text('颜色')
          .fontSize(LabelStyles.medium.fontSize)
          .fontColor(useColor(TextColors.secondary, this.isDark))
        ForEach(HIGHLIGHT_COLORS, (c: HighlightColor) => {
          Column()
            .width(24).height(24).borderRadius(12)
            .backgroundColor(COLOR_CHIP_HEX[c])
            .border({
              width: this.currentHighlight()?.color === c ? 2 : 1,
              color: useColor(BorderColors.primary, this.isDark),
            })
            .onClick(() => this.runAction('recolor', c))
        })
      }
      .width('100%')
      .padding(Spacing.s3)

      this.actionRow('添加笔记', () => this.runAction('note'))
      this.actionRow('复制原文', () => this.runAction('copy'))
      this.actionRow('删除高亮', () => this.runAction('delete'), true)

      AppButton({
        label: '取消',
        variant: 'tertiary',
        onAction: () => this.dismissActionSheet(),
      })
        .margin({ top: Spacing.s2 })
    }
    .width('100%')
    .padding(Spacing.s4)
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
    .borderRadius({ topLeft: Radius.xl, topRight: Radius.xl })
  }

  @Builder
  actionRow(label: string, onTap: () => void, danger: boolean = false) {
    Row() {
      Text(label)
        .fontSize(BodyStyles.medium.fontSize)
        .fontColor(danger
          ? '#F87171'
          : useColor(TextColors.primary, this.isDark))
        .layoutWeight(1)
    }
    .width('100%')
    .padding(Spacing.s3)
    .onClick(onTap)
  }

  private async runAction(action: HighlightAction, color?: HighlightColor): Promise<void> {
    const h = this.currentHighlight();
    if (!h) {
      this.dismissActionSheet();
      return;
    }
    if (action === 'recolor' && color && this.onUpdate) {
      await this.onUpdate(h.id, { color });
    } else if (action === 'delete' && this.onDelete) {
      await this.onDelete(h.id);
    } else if (action === 'note' && this.onAddNote) {
      this.onAddNote(h.id);
    } else if (action === 'copy' && this.onCopy) {
      this.onCopy(h.text);
    }
    this.dismissActionSheet();
  }

  private dismissActionSheet(): void {
    this.actionSheetVisible = false;
    this.actionTargetId = '';
  }

  // ──────────────────────────────────────────
  //   build
  // ──────────────────────────────────────────

  build() {
    Stack() {
      // 颜色选择 popover：浮在选区上方
      if (this.colorPickerVisible && this.pendingRange) {
        Column() {
          this.colorPicker()
        }
        .position({
          x: Math.max(0, (this.pendingRange.startX + this.pendingRange.endX) / 2 - 110),
          y: Math.max(0, this.pendingRange.startY - 56),
        })
      }

      // Action sheet（底部弹出）
      if (this.actionSheetVisible) {
        // 半透明遮罩（吞掉外部点击）
        Column()
          .width('100%').height('100%')
          .backgroundColor(useColor(BgColors.overlay, this.isDark))
          .onClick(() => this.dismissActionSheet())
        Column() {
          this.actionSheet()
        }
        .width('100%')
        .position({ x: 0, y: 0 })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.End)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.colorPickerVisible || this.actionSheetVisible
      ? HitTestMode.Default
      : HitTestMode.Transparent)
  }
}

/** 重导出，方便 Reader 引用。 */
export { ReaderHighlightColors };
