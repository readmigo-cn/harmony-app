/**
 * Button.ets — 米果智读通用按钮组件（W6-C1）
 *
 * 变体：primary / secondary / tertiary / ghost / destructive / link
 * 尺寸：sm / md / lg
 * 形状：default(radius.md) / pill(radius.full) / square(radius.sm)
 * 图标：iconLeft / iconRight（Resource）
 * 状态：idle / pressed / disabled / loading
 * 无障碍：accessibilityText
 */

import { EffectiveTheme } from '../../core/theme/Theme.types';
import {
  useColor,
  TextColors,
  BgColors,
  AccentColors,
  BorderColors,
  StateColors,
  BrandPalette,
  GrayPalette,
} from '../../core/theme/AppColors';
import {
  Typography,
  LabelStyles,
} from '../../core/theme/AppTypography';
import { Spacing, Radius, MotionDuration, MotionEasing } from '../../core/theme/AppSpacing';

// ─────────────────────────────────────────────
// 类型导出
// ─────────────────────────────────────────────

/** 按钮外观变体 */
export type ButtonVariant = 'primary' | 'secondary' | 'tertiary' | 'ghost' | 'destructive' | 'link';

/** 按钮尺寸 */
export type ButtonSize = 'sm' | 'md' | 'lg';

/** 按钮圆角形状 */
export type ButtonShape = 'default' | 'pill' | 'square';

// ─────────────────────────────────────────────
// 尺寸 Token 映射
// ─────────────────────────────────────────────

/** 按尺寸决定高度（vp） */
function resolveHeight(size: ButtonSize): number {
  switch (size) {
    case 'sm': return 32;
    case 'lg': return 52;
    default:   return 44; // md
  }
}

/** 按尺寸决定水平内边距 */
function resolvePaddingH(size: ButtonSize): number {
  switch (size) {
    case 'sm': return Spacing.s3;  // 12vp
    case 'lg': return Spacing.s6;  // 24vp
    default:   return Spacing.s4;  // 16vp
  }
}

/** 按尺寸决定图标尺寸 */
function resolveIconSize(size: ButtonSize): number {
  switch (size) {
    case 'sm': return 14;
    case 'lg': return 20;
    default:   return 17;
  }
}

/** 按形状决定圆角 */
function resolveRadius(shape: ButtonShape): number {
  switch (shape) {
    case 'pill':   return Radius.full;
    case 'square': return Radius.sm;
    default:       return Radius.md;
  }
}

// ─────────────────────────────────────────────
// 颜色 Token 映射
// ─────────────────────────────────────────────

/** 各变体的背景色（idle） */
function resolveBg(variant: ButtonVariant, isDark: boolean): ResourceColor {
  switch (variant) {
    case 'primary':
      return useColor(AccentColors.primary, isDark);
    case 'secondary':
      return isDark ? '#2C2C2E' : BrandPalette.b100;
    case 'tertiary':
      return useColor(BgColors.secondary, isDark);
    case 'ghost':
    case 'link':
      return 'transparent';
    case 'destructive':
      return useColor(StateColors.error, isDark);
    default:
      return useColor(AccentColors.primary, isDark);
  }
}

/** 各变体按压态背景色 */
function resolvePressedBg(variant: ButtonVariant, isDark: boolean): ResourceColor {
  switch (variant) {
    case 'primary':
      return useColor(AccentColors.pressed, isDark);
    case 'secondary':
      return isDark ? '#3A3A3C' : BrandPalette.b200;
    case 'tertiary':
      return isDark ? '#3A3A3C' : GrayPalette.g200;
    case 'ghost':
      return isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)';
    case 'link':
      return 'transparent';
    case 'destructive':
      return '#E53E3E';
    default:
      return useColor(AccentColors.pressed, isDark);
  }
}

/** 各变体文字色 */
function resolveTextColor(variant: ButtonVariant, isDark: boolean): ResourceColor {
  switch (variant) {
    case 'primary':
      return '#FFFFFF';
    case 'secondary':
      return isDark ? BrandPalette.b400 : BrandPalette.b600;
    case 'tertiary':
      return useColor(TextColors.primary, isDark);
    case 'ghost':
      return useColor(TextColors.primary, isDark);
    case 'link':
      return useColor(TextColors.link, isDark);
    case 'destructive':
      return '#FFFFFF';
    default:
      return '#FFFFFF';
  }
}

/** 各变体边框宽（secondary 有 1px 边框） */
function resolveBorderWidth(variant: ButtonVariant): number {
  return variant === 'secondary' ? 1 : 0;
}

/** 各变体边框色 */
function resolveBorderColor(variant: ButtonVariant, isDark: boolean): ResourceColor {
  if (variant === 'secondary') {
    return isDark ? BrandPalette.b500 : BrandPalette.b400;
  }
  return 'transparent';
}

// ─────────────────────────────────────────────
// AppButton 组件
// ─────────────────────────────────────────────

/**
 * AppButton — 通用多态按钮
 *
 * 用法示例：
 *   AppButton({ label: '确认', variant: 'primary', size: 'md', onClick: () => {} })
 */
@Component
export struct AppButton {
  // ── 外观 Props ──
  @Prop variant: ButtonVariant = 'primary';
  @Prop size: ButtonSize = 'md';
  @Prop shape: ButtonShape = 'default';
  @Prop label: string = '';
  @Prop iconLeft: Resource | undefined = undefined;
  @Prop iconRight: Resource | undefined = undefined;

  // ── 状态 Props ──
  @Prop disabled: boolean = false;
  @Prop loading: boolean = false;
  @Prop fullWidth: boolean = false;

  // ── 无障碍 ──
  @Prop accessibilityText: string = '';

  // ── 事件 ──
  onClick?: () => void;

  // ── 主题（从祖先 ThemeProvider 消费） ──
  @Consume('theme') theme: EffectiveTheme;

  // ── 内部状态 ──
  @State private pressed: boolean = false;

  // ── 计算属性 ──
  private get isDark(): boolean {
    return this.theme === 'night';
  }

  private get isInteractive(): boolean {
    return !this.disabled && !this.loading;
  }

  private get currentBg(): ResourceColor {
    if (this.disabled) {
      return useColor(BgColors.tertiary, this.isDark);
    }
    if (this.pressed) {
      return resolvePressedBg(this.variant, this.isDark);
    }
    return resolveBg(this.variant, this.isDark);
  }

  private get currentTextColor(): ResourceColor {
    if (this.disabled) {
      return useColor(TextColors.disabled, this.isDark);
    }
    return resolveTextColor(this.variant, this.isDark);
  }

  /** label 文字样式按尺寸选取 */
  private get labelStyle() {
    switch (this.size) {
      case 'sm': return Typography.label.small;
      case 'lg': return Typography.label.large;
      default:   return Typography.label.medium;
    }
  }

  // ─── Loading Spinner ───
  @Builder
  private spinnerView() {
    // 使用 LoadingProgress 代替 Spinner（HarmonyOS 原生加载组件）
    LoadingProgress()
      .width(resolveIconSize(this.size))
      .height(resolveIconSize(this.size))
      .color(this.currentTextColor)
  }

  // ─── 图标视图 ───
  @Builder
  private iconView(res: Resource) {
    Image(res)
      .width(resolveIconSize(this.size))
      .height(resolveIconSize(this.size))
      .fillColor(this.currentTextColor)
      .objectFit(ImageFit.Contain)
  }

  // ─── 内容行 ───
  @Builder
  private contentRow() {
    Row({ space: Spacing.s2 }) {
      // 左图标 或 Loading Spinner
      if (this.loading) {
        this.spinnerView()
      } else if (this.iconLeft !== undefined) {
        this.iconView(this.iconLeft)
      }

      // 标签文字（loading 时隐藏）
      if (!this.loading) {
        Text(this.label)
          .fontFamily(this.labelStyle.fontFamily)
          .fontSize(this.labelStyle.fontSize)
          .fontWeight(this.labelStyle.fontWeight)
          .lineHeight(this.labelStyle.lineHeight)
          .fontColor(this.currentTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      // 右图标（loading 时不显示）
      if (!this.loading && this.iconRight !== undefined) {
        this.iconView(this.iconRight)
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Row() {
      this.contentRow()
    }
    // ── 尺寸布局 ──
    .height(resolveHeight(this.size))
    .padding({ left: resolvePaddingH(this.size), right: resolvePaddingH(this.size) })
    .width(this.fullWidth ? '100%' : undefined)
    .constraintSize({ minWidth: resolveHeight(this.size) }) // square 形态最小宽度保证
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)

    // ── 外观 ──
    .backgroundColor(this.currentBg)
    .borderRadius(resolveRadius(this.shape))
    .border({
      width: resolveBorderWidth(this.variant),
      color: this.disabled ? 'transparent' : resolveBorderColor(this.variant, this.isDark),
    })

    // ── 按压动效 ──
    .scale(this.pressed ? { x: 0.97, y: 0.97 } : { x: 1.0, y: 1.0 })
    .animation({
      duration: MotionDuration.fast,
      curve: MotionEasing.decelerate,
    })
    .opacity(this.disabled ? 0.4 : 1.0)

    // ── 交互 ──
    .enabled(this.isInteractive)
    .onClick(() => {
      if (this.isInteractive) {
        this.onClick?.();
      }
    })
    .onTouch((event: TouchEvent) => {
      if (!this.isInteractive) return;
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })

    // ── 无障碍 ──
    .accessibilityText(
      this.accessibilityText.length > 0
        ? this.accessibilityText
        : this.label
    )
    .accessibilityLevel(this.disabled ? 'no' : 'yes')
  }
}

// ─────────────────────────────────────────────
// @Preview — DevEco 内联预览
// ─────────────────────────────────────────────

@Preview
@Component
struct ButtonPreview {
  @Provide('theme') theme: EffectiveTheme = 'day';

  build() {
    Column({ space: Spacing.s4 }) {
      // 主要变体行
      Row({ space: Spacing.s3 }) {
        AppButton({ label: '主要按钮', variant: 'primary', size: 'md' })
        AppButton({ label: '次要按钮', variant: 'secondary', size: 'md' })
        AppButton({ label: '幽灵按钮', variant: 'ghost', size: 'md' })
      }

      // 尺寸对比行
      Row({ space: Spacing.s3 }) {
        AppButton({ label: '小', variant: 'primary', size: 'sm' })
        AppButton({ label: '中', variant: 'primary', size: 'md' })
        AppButton({ label: '大', variant: 'primary', size: 'lg' })
      }

      // 特殊状态行
      Row({ space: Spacing.s3 }) {
        AppButton({ label: '加载中', variant: 'primary', size: 'md', loading: true })
        AppButton({ label: '禁用', variant: 'primary', size: 'md', disabled: true })
        AppButton({ label: '危险', variant: 'destructive', size: 'md' })
      }

      // 全宽 + pill 形状
      AppButton({ label: '立即订阅 —全宽胶囊', variant: 'primary', size: 'lg', shape: 'pill', fullWidth: true })
    }
    .padding(Spacing.s6)
    .backgroundColor('#F7F8FD')
  }
}
