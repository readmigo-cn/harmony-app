/**
 * AppTypography — 米果智读 HarmonyOS 字体 Token
 *
 * 三层结构：
 *   Primitive  → 字族、字号原始值
 *   Semantic   → 语义化文字样式（display / headline / title / body / label / caption）
 *   Component  → 阅读器专属字号阶（用户可调）
 *
 * 字族说明：
 *   - UI 字体：HarmonyOS Sans（系统默认，HarmonyOS Design 推荐）
 *   - 阅读字体：由 W5-A3 注册的 reader-font，这里仅引用 family 名，
 *     衬线字体更适合长文阅读。fallback 为系统字体。
 *
 * Source of truth: brand/tokens/primitive/font.json
 */

// ─────────────────────────────────────────────
// 辅助类型
// ─────────────────────────────────────────────

/** 完整文字样式描述 */
export interface TextStyle {
  fontFamily: string;
  fontSize: number;
  fontWeight: number | FontWeight;
  lineHeight: number;    // vp（viewport pixel）
  letterSpacing: number; // vp
}

// ─────────────────────────────────────────────
// Layer 1 — Primitive（字体原始 Token）
// ─────────────────────────────────────────────

/** 字族名称 */
export const FontFamily = {
  /** HarmonyOS Sans — UI 界面默认字族 */
  ui:     'HarmonyOS Sans',
  /** 阅读器衬线字体，由 W5-A3 注册（name: "ReadmigoReader"）*/
  reader: 'ReadmigoReader',
  /** 代码等宽字体（fallback 到系统等宽字体） */
  mono:   "'HarmonyOS Sans SC', monospace",
} as const;

/** 字重枚举 */
export const FontWeightToken = {
  light:    300,
  regular:  400,
  medium:   500,
  semibold: 600,
  bold:     700,
} as const;

/** 原始字号（vp），与 brand/tokens/primitive/font.json#font.size 对齐 */
export const FontSizeToken = {
  /** 大标题 */    display:     34,
  /** 一级标题 */  title1:      28,
  /** 二级标题 */  title2:      22,
  /** 三级标题 */  title3:      20,
  /** 醒目标题 */  headline:    17,
  /** 正文 */      body:        17,
  /** 说明文字 */  callout:     16,
  /** 副标题 */    subheadline: 15,
  /** 注脚 */      footnote:    13,
  /** 小注 1 */    caption1:    12,
  /** 小注 2 */    caption2:    11,
} as const;

/** 原始行高（vp），与 brand/tokens/primitive/font.json#font.lineHeight 对齐 */
export const LineHeightToken = {
  display:     40,
  title1:      34,
  title2:      28,
  title3:      25,
  headline:    22,
  body:        22,
  callout:     21,
  subheadline: 20,
  footnote:    18,
  caption1:    16,
  caption2:    13,
} as const;

// ─────────────────────────────────────────────
// Layer 2 — Semantic（语义化文字 Token）
// 命名规范：display / headline / title / body / label / caption
// ─────────────────────────────────────────────

/** Display 大标题（启动页、空状态页等） */
export const DisplayStyles = {
  large: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.display,
    fontWeight:    FontWeightToken.bold,
    lineHeight:    LineHeightToken.display,
    letterSpacing: -0.5,
  } as TextStyle,
  medium: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.title1,
    fontWeight:    FontWeightToken.bold,
    lineHeight:    LineHeightToken.title1,
    letterSpacing: -0.3,
  } as TextStyle,
  small: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.title2,
    fontWeight:    FontWeightToken.semibold,
    lineHeight:    LineHeightToken.title2,
    letterSpacing: -0.2,
  } as TextStyle,
};

/** Headline 区块标题 */
export const HeadlineStyles = {
  large: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.title2,
    fontWeight:    FontWeightToken.semibold,
    lineHeight:    LineHeightToken.title2,
    letterSpacing: 0,
  } as TextStyle,
  medium: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.title3,
    fontWeight:    FontWeightToken.medium,
    lineHeight:    LineHeightToken.title3,
    letterSpacing: 0,
  } as TextStyle,
  small: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.headline,
    fontWeight:    FontWeightToken.medium,
    lineHeight:    LineHeightToken.headline,
    letterSpacing: 0,
  } as TextStyle,
};

/** Title 页面 / 卡片标题 */
export const TitleStyles = {
  large: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.title3,
    fontWeight:    FontWeightToken.semibold,
    lineHeight:    LineHeightToken.title3,
    letterSpacing: 0,
  } as TextStyle,
  medium: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.headline,
    fontWeight:    FontWeightToken.semibold,
    lineHeight:    LineHeightToken.headline,
    letterSpacing: 0,
  } as TextStyle,
  small: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.body,
    fontWeight:    FontWeightToken.medium,
    lineHeight:    LineHeightToken.body,
    letterSpacing: 0,
  } as TextStyle,
};

/** Body 正文 */
export const BodyStyles = {
  large: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.body,
    fontWeight:    FontWeightToken.regular,
    lineHeight:    LineHeightToken.body,
    letterSpacing: 0,
  } as TextStyle,
  medium: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.callout,
    fontWeight:    FontWeightToken.regular,
    lineHeight:    LineHeightToken.callout,
    letterSpacing: 0,
  } as TextStyle,
  small: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.subheadline,
    fontWeight:    FontWeightToken.regular,
    lineHeight:    LineHeightToken.subheadline,
    letterSpacing: 0,
  } as TextStyle,
};

/** Label 标签 / 按钮文字 */
export const LabelStyles = {
  large: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.callout,
    fontWeight:    FontWeightToken.medium,
    lineHeight:    LineHeightToken.callout,
    letterSpacing: 0,
  } as TextStyle,
  medium: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.subheadline,
    fontWeight:    FontWeightToken.medium,
    lineHeight:    LineHeightToken.subheadline,
    letterSpacing: 0,
  } as TextStyle,
  small: {
    fontFamily:    FontFamily.ui,
    fontSize:      FontSizeToken.footnote,
    fontWeight:    FontWeightToken.medium,
    lineHeight:    LineHeightToken.footnote,
    letterSpacing: 0,
  } as TextStyle,
};

/** Caption 辅助文字 / 标注 */
export const CaptionStyle: TextStyle = {
  fontFamily:    FontFamily.ui,
  fontSize:      FontSizeToken.caption1,
  fontWeight:    FontWeightToken.regular,
  lineHeight:    LineHeightToken.caption1,
  letterSpacing: 0,
};

// ─────────────────────────────────────────────
// Layer 3 — Component（阅读器专属字体 Token）
// 5 档字号阶，用户可在设置中调节
// ─────────────────────────────────────────────

/** 阅读器字号阶（用户可调，5 档），使用衬线字体 */
export const ReaderBodyStyles = {
  /** 极小字号（适合小字高密度阅读） */
  xs: {
    fontFamily:    FontFamily.reader,
    fontSize:      14,
    fontWeight:    FontWeightToken.regular,
    lineHeight:    22,
    letterSpacing: 0.2,
  } as TextStyle,
  /** 小字号 */
  sm: {
    fontFamily:    FontFamily.reader,
    fontSize:      16,
    fontWeight:    FontWeightToken.regular,
    lineHeight:    26,
    letterSpacing: 0.2,
  } as TextStyle,
  /** 默认字号（推荐） */
  md: {
    fontFamily:    FontFamily.reader,
    fontSize:      18,
    fontWeight:    FontWeightToken.regular,
    lineHeight:    30,
    letterSpacing: 0.2,
  } as TextStyle,
  /** 大字号（老年模式） */
  lg: {
    fontFamily:    FontFamily.reader,
    fontSize:      21,
    fontWeight:    FontWeightToken.regular,
    lineHeight:    34,
    letterSpacing: 0.1,
  } as TextStyle,
  /** 极大字号 */
  xl: {
    fontFamily:    FontFamily.reader,
    fontSize:      24,
    fontWeight:    FontWeightToken.regular,
    lineHeight:    38,
    letterSpacing: 0.1,
  } as TextStyle,
};

/** 阅读器章节标题 */
export const ReaderHeadingStyle: TextStyle = {
  fontFamily:    FontFamily.reader,
  fontSize:      22,
  fontWeight:    FontWeightToken.semibold,
  lineHeight:    32,
  letterSpacing: 0,
};

// ─────────────────────────────────────────────
// 统一导出结构（便于树摇）
// ─────────────────────────────────────────────

export const Typography = {
  display:  DisplayStyles,
  headline: HeadlineStyles,
  title:    TitleStyles,
  body:     BodyStyles,
  label:    LabelStyles,
  caption:  CaptionStyle,
  reader: {
    body:    ReaderBodyStyles,
    heading: ReaderHeadingStyle,
  },
} as const;

// ─────────────────────────────────────────────
// 辅助函数：useTypography
// ─────────────────────────────────────────────

/**
 * 按 token 路径字符串返回 TextStyle。
 * 支持 "body.large"、"reader.body.md"、"caption" 等格式。
 *
 * 用法：
 *   const style = useTypography('body.large');
 *   Text('Hello').fontSize(style.fontSize).fontWeight(style.fontWeight)
 */
export function useTypography(token: string): TextStyle {
  const parts = token.split('.');
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let current: any = Typography;
  for (const part of parts) {
    if (current === undefined || current === null) break;
    current = current[part];
  }
  if (current && typeof current === 'object' && 'fontSize' in current) {
    return current as TextStyle;
  }
  // fallback：返回 body.large
  return BodyStyles.large;
}
