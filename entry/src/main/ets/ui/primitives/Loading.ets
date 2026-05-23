/**
 * Loading.ets — 米果智读加载与骨架屏组件（W6-C8）
 *
 * 提供：
 *   - LoadingIndicator  小型加载指示器（spinner / dots / progress）
 *   - AppSkeleton       骨架屏占位（text / paragraph / avatar / image / card / list-item）
 *   - AppLoadingScreen  全页加载（splash 之后、首屏数据就位前）
 */

import { EffectiveTheme } from '../../core/theme/Theme.types';
import {
  useColor,
  TextColors,
  BgColors,
  AccentColors,
  GrayPalette,
  BrandPalette,
} from '../../core/theme/AppColors';
import { LabelStyles, BodyStyles, TitleStyles } from '../../core/theme/AppTypography';
import { Spacing, Radius, MotionDuration, MotionEasing } from '../../core/theme/AppSpacing';

// ─────────────────────────────────────────────
// 类型
// ─────────────────────────────────────────────

export type LoadingSize = 'sm' | 'md' | 'lg';
export type LoadingVariant = 'spinner' | 'dots' | 'progress';

export type SkeletonVariant =
  | 'text'
  | 'paragraph'
  | 'avatar'
  | 'image'
  | 'card'
  | 'list-item';

// ─────────────────────────────────────────────
// 尺寸映射
// ─────────────────────────────────────────────

function spinnerSize(size: LoadingSize): number {
  switch (size) {
    case 'sm': return 16;
    case 'lg': return 40;
    default:   return 24;
  }
}

function dotSize(size: LoadingSize): number {
  switch (size) {
    case 'sm': return 4;
    case 'lg': return 10;
    default:   return 6;
  }
}

// ─────────────────────────────────────────────
// LoadingIndicator
// ─────────────────────────────────────────────

@Component
export struct LoadingIndicator {
  @Prop size: LoadingSize = 'md';
  @Prop variant: LoadingVariant = 'spinner';
  @Prop label: string = '';
  /** 进度（0-1），仅 variant='progress' 使用 */
  @Prop progress: number = 0;

  @Consume('theme') theme: EffectiveTheme;

  // dots 动画状态
  @State private dotPhase: number = 0;
  private dotsTimer: number = -1;

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  private get accentColor(): ResourceColor {
    return useColor(AccentColors.primary, this.isDark);
  }

  aboutToAppear(): void {
    if (this.variant === 'dots') {
      this.dotsTimer = setInterval(() => {
        this.dotPhase = (this.dotPhase + 1) % 3;
      }, 320);
    }
  }

  aboutToDisappear(): void {
    if (this.dotsTimer !== -1) {
      clearInterval(this.dotsTimer);
      this.dotsTimer = -1;
    }
  }

  @Builder
  spinnerView() {
    LoadingProgress()
      .width(spinnerSize(this.size))
      .height(spinnerSize(this.size))
      .color(this.accentColor)
  }

  private readonly dotIdx: number[] = [0, 1, 2];

  @Builder
  dotsView() {
    Row({ space: dotSize(this.size) }) {
      ForEach(this.dotIdx, (i: number) => {
        Circle({ width: dotSize(this.size), height: dotSize(this.size) })
          .fill(this.accentColor)
          .opacity(this.dotPhase === i ? 1.0 : 0.35)
          .animation({
            duration: MotionDuration.fast,
            curve: MotionEasing.standard,
          })
      }, (i: number) => `${i}`)
    }
    .height(dotSize(this.size))
  }

  @Builder
  progressView() {
    Stack({ alignContent: Alignment.Start }) {
      // 轨道
      Row()
        .width('100%')
        .height(this.size === 'sm' ? 4 : (this.size === 'lg' ? 10 : 6))
        .backgroundColor(useColor(BgColors.tertiary, this.isDark))
        .borderRadius(Radius.full)
      // 填充
      Row()
        .width(`${Math.max(0, Math.min(100, this.progress * 100))}%`)
        .height(this.size === 'sm' ? 4 : (this.size === 'lg' ? 10 : 6))
        .backgroundColor(this.accentColor)
        .borderRadius(Radius.full)
        .animation({
          duration: MotionDuration.normal,
          curve: MotionEasing.decelerate,
        })
    }
    .width('100%')
  }

  build() {
    Column({ space: Spacing.s2 }) {
      if (this.variant === 'spinner') {
        this.spinnerView()
      } else if (this.variant === 'dots') {
        this.dotsView()
      } else {
        this.progressView()
      }

      if (this.label && this.label.length > 0) {
        Text(this.label)
          .fontFamily(LabelStyles.small.fontFamily)
          .fontSize(LabelStyles.small.fontSize)
          .fontWeight(LabelStyles.small.fontWeight)
          .lineHeight(LabelStyles.small.lineHeight)
          .fontColor(useColor(TextColors.secondary, this.isDark))
          .textAlign(TextAlign.Center)
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(this.label || '加载中')
    .accessibilityLevel('yes')
  }
}

// ─────────────────────────────────────────────
// AppSkeleton — 骨架屏
// ─────────────────────────────────────────────

@Component
export struct AppSkeleton {
  @Prop variant: SkeletonVariant = 'text';
  /** paragraph 行数 */
  @Prop rows: number = 3;
  /** 单条骨架宽度，% 或 vp 数字 */
  @Prop widthPercent: string = '100%';
  /** 单条骨架高度（vp） */
  @Prop heightVp: number = 16;

  @Consume('theme') theme: EffectiveTheme;

  // shimmer 动画相位（0 → 1 循环）
  @State private shimmerPhase: number = 0;
  private shimmerTimer: number = -1;

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  private get baseColor(): ResourceColor {
    return this.isDark ? GrayPalette.g700 : GrayPalette.g200;
  }

  private get highlightColor(): ResourceColor {
    return this.isDark ? GrayPalette.g600 : GrayPalette.g100;
  }

  aboutToAppear(): void {
    // 1.5s 循环 shimmer，相位用 50ms 步进，模拟连续过渡
    this.shimmerTimer = setInterval(() => {
      this.shimmerPhase = (this.shimmerPhase + 0.04) % 1;
    }, 60);
  }

  aboutToDisappear(): void {
    if (this.shimmerTimer !== -1) {
      clearInterval(this.shimmerTimer);
      this.shimmerTimer = -1;
    }
  }

  @Builder
  bar(w: Length, h: number, radius: number) {
    Row()
      .width(w)
      .height(h)
      .backgroundColor(this.shimmerPhase < 0.5 ? this.baseColor : this.highlightColor)
      .borderRadius(radius)
      .animation({
        duration: MotionDuration.normal,
        curve: MotionEasing.standard,
      })
  }

  @Builder
  textSkeleton() {
    this.bar(this.widthPercent, this.heightVp, Radius.sm)
  }

  private get rowIndices(): number[] {
    const list: number[] = [];
    for (let i = 0; i < this.rows; i++) list.push(i);
    return list;
  }

  @Builder
  paragraphSkeleton() {
    Column({ space: Spacing.s2 }) {
      ForEach(
        this.rowIndices,
        (i: number) => {
          // 最后一行宽度收窄
          this.bar(
            i === this.rows - 1 ? '60%' : this.widthPercent,
            this.heightVp,
            Radius.sm,
          )
        },
        (i: number) => `${i}`,
      )
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  avatarSkeleton() {
    Row()
      .width(this.heightVp > 0 ? this.heightVp : 48)
      .height(this.heightVp > 0 ? this.heightVp : 48)
      .backgroundColor(this.shimmerPhase < 0.5 ? this.baseColor : this.highlightColor)
      .borderRadius(Radius.full)
      .animation({ duration: MotionDuration.normal, curve: MotionEasing.standard })
  }

  @Builder
  imageSkeleton() {
    this.bar(this.widthPercent, this.heightVp > 16 ? this.heightVp : 160, Radius.def)
  }

  @Builder
  cardSkeleton() {
    Column({ space: Spacing.s3 }) {
      this.bar('100%', 160, Radius.def)
      this.bar('80%', 18, Radius.sm)
      this.bar('100%', 14, Radius.sm)
      this.bar('60%', 14, Radius.sm)
    }
    .padding(Spacing.s3)
    .width(this.widthPercent)
    .borderRadius(Radius.lg)
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
  }

  @Builder
  listItemSkeleton() {
    Row({ space: Spacing.s3 }) {
      // 头像
      Row()
        .width(48)
        .height(48)
        .borderRadius(Radius.full)
        .backgroundColor(this.shimmerPhase < 0.5 ? this.baseColor : this.highlightColor)
        .animation({ duration: MotionDuration.normal, curve: MotionEasing.standard })

      // 文本两行
      Column({ space: Spacing.s1 }) {
        this.bar('70%', 16, Radius.sm)
        this.bar('40%', 12, Radius.sm)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(Spacing.s3)
  }

  build() {
    Column() {
      if (this.variant === 'text') {
        this.textSkeleton()
      } else if (this.variant === 'paragraph') {
        this.paragraphSkeleton()
      } else if (this.variant === 'avatar') {
        this.avatarSkeleton()
      } else if (this.variant === 'image') {
        this.imageSkeleton()
      } else if (this.variant === 'card') {
        this.cardSkeleton()
      } else {
        this.listItemSkeleton()
      }
    }
    .accessibilityText('内容加载中')
    .accessibilityLevel('yes')
  }
}

// ─────────────────────────────────────────────
// AppLoadingScreen — 全页加载
// ─────────────────────────────────────────────

@Component
export struct AppLoadingScreen {
  /** 顶部 logo（可选） */
  @Prop logo: Resource | undefined = undefined;
  /** 标签文字 */
  @Prop label: string = '加载中...';

  @Consume('theme') theme: EffectiveTheme;

  // 标签上下浮动 loop
  @State private bob: number = 0;
  private bobTimer: number = -1;

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  aboutToAppear(): void {
    this.bobTimer = setInterval(() => {
      this.bob = this.bob === 0 ? 1 : 0;
    }, 900);
  }

  aboutToDisappear(): void {
    if (this.bobTimer !== -1) {
      clearInterval(this.bobTimer);
      this.bobTimer = -1;
    }
  }

  build() {
    Column({ space: Spacing.s4 }) {
      if (this.logo !== undefined) {
        Image(this.logo)
          .width(80)
          .height(80)
          .objectFit(ImageFit.Contain)
          .opacity(this.bob === 0 ? 0.85 : 1.0)
          .animation({ duration: MotionDuration.slow, curve: MotionEasing.standard })
      }

      LoadingIndicator({ size: 'md', variant: 'spinner' })

      if (this.label && this.label.length > 0) {
        Text(this.label)
          .fontFamily(BodyStyles.medium.fontFamily)
          .fontSize(BodyStyles.medium.fontSize)
          .fontWeight(BodyStyles.medium.fontWeight)
          .fontColor(useColor(TextColors.secondary, this.isDark))
          .translate({ y: this.bob === 0 ? 0 : -2 })
          .animation({ duration: MotionDuration.slow, curve: MotionEasing.standard })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(useColor(BgColors.primary, this.isDark))
    .accessibilityText(this.label)
    .accessibilityLevel('yes')
  }
}
