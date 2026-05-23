/**
 * AppColors — 米果智读 HarmonyOS 颜色 Token
 *
 * 三层结构（与 readmigo brand repo 保持一致）：
 *   Primitive  → 原始色板，直接定义 hex 值
 *   Semantic   → 语义化 token，引用 Primitive，提供 light/dark 对
 *   Component  → 组件专属 token，引用 Semantic
 *
 * 品牌色说明：
 *   海外版 readmigo 主色为紫罗兰 #A78BFA（violet-400）
 *   米果智读沿用相同品牌色，保持视觉一致性
 *
 * 暗色模式：
 *   ColorPair 结构存储 light/dark 双值，由 useColor() 按当前主题返回。
 *   系统级资源（$r('sys.color.*')）的暗色切换由 HarmonyOS 运行时自动处理，
 *   不需要 ColorPair 包装，见 HarmonyDesignBridge.ets。
 */

// ─────────────────────────────────────────────
// 辅助类型
// ─────────────────────────────────────────────

/** Light / Dark 颜色对，用于语义 token */
export interface ColorPair {
  light: ResourceColor;
  dark: ResourceColor;
}

// ─────────────────────────────────────────────
// Layer 1 — Primitive（原始色板）
// Source of truth: brand/tokens/primitive/color.json & gray.json
// ─────────────────────────────────────────────

/** 品牌主色阶（Violet，与海外版 readmigo 一致） */
export const BrandPalette = {
  /** 50  — 极淡底色 */ b50:  '#F5F3FF',
  /** 100 — 淡底色   */ b100: '#EDE9FE',
  /** 200 — 浅色     */ b200: '#DDD6FE',
  /** 300 — 中浅色   */ b300: '#C4B5FD',
  /** 400 — 主品牌色 */ b400: '#A78BFA', // brand.primary（light）
  /** 500 — 深品牌色 */ b500: '#8B5CF6', // brand.primary-dark（dark）
  /** 600 — 深色     */ b600: '#7C3AED', // brand.pink（渐变末端）
  /** 700 — 更深色   */ b700: '#6D28D9', // brand.pink-dark
  /** 800 — 暗色     */ b800: '#5B21B6',
  /** 900 — 极深色   */ b900: '#4C1D95',
} as const;

/** 灰度阶 — source: brand/tokens/primitive/gray.json */
export const GrayPalette = {
  g50:  '#FAFAFA',
  g100: '#F4F4F5',
  g200: '#E4E4E7',
  g300: '#D4D4D8',
  g400: '#A1A1AA',
  g500: '#71717A',
  g600: '#52525B',
  g700: '#3F3F46',
  g800: '#27272A',
  g900: '#18181B',
} as const;

/** 功能色阶（Red / Orange / Yellow / Green / Blue / Purple / Pink） */
export const ColorPalette = {
  // Red
  red50:    '#FFF5F5', red100: '#FED7D7', red200: '#FEB2B2', red300: '#FC8181',
  red400:   '#F56565', red500: '#E53E3E', red600: '#C53030', red700: '#9B2C2C',
  red800:   '#822727', red900: '#63171B',
  // Orange
  orange50:  '#FFFAF0', orange100: '#FEEBC8', orange200: '#FBD38D', orange300: '#F6AD55',
  orange400: '#ED8936', orange500: '#DD6B20', orange600: '#C05621', orange700: '#9C4221',
  orange800: '#7B341E', orange900: '#652B19',
  // Yellow
  yellow50:  '#FFFFF0', yellow100: '#FEFCBF', yellow200: '#FAF089', yellow300: '#F6E05E',
  yellow400: '#ECC94B', yellow500: '#D69E2E', yellow600: '#B7791F', yellow700: '#975A16',
  yellow800: '#744210', yellow900: '#5F370E',
  // Green
  green50:  '#F0FFF4', green100: '#C6F6D5', green200: '#9AE6B4', green300: '#68D391',
  green400: '#48BB78', green500: '#38A169', green600: '#276749', green700: '#22543D',
  green800: '#1C4532', green900: '#1A3A2E',
  // Blue
  blue50:  '#EBF8FF', blue100: '#BEE3F8', blue200: '#90CDF4', blue300: '#63B3ED',
  blue400: '#4299E1', blue500: '#3182CE', blue600: '#2B6CB0', blue700: '#2C5282',
  blue800: '#2A4365', blue900: '#1A365D',
  // Purple（与 BrandPalette 对齐）
  purple50:  '#F5F3FF', purple100: '#EDE9FE', purple200: '#DDD6FE', purple300: '#C4B5FD',
  purple400: '#A78BFA', purple500: '#8B5CF6', purple600: '#7C3AED', purple700: '#6D28D9',
  purple800: '#5B21B6', purple900: '#4C1D95',
  // Pink
  pink50:  '#FFF5F7', pink100: '#FED7E2', pink200: '#FBB6CE', pink300: '#F687B3',
  pink400: '#ED64A6', pink500: '#D53F8C', pink600: '#B83280', pink700: '#97266D',
  pink800: '#702459', pink900: '#521B41',
} as const;

// ─────────────────────────────────────────────
// Layer 2 — Semantic（语义 Token）
// 引用 Primitive，不允许直接写 hex
// Source of truth: brand/tokens/semantic/color.light.json & color.dark.json
// ─────────────────────────────────────────────

/** 文字颜色 token */
export const TextColors: Record<string, ColorPair> = {
  /** 主要文字：标题、正文 */
  primary:   { light: '#2D2E4A', dark: '#F5F5F7' },
  /** 次要文字：副标题、说明 */
  secondary: { light: '#6B6F9C', dark: '#A1A1A6' },
  /** 提示文字：占位符、弱化信息 */
  tertiary:  { light: '#A3A6C8', dark: '#636366' },
  /** 反色文字：用于深色背景上 */
  inverse:   { light: '#FFFFFF', dark: '#000000' },
  /** 禁用文字 */
  disabled:  { light: GrayPalette.g400, dark: GrayPalette.g600 },
  /** 链接文字 */
  link:      { light: BrandPalette.b500, dark: BrandPalette.b400 },
  /** 错误提示文字 */
  error:     { light: '#FF6B6B', dark: '#FF5E5E' },
};

/** 背景颜色 token */
export const BgColors: Record<string, ColorPair> = {
  /** 页面主背景 */
  primary:   { light: '#F7F8FD', dark: '#000000' },
  /** 次要背景（Section、List 容器） */
  secondary: { light: '#EEF0FA', dark: '#1C1C1E' },
  /** 第三层背景 */
  tertiary:  { light: GrayPalette.g100, dark: '#2C2C2E' },
  /** 卡片 / 弹窗 / 悬浮层 */
  elevated:  { light: '#FFFFFF', dark: '#1C1C1E' },
  /** 遮罩层 */
  overlay:   { light: 'rgba(0,0,0,0.4)', dark: 'rgba(0,0,0,0.6)' },
};

/** 边框颜色 token */
export const BorderColors: Record<string, ColorPair> = {
  /** 默认边框 */
  primary:   { light: GrayPalette.g200, dark: GrayPalette.g700 },
  /** 弱化边框 */
  secondary: { light: '#EEF0FA', dark: '#2C2C2E' },
  /** 焦点边框（输入框聚焦） */
  focus:     { light: BrandPalette.b400, dark: BrandPalette.b500 },
  /** 错误边框 */
  error:     { light: '#FF6B6B', dark: '#FF5E5E' },
};

/** 表面颜色 token（组件背景） */
export const SurfaceColors: Record<string, ColorPair> = {
  card:    { light: '#FFFFFF', dark: '#1C1C1E' },
  button:  { light: BrandPalette.b400, dark: BrandPalette.b500 },
  input:   { light: '#F7F8FD', dark: '#2C2C2E' },
  divider: { light: GrayPalette.g200, dark: GrayPalette.g700 },
};

/** 强调色 token（品牌互动色） */
export const AccentColors: Record<string, ColorPair> = {
  /** 主强调色（按钮、选中态） */
  primary:   { light: BrandPalette.b400, dark: BrandPalette.b400 },
  /** 次强调色 */
  secondary: { light: BrandPalette.b300, dark: BrandPalette.b300 },
  /** 悬停态 */
  hover:     { light: BrandPalette.b300, dark: BrandPalette.b500 },
  /** 按压态 */
  pressed:   { light: BrandPalette.b600, dark: BrandPalette.b600 },
};

/** 状态色 token */
export const StateColors: Record<string, ColorPair> = {
  /** 成功 — source: brand.semantic.success */
  success: { light: '#6ED6A8', dark: '#4AD98D' },
  /** 警告 — source: brand.semantic.warning */
  warning: { light: '#FFC26A', dark: '#FFB74D' },
  /** 错误 — source: brand.semantic.error */
  error:   { light: '#FF6B6B', dark: '#FF5E5E' },
  /** 信息 — source: brand.semantic.info */
  info:    { light: '#7BAAFF', dark: '#6B9AEF' },
};

// ─────────────────────────────────────────────
// Layer 3 — Component（组件专属 Token）
// Source of truth: brand/tokens/component/reader.json
// ─────────────────────────────────────────────

/** 阅读器三主题背景 */
export const ReaderBgColors = {
  /** 白天模式（纯白，高对比） */
  day:   '#FFFFFF',
  /** 夜间模式（深灰，护眼） */
  night: '#1F1F1F',
  /** 纸质模式（暖黄，仿纸张） */
  sepia: '#FAF2E3',
} as const;

/** 阅读器三主题正文文字颜色 */
export const ReaderTextColors = {
  day:   '#000000',
  night: '#D9D9D9',
  sepia: '#4D331A',
} as const;

/** 阅读器高亮色 */
export const ReaderHighlightColors = {
  yellow: { light: 'rgba(255, 214, 0, 0.35)',  dark: 'rgba(255, 214, 0, 0.25)'  },
  blue:   { light: 'rgba(100, 181, 246, 0.35)', dark: 'rgba(100, 181, 246, 0.25)' },
  pink:   { light: 'rgba(248, 113, 113, 0.30)', dark: 'rgba(248, 113, 113, 0.20)' },
  green:  { light: 'rgba(74, 217, 141, 0.30)',  dark: 'rgba(74, 217, 141, 0.20)'  },
} as const;

/** Tab Bar 颜色 */
export const TabBarColors: Record<string, ColorPair> = {
  bg:        { light: '#FFFFFF', dark: '#1C1C1E' },
  icon:      { light: GrayPalette.g500, dark: GrayPalette.g400 },
  iconActive: { light: BrandPalette.b400, dark: BrandPalette.b400 },
};

// ─────────────────────────────────────────────
// 辅助函数：useColor
// ─────────────────────────────────────────────

/**
 * 根据当前颜色模式返回对应颜色值。
 *
 * @param pair   - ColorPair（light/dark 对）
 * @param isDark - 是否为深色模式，默认 false
 * @returns      ResourceColor
 *
 * 用法：
 *   fontColor(useColor(TextColors.primary, this.isDarkMode))
 */
export function useColor(pair: ColorPair, isDark: boolean = false): ResourceColor {
  return isDark ? pair.dark : pair.light;
}
