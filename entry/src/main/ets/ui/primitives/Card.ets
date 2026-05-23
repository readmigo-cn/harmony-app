/**
 * Card.ets — 米果智读卡片组件（W6-C3）
 *
 * 变体：elevated / outlined / filled
 * 内边距预设：none / sm / md / lg
 * 可组合子组件：CardMedia / CardHeader / CardBody / CardFooter
 * 支持整卡点击、宽高比、自动深色主题
 */

import { EffectiveTheme } from '../../core/theme/Theme.types';
import {
  useColor,
  TextColors,
  BgColors,
  BorderColors,
  SurfaceColors,
} from '../../core/theme/AppColors';
import {
  Typography,
  TitleStyles,
  BodyStyles,
  LabelStyles,
  CaptionStyle,
} from '../../core/theme/AppTypography';
import { Spacing, Radius, Elevation, MotionDuration, MotionEasing } from '../../core/theme/AppSpacing';

// ─────────────────────────────────────────────
// 类型导出
// ─────────────────────────────────────────────

/** 卡片外观变体 */
export type CardVariant = 'elevated' | 'outlined' | 'filled';

/** 卡片内边距预设 */
export type CardPadding = 'none' | 'sm' | 'md' | 'lg';

// ─────────────────────────────────────────────
// Token 映射辅助
// ─────────────────────────────────────────────

function resolveCardPadding(padding: CardPadding): number {
  switch (padding) {
    case 'none': return 0;
    case 'sm':   return Spacing.s3;  // 12vp
    case 'lg':   return Spacing.s5;  // 20vp
    default:     return Spacing.s4;  // 16vp (md)
  }
}

function resolveCardBg(variant: CardVariant, isDark: boolean): ResourceColor {
  switch (variant) {
    case 'elevated':
      return useColor(SurfaceColors.card, isDark);
    case 'outlined':
      return useColor(SurfaceColors.card, isDark);
    case 'filled':
      return useColor(BgColors.secondary, isDark);
    default:
      return useColor(SurfaceColors.card, isDark);
  }
}

function resolveCardBorder(variant: CardVariant, isDark: boolean): { width: number; color: ResourceColor } {
  if (variant === 'outlined') {
    return { width: 1, color: useColor(BorderColors.primary, isDark) };
  }
  return { width: 0, color: 'transparent' };
}

function resolveCardShadow(variant: CardVariant): ShadowOptions | null {
  return variant === 'elevated' ? Elevation.e2 : null;
}

// ─────────────────────────────────────────────
// CardMedia — 媒体槽（顶部图片）
// ─────────────────────────────────────────────

/**
 * CardMedia — 卡片顶部媒体图片区域
 *
 * 用法：在 AppCard 的 mediaSlot builder 中放置
 */
@Component
export struct CardMedia {
  @Prop src: string = '';
  @Prop alt: string = '';
  @Prop aspectRatio: number = 16 / 9;  // 宽高比，默认 16:9
  @Prop borderRadius: number = Radius.def; // 顶部圆角继承卡片

  build() {
    Image(this.src)
      .width('100%')
      .aspectRatio(this.aspectRatio)
      .objectFit(ImageFit.Cover)
      .borderRadius({
        topLeft: this.borderRadius,
        topRight: this.borderRadius,
        bottomLeft: 0,
        bottomRight: 0,
      })
      .alt(this.alt)
  }
}

// ─────────────────────────────────────────────
// CardHeader — 标题区
// ─────────────────────────────────────────────

/**
 * CardHeader — 卡片标题 + 副标题 + 可选操作区
 *
 * 用法：
 *   CardHeader({ title: '书名', subtitle: '作者', padding: 'md' })
 */
@Component
export struct CardHeader {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop padding: CardPadding = 'md';

  // ── 主题 ──
  @Consume('theme') theme: EffectiveTheme;

  // ── 可选：右侧操作区 builder ──
  @BuilderParam actions: () => void = CardHeader.emptyBuilder;

  @Builder
  static emptyBuilder() {}

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  build() {
    Row() {
      Column({ space: Spacing.s1 }) {
        if (this.title.length > 0) {
          Text(this.title)
            .fontFamily(TitleStyles.medium.fontFamily)
            .fontSize(TitleStyles.medium.fontSize)
            .fontWeight(TitleStyles.medium.fontWeight)
            .lineHeight(TitleStyles.medium.lineHeight)
            .fontColor(useColor(TextColors.primary, this.isDark))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontFamily(BodyStyles.small.fontFamily)
            .fontSize(BodyStyles.small.fontSize)
            .fontWeight(BodyStyles.small.fontWeight)
            .lineHeight(BodyStyles.small.lineHeight)
            .fontColor(useColor(TextColors.secondary, this.isDark))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧操作区（可选）
      this.actions()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: resolveCardPadding(this.padding),
      right: resolveCardPadding(this.padding),
      top: resolveCardPadding(this.padding),
      bottom: this.padding === 'none' ? 0 : Spacing.s2,
    })
  }
}

// ─────────────────────────────────────────────
// CardBody — 内容区
// ─────────────────────────────────────────────

/**
 * CardBody — 卡片正文内容容器
 *
 * 用法：
 *   CardBody({ padding: 'md' }) {
 *     Text('内容...')
 *   }
 */
@Component
export struct CardBody {
  @Prop padding: CardPadding = 'md';

  @BuilderParam content: () => void = CardBody.emptyBuilder;

  @Builder
  static emptyBuilder() {}

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: resolveCardPadding(this.padding),
      right: resolveCardPadding(this.padding),
      top: Spacing.s2,
      bottom: Spacing.s2,
    })
  }
}

// ─────────────────────────────────────────────
// CardFooter — 底部操作区
// ─────────────────────────────────────────────

/**
 * CardFooter — 卡片底部操作区
 *
 * 用法：
 *   CardFooter({ padding: 'md' }) {
 *     // 放置按钮等操作元素
 *   }
 */
@Component
export struct CardFooter {
  @Prop padding: CardPadding = 'md';
  @Prop showDivider: boolean = true;

  @BuilderParam actions: () => void = CardFooter.emptyBuilder;

  @Builder
  static emptyBuilder() {}

  // ── 主题 ──
  @Consume('theme') theme: EffectiveTheme;

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  build() {
    Column({ space: 0 }) {
      // 分隔线
      if (this.showDivider) {
        Divider()
          .color(useColor(BorderColors.secondary, this.isDark))
          .strokeWidth(1)
      }

      // 底部操作
      Row() {
        this.actions()
      }
      .width('100%')
      .padding({
        left: resolveCardPadding(this.padding),
        right: resolveCardPadding(this.padding),
        top: Spacing.s3,
        bottom: resolveCardPadding(this.padding),
      })
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
  }
}

// ─────────────────────────────────────────────
// AppCard — 卡片容器（主组件）
// ─────────────────────────────────────────────

/**
 * AppCard — 灵活卡片容器
 *
 * 用法示例（全组合）：
 *   AppCard({ variant: 'elevated', padding: 'none', clickable: true, onClick: () => {} }) {
 *     CardMedia({ src: '...', aspectRatio: 16/9 })
 *     CardHeader({ title: '书名', subtitle: '作者' })
 *     CardBody({ padding: 'md' }) { Text('摘要...') }
 *     CardFooter({ padding: 'md' }) { AppButton({ label: '阅读' }) }
 *   }
 *
 * 用法示例（简单内容）：
 *   AppCard({ variant: 'elevated', padding: 'md' }) {
 *     Text('内容')
 *   }
 */
@Component
export struct AppCard {
  // ── 外观 Props ──
  @Prop variant: CardVariant = 'elevated';
  @Prop padding: CardPadding = 'md';
  @Prop borderRadius: number = Radius.def;
  @Prop aspectRatio: number | undefined = undefined; // 可选宽高比约束

  // ── 交互 Props ──
  @Prop clickable: boolean = false;

  // ── 事件 ──
  onClick?: () => void;

  // ── 内容 builder ──
  @BuilderParam content: () => void = AppCard.emptyBuilder;

  @Builder
  static emptyBuilder() {}

  // ── 主题 ──
  @Consume('theme') theme: EffectiveTheme;

  // ── 内部状态 ──
  @State private pressed: boolean = false;

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  private get shadow(): ShadowOptions | null {
    return resolveCardShadow(this.variant);
  }

  private get border() {
    return resolveCardBorder(this.variant, this.isDark);
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    // 仅在 padding != none 且无子组件自管理内边距时添加统一内边距
    .padding(this.padding === 'none' ? 0 : resolveCardPadding(this.padding))
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(resolveCardBg(this.variant, this.isDark))
    .borderRadius(this.borderRadius)
    .border(this.border)
    // 阴影
    .shadow(this.shadow !== null ? this.shadow : undefined)
    // 可选宽高比
    .aspectRatio(this.aspectRatio !== undefined ? this.aspectRatio : undefined)
    // 按压动效（仅 clickable 时）
    .scale(
      this.clickable && this.pressed
        ? { x: 0.985, y: 0.985 }
        : { x: 1.0, y: 1.0 }
    )
    .animation({
      duration: MotionDuration.fast,
      curve: MotionEasing.decelerate,
    })
    // 交互
    .enabled(true)
    .onClick(() => {
      if (this.clickable) {
        this.onClick?.();
      }
    })
    .onTouch((event: TouchEvent) => {
      if (!this.clickable) return;
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    // 无障碍：clickable 卡片标记为 button 角色
    .accessibilityLevel(this.clickable ? 'yes' : 'auto')
  }
}

// ─────────────────────────────────────────────
// @Preview — DevEco 内联预览
// ─────────────────────────────────────────────

@Preview
@Component
struct CardPreview {
  @Provide('theme') theme: EffectiveTheme = 'day';

  build() {
    Scroll() {
      Column({ space: Spacing.s4 }) {

        // ── elevated 卡片（最常用） ──
        AppCard({ variant: 'elevated', padding: 'md' }) {
          Column({ space: Spacing.s2 }) {
            Text('Elevated 卡片')
              .fontSize(TitleStyles.small.fontSize)
              .fontWeight(TitleStyles.small.fontWeight)
            Text('阴影卡片，适合书单、列表项等场景。')
              .fontSize(BodyStyles.medium.fontSize)
              .fontColor('#6B6F9C')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }

        // ── outlined 卡片 ──
        AppCard({ variant: 'outlined', padding: 'md' }) {
          Column({ space: Spacing.s2 }) {
            Text('Outlined 卡片')
              .fontSize(TitleStyles.small.fontSize)
              .fontWeight(TitleStyles.small.fontWeight)
            Text('边框卡片，适合表单、设置选项等场景。')
              .fontSize(BodyStyles.medium.fontSize)
              .fontColor('#6B6F9C')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }

        // ── filled 可点击卡片 ──
        AppCard({
          variant: 'filled',
          padding: 'md',
          clickable: true,
          onClick: () => { console.info('card clicked'); },
        }) {
          Row() {
            Text('Filled 可点击卡片')
              .fontSize(TitleStyles.small.fontSize)
              .fontWeight(TitleStyles.small.fontWeight)
              .layoutWeight(1)
            Text('›')
              .fontSize(20)
              .fontColor('#A78BFA')
          }
          .width('100%')
        }

      }
      .padding(Spacing.s6)
    }
    .backgroundColor('#F7F8FD')
  }
}
