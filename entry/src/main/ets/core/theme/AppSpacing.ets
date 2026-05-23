/**
 * AppSpacing — 米果智读 HarmonyOS 间距 / 圆角 / 层级 / 动效 Token
 *
 * Source of truth:
 *   - 间距：brand/tokens/semantic/spacing.json
 *   - 圆角：brand/tokens/semantic/radius.json
 *   - 阴影：brand/tokens/semantic/shadow.json（HarmonyOS 用 ShadowOptions 替代 CSS shadow）
 */

// ─────────────────────────────────────────────
// Spacing（间距阶）
// 基于 4px 基准单位，与 brand spacing token 完整对齐
// brand spacing.json: 0/4/8/12/16/20/24/32/40/48/64，此处扩展更多档位
// ─────────────────────────────────────────────

export const Spacing = {
  /** 0vp  */  s0:   0,
  /** 2vp  */  s0_5: 2,
  /** 4vp  */  s1:   4,   // brand spacing.1
  /** 8vp  */  s2:   8,   // brand spacing.2
  /** 12vp */  s3:   12,  // brand spacing.3
  /** 16vp */  s4:   16,  // brand spacing.4
  /** 20vp */  s5:   20,  // brand spacing.5
  /** 24vp */  s6:   24,  // brand spacing.6
  /** 32vp */  s8:   32,  // brand spacing.8
  /** 40vp */  s10:  40,  // brand spacing.10
  /** 48vp */  s12:  48,  // brand spacing.12
  /** 64vp */  s16:  64,  // brand spacing.16
  /** 80vp */  s20:  80,
  /** 96vp */  s24:  96,
  /** 120vp */ s30:  120,
  /** 160vp */ s40:  160,
  /** 200vp */ s50:  200,
  /** 240vp */ s60:  240,
} as const;

// ─────────────────────────────────────────────
// Radius（圆角）
// Source of truth: brand/tokens/semantic/radius.json
// ─────────────────────────────────────────────

export const Radius = {
  /** 0    — 无圆角 */        none: 0,   // brand radius.none
  /** 4vp  — 小圆角，标签  */ sm:   4,   // brand radius.sm
  /** 6vp  — 中小圆角     */  md:   6,   // brand radius.md
  /** 8vp  — 默认卡片圆角 */  def:  8,   // brand radius.default
  /** 12vp — 大圆角，输入框*/ lg:   12,  // brand radius.lg
  /** 16vp — 弹窗底部栏   */  xl:   16,  // brand radius.xl
  /** 20vp — 超大圆角     */  xxl:  20,  // brand radius.2xl
  /** 9999 — 完全圆形     */  full: 9999, // brand radius.full
} as const;

// ─────────────────────────────────────────────
// Elevation（层级 / 阴影）
// HarmonyOS 使用 ShadowOptions，无法直接用 CSS shadow 字符串
// 每档对应 brand/tokens/semantic/shadow.json 的概念层级
// ─────────────────────────────────────────────

export const Elevation = {
  /** 0 — 无阴影（同层内容） */
  e0: null as ShadowOptions | null,

  /** 1 — 极淡阴影（分割线替代）  brand: shadow.sm */
  e1: {
    radius:  4,
    color:   'rgba(0,0,0,0.05)',
    offsetX: 0,
    offsetY: 1,
  } as ShadowOptions,

  /** 2 — 卡片阴影              brand: shadow.md */
  e2: {
    radius:  8,
    color:   'rgba(0,0,0,0.10)',
    offsetX: 0,
    offsetY: 2,
  } as ShadowOptions,

  /** 3 — 浮动卡片阴影          brand: shadow.lg */
  e3: {
    radius:  16,
    color:   'rgba(0,0,0,0.10)',
    offsetX: 0,
    offsetY: 4,
  } as ShadowOptions,

  /** 4 — 底部弹窗 / DropDown   brand: shadow.xl */
  e4: {
    radius:  24,
    color:   'rgba(0,0,0,0.10)',
    offsetX: 0,
    offsetY: 10,
  } as ShadowOptions,

  /** 5 — 全屏模态弹窗           brand: shadow.2xl */
  e5: {
    radius:  40,
    color:   'rgba(0,0,0,0.10)',
    offsetX: 0,
    offsetY: 20,
  } as ShadowOptions,
} as const;

// ─────────────────────────────────────────────
// Motion（动效 Token）
// HarmonyOS Animation 曲线对应 Material / HIG 规范
// ─────────────────────────────────────────────

/** 动效时长（ms） */
export const MotionDuration = {
  /** 即时响应（图标切换、Tab 切换）   */ fast:   150,
  /** 标准过渡（页面推入、弹窗出现）   */ normal: 250,
  /** 慢速动画（引导动画、空状态插画） */ slow:   400,
} as const;

/** 动效曲线（HarmonyOS Curve 枚举） */
export const MotionEasing = {
  /**
   * 标准曲线 — EaseInOut
   * 用于页面转场、容器布局变化
   */
  standard:    Curve.EaseInOut,

  /**
   * 减速曲线 — EaseOut（decelerate）
   * 用于元素进入屏幕（从外部飞入）
   */
  decelerate:  Curve.EaseOut,

  /**
   * 加速曲线 — EaseIn（accelerate）
   * 用于元素离开屏幕（飞出去）
   */
  accelerate:  Curve.EaseIn,

  /**
   * 弹簧曲线 — Spring
   * 用于卡片展开 / 收起等弹性交互
   */
  spring:      Curve.Spring,
} as const;
