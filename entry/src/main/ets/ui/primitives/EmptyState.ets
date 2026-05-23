/**
 * EmptyState.ets — 米果智读空状态组件（W6-C9）
 *
 * 提供 AppEmptyState：
 *   - 5 种变体：no-data / no-results / error / offline / permission-denied
 *   - 每种变体内置默认插画（emoji 占位）+ 中文文案
 *   - 可覆盖 title / description / icon / action
 */

import { EffectiveTheme } from '../../core/theme/Theme.types';
import {
  useColor,
  TextColors,
  BgColors,
  AccentColors,
} from '../../core/theme/AppColors';
import {
  TitleStyles,
  BodyStyles,
  LabelStyles,
} from '../../core/theme/AppTypography';
import { Spacing, Radius, MotionDuration, MotionEasing } from '../../core/theme/AppSpacing';

// ─────────────────────────────────────────────
// 类型
// ─────────────────────────────────────────────

export type EmptyStateVariant =
  | 'no-data'
  | 'no-results'
  | 'error'
  | 'offline'
  | 'permission-denied';

export interface EmptyStateAction {
  label: string;
  onPress: () => void;
}

interface VariantPreset {
  emoji: string;
  title: string;
  description: string;
}

// ─────────────────────────────────────────────
// 默认文案
// ─────────────────────────────────────────────

const VARIANT_PRESETS: Record<EmptyStateVariant, VariantPreset> = {
  'no-data': {
    emoji: '📚',
    title: '书架空空如也',
    description: '从「发现」加几本书，开始你的阅读之旅',
  },
  'no-results': {
    emoji: '🔍',
    title: '没有找到匹配结果',
    description: '换个关键词试试，或者浏览推荐内容',
  },
  'error': {
    emoji: '⚠️',
    title: '加载出错了',
    description: '别担心，请稍后重试',
  },
  'offline': {
    emoji: '📡',
    title: '当前无网络连接',
    description: '请检查你的网络设置后重试',
  },
  'permission-denied': {
    emoji: '🔒',
    title: '权限不足',
    description: '请在设置中授予相关权限以继续使用',
  },
};

// ─────────────────────────────────────────────
// AppEmptyState
// ─────────────────────────────────────────────

@Component
export struct AppEmptyState {
  @Prop variant: EmptyStateVariant = 'no-data';
  /** 自定义图标资源（覆盖 emoji） */
  @Prop icon: Resource | undefined = undefined;
  /** 标题（覆盖默认文案） */
  @Prop title: string = '';
  /** 描述（覆盖默认文案） */
  @Prop description: string = '';
  /** 按钮文字（不为空则展示 action） */
  @Prop actionLabel: string = '';
  onAction?: () => void;

  @Consume('theme') theme: EffectiveTheme;

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  private get preset(): VariantPreset {
    return VARIANT_PRESETS[this.variant];
  }

  private get effectiveTitle(): string {
    return this.title.length > 0 ? this.title : this.preset.title;
  }

  private get effectiveDescription(): string {
    return this.description.length > 0 ? this.description : this.preset.description;
  }

  build() {
    Column({ space: Spacing.s4 }) {
      // 插画
      if (this.icon !== undefined) {
        Image(this.icon)
          .width(120)
          .height(120)
          .objectFit(ImageFit.Contain)
      } else {
        Text(this.preset.emoji)
          .fontSize(64)
          .textAlign(TextAlign.Center)
          .opacity(0.85)
      }

      // 标题
      Text(this.effectiveTitle)
        .fontFamily(TitleStyles.medium.fontFamily)
        .fontSize(TitleStyles.medium.fontSize)
        .fontWeight(TitleStyles.medium.fontWeight)
        .lineHeight(TitleStyles.medium.lineHeight)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .textAlign(TextAlign.Center)

      // 描述
      Text(this.effectiveDescription)
        .fontFamily(BodyStyles.medium.fontFamily)
        .fontSize(BodyStyles.medium.fontSize)
        .fontWeight(BodyStyles.medium.fontWeight)
        .lineHeight(BodyStyles.medium.lineHeight)
        .fontColor(useColor(TextColors.secondary, this.isDark))
        .textAlign(TextAlign.Center)
        .padding({ left: Spacing.s4, right: Spacing.s4 })

      // Action
      if (this.actionLabel.length > 0) {
        Text(this.actionLabel)
          .fontFamily(LabelStyles.medium.fontFamily)
          .fontSize(LabelStyles.medium.fontSize)
          .fontWeight(LabelStyles.large.fontWeight)
          .fontColor('#FFFFFF')
          .padding({
            left: Spacing.s5,
            right: Spacing.s5,
            top: Spacing.s2,
            bottom: Spacing.s2,
          })
          .borderRadius(Radius.full)
          .backgroundColor(useColor(AccentColors.primary, this.isDark))
          .margin({ top: Spacing.s2 })
          .onClick(() => {
            this.onAction?.();
          })
          .accessibilityText(this.actionLabel)
          .accessibilityLevel('yes')
      }
    }
    .width('100%')
    .padding({ top: Spacing.s10, bottom: Spacing.s10, left: Spacing.s4, right: Spacing.s4 })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(`${this.effectiveTitle}。${this.effectiveDescription}`)
    .accessibilityLevel('yes')
  }
}
