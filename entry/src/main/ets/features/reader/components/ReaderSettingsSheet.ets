/**
 * ReaderSettingsSheet.ets — W7-C 阅读器视觉设置面板
 *
 * 集合 W7-C1（字号）/ W7-C2（行距）/ W7-C3（主题）/ W7-C4（翻页方式）+ 字体备选。
 *
 * 架构：
 *   - 复用 W6 AppSheet，提供底部弹窗 + 拖拽手柄 + 遮罩
 *   - 设置变更立即写入 SettingsStore（持久化）+ 调用回调（让 Reader 触发 relayout）
 *   - 主题切换调用 ThemeService.setUserTheme，由 ThemeService 推送到 AppStorage
 *
 * 实时应用机制：
 *   - 字号：onFontSizeChange(sp) → Reader 调 typesetting.setFontSize() + relayout，
 *     基于 percentComplete 重新定位 pageIndex 保持阅读位置
 *   - 行距：onLineHeightChange(multiplier) → Reader 调 typesetting.setLineHeight() + relayout
 *   - 主题：onThemeChange(theme) → Reader 调 typesetting.setTheme() + Canvas 重绘（无需 relayout）
 *   - 翻页：onPageTurnModeChange(mode) → Reader 重新初始化翻页 controller
 *   - 字体：onFontChange(font) → Reader 更新 fontFamily + Canvas 重绘
 */

import {
  TextColors,
  BgColors,
  BorderColors,
  AccentColors,
  SurfaceColors,
  useColor,
} from '../../../core/theme/AppColors';
import {
  FontFamily,
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius, MotionDuration, MotionEasing } from '../../../core/theme/AppSpacing';
import {
  SettingsStore,
  ReaderTheme,
  PageTurnMode,
  ReaderFont,
  FontSizeLevel,
  LineHeightLevel,
  FONT_SIZE_LEVEL_MAP,
  LINE_HEIGHT_LEVEL_MAP,
} from '../../../store/SettingsStore';
import { ThemeService } from '../../../core/theme/ThemeService';
import { AppSheet } from '../../../ui/primitives/Modal';
import { ToastManager } from './Toast';

// ─────────────────────────────────────────────
// 视觉档位元数据
// ─────────────────────────────────────────────

/** 字号档位元数据（与 SettingsStore.FONT_SIZE_LEVEL_MAP 对齐） */
interface FontSizeOption {
  level: FontSizeLevel;
  label: string;
  size: number;
}

const FONT_SIZE_OPTIONS: FontSizeOption[] = [
  { level: 1, label: '极小', size: FONT_SIZE_LEVEL_MAP[1] },
  { level: 2, label: '小',   size: FONT_SIZE_LEVEL_MAP[2] },
  { level: 3, label: '中',   size: FONT_SIZE_LEVEL_MAP[3] },
  { level: 4, label: '大',   size: FONT_SIZE_LEVEL_MAP[4] },
  { level: 5, label: '极大', size: FONT_SIZE_LEVEL_MAP[5] },
];

/** 行距档位元数据 */
interface LineHeightOption {
  level: LineHeightLevel;
  label: string;
  multiplier: number;
}

const LINE_HEIGHT_OPTIONS: LineHeightOption[] = [
  { level: 1, label: '紧凑', multiplier: LINE_HEIGHT_LEVEL_MAP[1] },
  { level: 2, label: '标准', multiplier: LINE_HEIGHT_LEVEL_MAP[2] },
  { level: 3, label: '宽松', multiplier: LINE_HEIGHT_LEVEL_MAP[3] },
];

/** 主题档位元数据（含视觉示意色） */
interface ThemeOption {
  value: ReaderTheme;
  label: string;
  bg: ResourceColor;
  fg: ResourceColor;
}

const THEME_OPTIONS: ThemeOption[] = [
  { value: 'day',    label: '日间',     bg: '#FFFFFF', fg: '#1A1A1A' },
  { value: 'night',  label: '夜间',     bg: '#1F1F1F', fg: '#D9D9D9' },
  { value: 'paper',  label: '羊皮纸',   bg: '#FAF2E3', fg: '#4D331A' },
  { value: 'system', label: '跟随系统', bg: '#A78BFA', fg: '#FFFFFF' },
];

/** 翻页档位元数据 */
interface PageTurnOption {
  value: PageTurnMode;
  label: string;
  icon: string;
}

const PAGE_TURN_OPTIONS: PageTurnOption[] = [
  { value: 'paged',      label: '卷页',  icon: '⊟' },
  { value: 'horizontal', label: '滑动',  icon: '↔' },
  { value: 'scroll',     label: '滚动',  icon: '↕' },
];

/** 字体档位元数据 */
interface FontOption {
  value: ReaderFont;
  label: string;
  family: string;
}

const FONT_OPTIONS: FontOption[] = [
  { value: 'sans',   label: '黑体',   family: FontFamily.ui },
  { value: 'serif',  label: '阅读',   family: FontFamily.reader },
  { value: 'system', label: '系统',   family: 'sans-serif' },
];

// ─────────────────────────────────────────────
// ReaderSettingsSheet 组件
// ─────────────────────────────────────────────

/**
 * 阅读设置底部弹窗。
 *
 * 用法（在 Reader.ets）：
 *   ReaderSettingsSheet({
 *     visible: $showSettings,
 *     isDark: this.theme === 'night',
 *     onFontSizeChange: (sp) => { ... },
 *     onLineHeightChange: (m) => { ... },
 *     onThemeChange: (t) => { ... },
 *     onPageTurnModeChange: (m) => { ... },
 *     onFontChange: (f) => { ... },
 *   })
 */
@Component
export struct ReaderSettingsSheet {
  /** 是否显示（双向绑定） */
  @Link visible: boolean;
  /** 是否暗色（一般 = (theme === 'night')） */
  isDark: boolean = false;

  /** 字号变化回调，参数为目标 sp 字号 */
  onFontSizeChange?: (size: number) => void;
  /** 行距变化回调，参数为行距倍数 */
  onLineHeightChange?: (multiplier: number) => void;
  /** 主题变化回调 */
  onThemeChange?: (theme: ReaderTheme) => void;
  /** 翻页方式变化回调 */
  onPageTurnModeChange?: (mode: PageTurnMode) => void;
  /** 字体变化回调，参数为 fontFamily 名 */
  onFontChange?: (font: ReaderFont, family: string) => void;

  // ── 当前选中状态（从 SettingsStore 初始化）──
  @State private fontSizeLevel: FontSizeLevel = SettingsStore.getReaderFontSizeLevel();
  @State private lineHeightLevel: LineHeightLevel = SettingsStore.getReaderLineHeightLevel();
  @State private theme: ReaderTheme = SettingsStore.getReaderTheme();
  @State private pageTurnMode: PageTurnMode = SettingsStore.getReaderPageTurnMode();
  @State private readerFont: ReaderFont = SettingsStore.getReaderFont();

  aboutToAppear(): void {
    // 每次打开重新拉取，避免外部其他途径变更未同步
    this.fontSizeLevel = SettingsStore.getReaderFontSizeLevel();
    this.lineHeightLevel = SettingsStore.getReaderLineHeightLevel();
    this.theme = SettingsStore.getReaderTheme();
    this.pageTurnMode = SettingsStore.getReaderPageTurnMode();
    this.readerFont = SettingsStore.getReaderFont();
  }

  // ───── handlers ─────

  private handleFontSizeLevel(level: FontSizeLevel): void {
    if (this.fontSizeLevel === level) return;
    this.fontSizeLevel = level;
    SettingsStore.setReaderFontSizeLevel(level);
    const size = FONT_SIZE_LEVEL_MAP[level];
    this.onFontSizeChange?.(size);
  }

  private handleLineHeightLevel(level: LineHeightLevel): void {
    if (this.lineHeightLevel === level) return;
    this.lineHeightLevel = level;
    SettingsStore.setReaderLineHeightLevel(level);
    this.onLineHeightChange?.(LINE_HEIGHT_LEVEL_MAP[level]);
  }

  private handleTheme(t: ReaderTheme): void {
    if (this.theme === t) return;
    this.theme = t;
    // ThemeService 内部会写回 SettingsStore + 推送 'app_theme_mode'
    if (t === 'day' || t === 'night' || t === 'sepia' || t === 'system') {
      ThemeService.setUserTheme(t);
    } else {
      // 'paper' → 兼容路径：直接写 SettingsStore，再让 ThemeService 重算
      SettingsStore.setReaderTheme(t);
      ThemeService.setUserTheme('sepia');
    }
    this.onThemeChange?.(t);
  }

  private handlePageTurn(mode: PageTurnMode): void {
    if (this.pageTurnMode === mode) return;
    this.pageTurnMode = mode;
    SettingsStore.setReaderPageTurnMode(mode);
    this.onPageTurnModeChange?.(mode);
    ToastManager.info(this.pageTurnLabel(mode), 1200);
  }

  private handleFont(f: ReaderFont): void {
    if (this.readerFont === f) return;
    this.readerFont = f;
    SettingsStore.setReaderFont(f);
    const family = FONT_OPTIONS.find((o) => o.value === f)?.family ?? FontFamily.ui;
    this.onFontChange?.(f, family);
  }

  private pageTurnLabel(mode: PageTurnMode): string {
    return PAGE_TURN_OPTIONS.find((o) => o.value === mode)?.label ?? mode;
  }

  // ───── builders ─────

  /** 区块标题：「字号 / 行距 / 主题 / 翻页方式 / 字体」 */
  @Builder
  sectionHeader(label: string) {
    Text(label)
      .fontSize(FontSizeToken.subheadline)
      .fontFamily(FontFamily.ui)
      .fontWeight(FontWeightToken.medium)
      .fontColor(useColor(TextColors.secondary, this.isDark))
      .margin({ bottom: Spacing.s3 })
  }

  /** Section A：字号（5 档圆形按钮 + 当前数值描述） */
  @Builder
  fontSizeSection() {
    Column({ space: 0 }) {
      this.sectionHeader('字号')

      Row({ space: Spacing.s3 }) {
        ForEach(FONT_SIZE_OPTIONS, (opt: FontSizeOption) => {
          this.fontSizeButton(opt)
        }, (opt: FontSizeOption) => `fs-${opt.level}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 当前选中描述：「中（18sp）」
      Text(`${FONT_SIZE_OPTIONS[this.fontSizeLevel - 1].label}（${FONT_SIZE_OPTIONS[this.fontSizeLevel - 1].size}sp）`)
        .fontSize(FontSizeToken.caption1)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
        .margin({ top: Spacing.s3 })
        .alignSelf(ItemAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Spacing.s4, bottom: Spacing.s4 })
  }

  @Builder
  fontSizeButton(opt: FontSizeOption) {
    Column() {
      Text('A')
        .fontSize(opt.size)
        .fontFamily(FontFamily.ui)
        .fontWeight(FontWeightToken.medium)
        .fontColor(this.fontSizeLevel === opt.level
          ? useColor(TextColors.inverse, this.isDark)
          : useColor(TextColors.primary, this.isDark))
    }
    .width(48)
    .height(48)
    .borderRadius(Radius.full)
    .backgroundColor(this.fontSizeLevel === opt.level
      ? useColor(AccentColors.primary, this.isDark)
      : useColor(BgColors.secondary, this.isDark))
    .border({
      width: this.fontSizeLevel === opt.level ? 0 : 1,
      color: useColor(BorderColors.secondary, this.isDark),
    })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .animation({
      duration: MotionDuration.fast,
      curve: MotionEasing.standard,
    })
    .onClick(() => this.handleFontSizeLevel(opt.level))
  }

  /** Section B：行距（3 档图标按钮） */
  @Builder
  lineHeightSection() {
    Column({ space: 0 }) {
      this.sectionHeader('行距')

      Row({ space: Spacing.s3 }) {
        ForEach(LINE_HEIGHT_OPTIONS, (opt: LineHeightOption) => {
          this.lineHeightButton(opt)
        }, (opt: LineHeightOption) => `lh-${opt.level}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Spacing.s4, bottom: Spacing.s4 })
  }

  @Builder
  lineHeightButton(opt: LineHeightOption) {
    Column({ space: 4 }) {
      // 视觉示意：3 条不同行距的横线
      Column({ space: opt.multiplier === 1.4 ? 2 : opt.multiplier === 1.6 ? 4 : 6 }) {
        Column().width(28).height(2).backgroundColor(useColor(TextColors.secondary, this.isDark))
        Column().width(20).height(2).backgroundColor(useColor(TextColors.secondary, this.isDark))
        Column().width(24).height(2).backgroundColor(useColor(TextColors.secondary, this.isDark))
      }
      .alignItems(HorizontalAlign.Start)

      Text(opt.label)
        .fontSize(FontSizeToken.caption1)
        .fontColor(this.lineHeightLevel === opt.level
          ? useColor(AccentColors.primary, this.isDark)
          : useColor(TextColors.tertiary, this.isDark))
    }
    .layoutWeight(1)
    .height(72)
    .borderRadius(Radius.lg)
    .backgroundColor(useColor(BgColors.secondary, this.isDark))
    .border({
      width: this.lineHeightLevel === opt.level ? 2 : 1,
      color: this.lineHeightLevel === opt.level
        ? useColor(AccentColors.primary, this.isDark)
        : useColor(BorderColors.secondary, this.isDark),
    })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .animation({
      duration: MotionDuration.fast,
      curve: MotionEasing.standard,
    })
    .onClick(() => this.handleLineHeightLevel(opt.level))
  }

  /** Section C：主题（4 档色块） */
  @Builder
  themeSection() {
    Column({ space: 0 }) {
      this.sectionHeader('主题')

      Row({ space: Spacing.s3 }) {
        ForEach(THEME_OPTIONS, (opt: ThemeOption) => {
          this.themeButton(opt)
        }, (opt: ThemeOption) => `th-${opt.value}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Spacing.s4, bottom: Spacing.s4 })
  }

  @Builder
  themeButton(opt: ThemeOption) {
    Column({ space: 6 }) {
      // 主题色块：背景 + 文字 "A" 样本
      Column() {
        Text('A')
          .fontSize(20)
          .fontFamily(FontFamily.ui)
          .fontWeight(FontWeightToken.medium)
          .fontColor(opt.fg)
      }
      .width(48)
      .height(48)
      .borderRadius(Radius.full)
      .backgroundColor(opt.bg)
      .border({
        width: this.theme === opt.value ? 2 : 1,
        color: this.theme === opt.value
          ? useColor(AccentColors.primary, this.isDark)
          : useColor(BorderColors.secondary, this.isDark),
      })
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)

      Text(opt.label)
        .fontSize(FontSizeToken.caption1)
        .fontColor(this.theme === opt.value
          ? useColor(AccentColors.primary, this.isDark)
          : useColor(TextColors.tertiary, this.isDark))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .animation({
      duration: MotionDuration.fast,
      curve: MotionEasing.standard,
    })
    .onClick(() => this.handleTheme(opt.value))
  }

  /** Section D：翻页方式（3 档图标按钮） */
  @Builder
  pageTurnSection() {
    Column({ space: 0 }) {
      this.sectionHeader('翻页方式')

      Row({ space: Spacing.s3 }) {
        ForEach(PAGE_TURN_OPTIONS, (opt: PageTurnOption) => {
          this.pageTurnButton(opt)
        }, (opt: PageTurnOption) => `pt-${opt.value}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Spacing.s4, bottom: Spacing.s4 })
  }

  @Builder
  pageTurnButton(opt: PageTurnOption) {
    Column({ space: 6 }) {
      Text(opt.icon)
        .fontSize(24)
        .fontColor(this.pageTurnMode === opt.value
          ? useColor(AccentColors.primary, this.isDark)
          : useColor(TextColors.secondary, this.isDark))
      Text(opt.label)
        .fontSize(FontSizeToken.caption1)
        .fontColor(this.pageTurnMode === opt.value
          ? useColor(AccentColors.primary, this.isDark)
          : useColor(TextColors.tertiary, this.isDark))
    }
    .layoutWeight(1)
    .height(72)
    .borderRadius(Radius.lg)
    .backgroundColor(useColor(BgColors.secondary, this.isDark))
    .border({
      width: this.pageTurnMode === opt.value ? 2 : 1,
      color: this.pageTurnMode === opt.value
        ? useColor(AccentColors.primary, this.isDark)
        : useColor(BorderColors.secondary, this.isDark),
    })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .animation({
      duration: MotionDuration.fast,
      curve: MotionEasing.standard,
    })
    .onClick(() => this.handlePageTurn(opt.value))
  }

  /** Section E：字体 */
  @Builder
  fontSection() {
    Column({ space: 0 }) {
      this.sectionHeader('字体')

      Row({ space: Spacing.s3 }) {
        ForEach(FONT_OPTIONS, (opt: FontOption) => {
          this.fontButton(opt)
        }, (opt: FontOption) => `font-${opt.value}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Spacing.s4, bottom: Spacing.s4 })
  }

  @Builder
  fontButton(opt: FontOption) {
    Column({ space: 4 }) {
      Text('字Aa')
        .fontSize(18)
        .fontFamily(opt.family)
        .fontColor(this.readerFont === opt.value
          ? useColor(AccentColors.primary, this.isDark)
          : useColor(TextColors.primary, this.isDark))
      Text(opt.label)
        .fontSize(FontSizeToken.caption1)
        .fontColor(this.readerFont === opt.value
          ? useColor(AccentColors.primary, this.isDark)
          : useColor(TextColors.tertiary, this.isDark))
    }
    .layoutWeight(1)
    .height(64)
    .borderRadius(Radius.lg)
    .backgroundColor(useColor(BgColors.secondary, this.isDark))
    .border({
      width: this.readerFont === opt.value ? 2 : 1,
      color: this.readerFont === opt.value
        ? useColor(AccentColors.primary, this.isDark)
        : useColor(BorderColors.secondary, this.isDark),
    })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .animation({
      duration: MotionDuration.fast,
      curve: MotionEasing.standard,
    })
    .onClick(() => this.handleFont(opt.value))
  }

  @Builder
  sheetContent() {
    Column({ space: 0 }) {
      this.fontSizeSection()
      Divider()
        .color(useColor(SurfaceColors.divider, this.isDark))
        .strokeWidth(0.5)
      this.lineHeightSection()
      Divider()
        .color(useColor(SurfaceColors.divider, this.isDark))
        .strokeWidth(0.5)
      this.themeSection()
      Divider()
        .color(useColor(SurfaceColors.divider, this.isDark))
        .strokeWidth(0.5)
      this.pageTurnSection()
      Divider()
        .color(useColor(SurfaceColors.divider, this.isDark))
        .strokeWidth(0.5)
      this.fontSection()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    AppSheet({
      visible: $visible,
      title: '阅读设置',
      isDark: this.isDark,
      // 弹窗高度档位：0.55 / 0.75 / 0.9，初次出现停在 0.75
      snapPoints: [0.55, 0.75, 0.9],
      sheetBody: () => {
        this.sheetContent();
      },
    })
  }
}
