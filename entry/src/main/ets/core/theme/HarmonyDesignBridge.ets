/**
 * HarmonyDesignBridge — Brand Token → HarmonyOS Design 系统资源映射
 *
 * 职责：
 *   当 HarmonyOS Design 提供了等效系统资源（$r('sys.color.*') 等）时，
 *   优先使用系统资源以保证与 HarmonyOS Design 体系一致；
 *   若系统资源无对应项，则 fallback 到 AppColors / AppSpacing 中的自定义值。
 *
 * 对照表说明（"sys.color.*" 均来自 HarmonyOS Design Token 文档）：
 *
 * ┌─────────────────────────────┬──────────────────────────────────────────┬─────────────────────┐
 * │ 自定义 Token                │ HarmonyOS 系统资源                       │ 对齐状态             │
 * ├─────────────────────────────┼──────────────────────────────────────────┼─────────────────────┤
 * │ TextColors.primary          │ sys.color.ohos_id_color_text_primary     │ 系统资源优先          │
 * │ TextColors.secondary        │ sys.color.ohos_id_color_text_secondary   │ 系统资源优先          │
 * │ TextColors.tertiary         │ sys.color.ohos_id_color_text_tertiary    │ 系统资源优先          │
 * │ TextColors.disabled         │ sys.color.ohos_id_color_text_disabled    │ 系统资源优先          │
 * │ BgColors.primary            │ sys.color.ohos_id_color_background       │ 系统资源优先          │
 * │ BgColors.elevated           │ sys.color.ohos_id_color_background_secondary│ 系统资源优先      │
 * │ BorderColors.primary        │ sys.color.ohos_id_color_list_separator   │ 系统资源优先          │
 * │ AccentColors.primary        │ sys.color.brand（自定义覆盖）             │ 品牌色覆盖系统默认     │
 * │ StateColors.success         │ sys.color.ohos_id_color_connected        │ 近似，用自定义值       │
 * │ StateColors.error           │ sys.color.ohos_id_color_warning          │ 近似，用自定义值       │
 * │ StateColors.warning         │ sys.color.ohos_id_color_handup           │ 近似，用自定义值       │
 * │ Spacing.s4 (16vp)           │ sys.float.ohos_id_default_padding_start  │ 系统资源优先          │
 * │ FontSizeToken.body (17)     │ sys.float.ohos_id_text_size_body1        │ 系统资源优先          │
 * │ FontSizeToken.subheadline   │ sys.float.ohos_id_text_size_body2        │ 系统资源优先          │
 * │ FontSizeToken.caption1      │ sys.float.ohos_id_text_size_caption      │ 系统资源优先          │
 * │ ReaderBgColors.day          │ 无等效系统资源                            │ 自定义值              │
 * │ ReaderBgColors.night        │ 无等效系统资源                            │ 自定义值              │
 * │ ReaderBgColors.sepia        │ 无等效系统资源                            │ 自定义值              │
 * │ Elevation.e2（卡片阴影）     │ sys.float.ohos_id_corner_radius_default  │ 圆角对齐，阴影自定义   │
 * │ MotionDuration.normal       │ 无系统常量，参考 HIG 250ms 标准           │ 参考值对齐             │
 * └─────────────────────────────┴──────────────────────────────────────────┴─────────────────────┘
 *
 * 覆盖率统计：
 *   颜色 token 中约 7/14 可用系统资源（50%）
 *   间距 token 中约 1/3 关键值有系统等效（HarmonyOS 推荐 16vp 标准内边距）
 *   字号 token 中约 3/11 有系统资源（body1/body2/caption）
 *   圆角 / 阴影 / 动效：系统资源较少，主要靠自定义值
 */

import {
  BrandPalette,
  TextColors,
  BgColors,
  AccentColors,
  StateColors,
  BorderColors,
  useColor,
} from './AppColors';
import { FontSizeToken } from './AppTypography';
import { Spacing } from './AppSpacing';

// ─────────────────────────────────────────────
// 系统资源映射
// 调用处直接使用 $r() 语法，此文件提供对照文档 + fallback 常量
// ─────────────────────────────────────────────

/**
 * 颜色桥接
 *
 * 推荐用法：在组件里直接写 $r('sys.color.ohos_id_color_text_primary')
 * 以下 fallback 值供不支持系统资源的场景（e.g. canvas 绘图）使用。
 */
export const ColorBridge = {
  /**
   * 主文字色
   * 系统资源：$r('sys.color.ohos_id_color_text_primary')
   * Fallback：TextColors.primary.light / dark
   */
  textPrimary: {
    sysResource: 'sys.color.ohos_id_color_text_primary',
    fallbackLight: TextColors.primary.light,
    fallbackDark:  TextColors.primary.dark,
  },

  /**
   * 次要文字色
   * 系统资源：$r('sys.color.ohos_id_color_text_secondary')
   * Fallback：TextColors.secondary
   */
  textSecondary: {
    sysResource: 'sys.color.ohos_id_color_text_secondary',
    fallbackLight: TextColors.secondary.light,
    fallbackDark:  TextColors.secondary.dark,
  },

  /**
   * 弱化文字色（提示）
   * 系统资源：$r('sys.color.ohos_id_color_text_tertiary')
   * Fallback：TextColors.tertiary
   */
  textTertiary: {
    sysResource: 'sys.color.ohos_id_color_text_tertiary',
    fallbackLight: TextColors.tertiary.light,
    fallbackDark:  TextColors.tertiary.dark,
  },

  /**
   * 禁用文字色
   * 系统资源：$r('sys.color.ohos_id_color_text_disabled')
   * Fallback：TextColors.disabled
   */
  textDisabled: {
    sysResource: 'sys.color.ohos_id_color_text_disabled',
    fallbackLight: TextColors.disabled.light,
    fallbackDark:  TextColors.disabled.dark,
  },

  /**
   * 页面主背景
   * 系统资源：$r('sys.color.ohos_id_color_background')
   * Fallback：BgColors.primary
   */
  bgPrimary: {
    sysResource: 'sys.color.ohos_id_color_background',
    fallbackLight: BgColors.primary.light,
    fallbackDark:  BgColors.primary.dark,
  },

  /**
   * 卡片 / 次级背景
   * 系统资源：$r('sys.color.ohos_id_color_background_secondary')
   * Fallback：BgColors.elevated
   */
  bgElevated: {
    sysResource: 'sys.color.ohos_id_color_background_secondary',
    fallbackLight: BgColors.elevated.light,
    fallbackDark:  BgColors.elevated.dark,
  },

  /**
   * 列表分隔线 / 边框
   * 系统资源：$r('sys.color.ohos_id_color_list_separator')
   * Fallback：BorderColors.primary
   */
  borderDefault: {
    sysResource: 'sys.color.ohos_id_color_list_separator',
    fallbackLight: BorderColors.primary.light,
    fallbackDark:  BorderColors.primary.dark,
  },

  /**
   * 品牌主色（强调色）
   * HarmonyOS Design 的 sys.color.brand 会被 resources/base/element/color.json 中
   * 的 "brand" 条目覆盖，需要在 resources 里定义品牌色以生效。
   * 推荐：在 resources/base/element/color.json 添加：
   *   { "name": "brand", "value": "#A78BFA" }
   * 系统资源：$r('sys.color.brand')
   * Fallback：BrandPalette.b400
   */
  accentPrimary: {
    sysResource: 'sys.color.brand',
    fallbackLight: AccentColors.primary.light as string,
    fallbackDark:  AccentColors.primary.dark as string,
  },
} as const;

/**
 * 文字尺寸桥接
 *
 * 推荐用法：fontSize($r('sys.float.ohos_id_text_size_body1'))
 * 以下 fallback 数值供不支持系统资源的纯数字场景使用。
 */
export const FontSizeBridge = {
  /**
   * 正文字号（17vp）
   * 系统资源：$r('sys.float.ohos_id_text_size_body1')
   * Fallback：FontSizeToken.body
   */
  body1:   { sysResource: 'sys.float.ohos_id_text_size_body1',   fallback: FontSizeToken.body },
  /**
   * 副正文字号（15vp）
   * 系统资源：$r('sys.float.ohos_id_text_size_body2')
   * Fallback：FontSizeToken.subheadline
   */
  body2:   { sysResource: 'sys.float.ohos_id_text_size_body2',   fallback: FontSizeToken.subheadline },
  /**
   * 说明文字（12vp）
   * 系统资源：$r('sys.float.ohos_id_text_size_caption')
   * Fallback：FontSizeToken.caption1
   */
  caption: { sysResource: 'sys.float.ohos_id_text_size_caption', fallback: FontSizeToken.caption1 },
} as const;

/**
 * 间距桥接
 *
 * 推荐用法：padding($r('sys.float.ohos_id_default_padding_start'))
 * Fallback 供动态计算场景使用。
 */
export const SpacingBridge = {
  /**
   * 标准起始内边距（16vp）
   * 系统资源：$r('sys.float.ohos_id_default_padding_start')
   * Fallback：Spacing.s4
   */
  defaultPaddingStart: { sysResource: 'sys.float.ohos_id_default_padding_start', fallback: Spacing.s4 },
  /**
   * 标准结束内边距（16vp）
   * 系统资源：$r('sys.float.ohos_id_default_padding_end')
   * Fallback：Spacing.s4
   */
  defaultPaddingEnd:   { sysResource: 'sys.float.ohos_id_default_padding_end',   fallback: Spacing.s4 },
} as const;

// ─────────────────────────────────────────────
// resources/base/element/color.json 品牌色注入指导
// ─────────────────────────────────────────────

/**
 * 要让 HarmonyOS Design 的 $r('sys.color.brand') 生效，
 * 需在以下路径追加品牌色覆盖：
 *
 *   entry/src/main/resources/base/element/color.json
 *   {
 *     "color": [
 *       { "name": "brand", "value": "#A78BFA" }
 *     ]
 *   }
 *
 *   entry/src/main/resources/dark/element/color.json
 *   {
 *     "color": [
 *       { "name": "brand", "value": "#8B5CF6" }
 *     ]
 *   }
 *
 * 这样 $r('sys.color.brand') 在 light 下返回 #A78BFA，
 * dark 下自动返回 #8B5CF6，无需手动判断主题。
 */
export const BRAND_RESOURCE_GUIDE = {
  lightHex: BrandPalette.b400,  // '#A78BFA'
  darkHex:  BrandPalette.b500,  // '#8B5CF6'
  resourceKey: 'sys.color.brand',
} as const;

// 保留导入，供模块树摇识别依赖
const _unused = { BrandPalette, useColor, StateColors };
void _unused;
