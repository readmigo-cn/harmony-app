/**
 * AppTokens — 设计 Token 统一出口
 *
 * 所有页面和组件只需从这里导入，无需直接引用各 theme 子文件。
 *
 * 用法：
 *   import { SemanticColors, TextColors, useColor, Typography, Spacing, Radius } from '../theme/AppTokens';
 */

// ─── 颜色 ───────────────────────────────────
export {
  // 类型
  ColorPair,
  // Primitive
  BrandPalette,
  GrayPalette,
  ColorPalette,
  // Semantic
  TextColors,
  BgColors,
  BorderColors,
  SurfaceColors,
  AccentColors,
  StateColors,
  // Component
  ReaderBgColors,
  ReaderTextColors,
  ReaderHighlightColors,
  TabBarColors,
  // 辅助函数
  useColor,
} from './AppColors';

// ─── 字体 ───────────────────────────────────
export {
  // 类型
  TextStyle,
  // Primitive
  FontFamily,
  FontWeightToken,
  FontSizeToken,
  LineHeightToken,
  // Semantic
  DisplayStyles,
  HeadlineStyles,
  TitleStyles,
  BodyStyles,
  LabelStyles,
  CaptionStyle,
  // Component
  ReaderBodyStyles,
  ReaderHeadingStyle,
  // 汇总对象
  Typography,
  // 辅助函数
  useTypography,
} from './AppTypography';

// ─── 间距 / 圆角 / 层级 / 动效 ─────────────
export {
  Spacing,
  Radius,
  Elevation,
  MotionDuration,
  MotionEasing,
} from './AppSpacing';
