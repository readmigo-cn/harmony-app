/**
 * AiContentBadge — W16-C2「AI 生成」合规标识徽章
 *
 * 合规依据：
 *   - 国家网信办《生成式人工智能服务管理暂行办法》(2023.07) 第十二条：
 *     「提供者应当按照《互联网信息服务深度合成管理规定》对图片、视频等
 *      生成内容进行标识」
 *   - 《互联网信息服务深度合成管理规定》(2023.01) 第十六、十七条：
 *     「在生成或者编辑的信息内容的合理位置、区域进行显著标识」
 *   - 米果智读 ExplainCard / Translate / TTS 输出均由 LLM 生成，必须显式标识
 *
 * 设计：
 *   - 不依赖外部图标库，emoji 🤖 + 文字组合（同 Apple、Google 推荐做法）
 *   - 三种 mode：
 *       inline  — 紧凑徽章，嵌在标题行
 *       prefix  — 整段内容上方独占一行，清晰说明「以下内容由 AI 生成」
 *       suffix  — 内容下方提示，附带「了解更多」链接
 *   - 「了解更多」点击 onLearnMore 回调（父组件 bind 一个 sheet 即可）
 *
 * 不在此组件做的：
 *   - 不弹自己的 sheet（避免组件拥有过多状态）
 *   - 不读 SettingsStore（合规标识不可被关闭）
 */

import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';

/** 显示位置 / 形态 */
export type AiContentBadgeMode = 'inline' | 'prefix' | 'suffix';

@Component
export struct AiContentBadge {
  /** 显示模式 */
  @Prop mode: string = 'inline';
  /** 自定义提示文字（默认「AI 生成」） */
  @Prop label: string = 'AI 生成';
  /** 是否显示「了解更多」入口（仅 prefix / suffix 生效） */
  @Prop showLearnMore: boolean = true;
  /** 「了解更多」点击回调，父组件可弹 sheet */
  onLearnMore?: () => void;

  // ------ build ------

  build() {
    if (this.mode === 'prefix') {
      this.prefixBlock();
    } else if (this.mode === 'suffix') {
      this.suffixBlock();
    } else {
      this.inlineBadge();
    }
  }

  /** 紧凑徽章：嵌在标题行 */
  @Builder
  inlineBadge() {
    Row({ space: 2 }) {
      Text('🤖').fontSize(AppFontSize.xs)
      Text(this.label)
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.brand)
        .fontWeight(AppFontWeight.medium)
    }
    .padding({ left: AppSpacing.xs, right: AppSpacing.xs, top: 2, bottom: 2 })
    .borderRadius(AppRadius.sm)
    .backgroundColor('#EDE9FE')
  }

  /** 上方独占行：「以下内容由 AI 生成」 */
  @Builder
  prefixBlock() {
    Row({ space: AppSpacing.xs }) {
      Text('🤖').fontSize(AppFontSize.sm)
      Text(`以下${this.label}的内容由 AI 生成`)
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textSecondary)
        .layoutWeight(1)
      if (this.showLearnMore) {
        Text('了解更多')
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.brand)
          .onClick(() => this.onLearnMore?.())
      }
    }
    .width('100%')
    .padding(AppSpacing.xs)
    .borderRadius(AppRadius.sm)
    .backgroundColor('#F5F3FF')
  }

  /** 下方提示行：「该内容由 AI 生成」 */
  @Builder
  suffixBlock() {
    Row({ space: AppSpacing.xs }) {
      Text('🤖').fontSize(AppFontSize.xs)
      Text(`该${this.label}内容由 AI 生成，仅供参考`)
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textTertiary)
        .layoutWeight(1)
      if (this.showLearnMore) {
        Text('了解更多')
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.brand)
          .onClick(() => this.onLearnMore?.())
      }
    }
    .width('100%')
    .padding({ top: AppSpacing.xs, bottom: AppSpacing.xs })
  }
}
