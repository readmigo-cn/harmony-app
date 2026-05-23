/**
 * Tab.ets — 米果智读 HarmonyOS 标签页组件集
 *
 * 包含：
 *   - AppTab       单个 Tab 标签项（用于 AppTabs 的 tabBar 插槽）
 *   - AppTabs      顶部/分段式标签容器（包裹系统 Tabs，统一视觉风格）
 *   - TabBarItem   底部导航栏单项数据类型
 *   - AppTabBar    主导航底部 TabBar（图标 + 标签 + 徽标支持）
 */

import {
  TextColors,
  BgColors,
  AccentColors,
  BorderColors,
  SurfaceColors,
  TabBarColors,
  BrandPalette,
  GrayPalette,
  useColor,
} from '../../core/theme/AppColors';
import {
  FontFamily,
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../core/theme/AppTypography';
import {
  Spacing,
  Radius,
  MotionDuration,
  MotionEasing,
} from '../../core/theme/AppSpacing';

// ─────────────────────────────────────────────
// 类型定义
// ─────────────────────────────────────────────

/** AppTabs 变体 */
export type TabsVariant = 'top' | 'bottom' | 'segmented';

/** AppTabs 指示器样式 */
export type TabIndicator = 'underline' | 'pill' | 'none';

/** 底部导航栏单项定义 */
export interface TabBarItem {
  /** 标签文字 */
  label: string;
  /** 普通状态图标资源（可为 Resource 或 SVG 路径字符串） */
  icon: ResourceStr;
  /** 激活状态图标资源（未提供时沿用 icon） */
  iconActive?: ResourceStr;
  /** 数字徽标（>0 时显示） */
  badge?: number;
  /** 是否显示小红点（badge=0 但 showDot=true 时展示） */
  showDot?: boolean;
  /** 路由名称（与 RouterService 集成时使用） */
  route?: string;
}

// ─────────────────────────────────────────────
// AppTab — 单个标签项（用于 AppTabs.tabBar 插槽）
// ─────────────────────────────────────────────

/**
 * AppTab — 单个 Tab 标签项
 *
 * 在 AppTabs 的 tabBar 插槽中使用，外部通过 isActive / variant / indicator
 * 控制激活样式，使整个 TabBar 视觉一致。
 */
@Component
export struct AppTab {
  /** 标签文字 */
  label: string = '';
  /** 可选图标（顶部 Tab 通常无图标） */
  icon?: ResourceStr;
  /** 是否为激活状态 */
  isActive: boolean = false;
  /** 指示器样式 */
  indicator: TabIndicator = 'underline';
  /** 是否暗色模式 */
  isDark: boolean = false;

  /** 激活文字颜色 */
  private get activeColor(): ResourceColor {
    return useColor(AccentColors.primary, this.isDark);
  }

  /** 非激活文字颜色 */
  private get inactiveColor(): ResourceColor {
    return useColor(TextColors.secondary, this.isDark);
  }

  build() {
    Column({ space: Spacing.s1 }) {
      // 图标（可选）
      if (this.icon) {
        Image(this.icon)
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
          .fillColor(this.isActive ? this.activeColor : this.inactiveColor)
      }

      // 标签文字
      Text(this.label)
        .fontSize(FontSizeToken.footnote)
        .fontFamily(FontFamily.ui)
        .fontWeight(this.isActive ? FontWeightToken.semibold : FontWeightToken.regular)
        .lineHeight(LineHeightToken.footnote)
        .fontColor(this.isActive ? this.activeColor : this.inactiveColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 指示器 — underline
      if (this.indicator === 'underline') {
        Column()
          .width(this.isActive ? '100%' : 0)
          .height(2)
          .borderRadius(Radius.full)
          .backgroundColor(this.activeColor)
          .animation({
            duration: MotionDuration.fast,
            curve: MotionEasing.standard,
          })
      }
    }
    .padding({
      left: Spacing.s4,
      right: Spacing.s4,
      top: Spacing.s3,
      bottom: this.indicator === 'underline' ? Spacing.s2 : Spacing.s3,
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    // pill 指示器：激活时整体背景变色
    .backgroundColor(
      this.indicator === 'pill' && this.isActive
        ? useColor(BgColors.secondary, this.isDark)
        : 'transparent'
    )
    .borderRadius(this.indicator === 'pill' ? Radius.full : Radius.none)
    .animation({
      duration: MotionDuration.fast,
      curve: MotionEasing.standard,
    })
  }
}

// ─────────────────────────────────────────────
// AppTabs — 标签容器
// ─────────────────────────────────────────────

/**
 * AppTabs — 标签页容器
 *
 * 包裹 HarmonyOS 原生 Tabs 组件，提供品牌化的 tabBar 样式：
 *   top        — 顶部标签，Underline 指示器，可滚动（超出宽度时）
 *   bottom     — 底部标签（与 AppTabBar 区分，适用于内页 TabView）
 *   segmented  — 分段控制器（Pill 指示器），固定等分宽度
 *
 * onChange 回调暴露当前 index。
 */
@Component
export struct AppTabs {
  /** Tab 标签文字列表 */
  labels: string[] = [];
  /** Tab 图标列表（可选，与 labels 等长） */
  icons?: ResourceStr[];
  /** 当前激活 index（双向绑定） */
  @Link currentIndex: number;
  /** Tab 样式变体 */
  variant: TabsVariant = 'top';
  /** 指示器样式（segmented 变体固定为 pill） */
  indicator: TabIndicator = 'underline';
  /** 是否暗色模式 */
  isDark: boolean = false;
  /** index 切换回调 */
  onChange?: (index: number) => void;
  /** Tab 内容插槽（与 labels 等长，按 index 渲染） */
  @BuilderParam tabContentBuilder: ((index: number) => void) | undefined = undefined;

  /** 将变体映射为 HarmonyOS TabsBarPosition */
  private get barPosition(): BarPosition {
    return this.variant === 'bottom' ? BarPosition.End : BarPosition.Start;
  }

  @Builder
  buildTabBar(index: number) {
    AppTab({
      label: this.labels[index] ?? '',
      icon: this.icons ? this.icons[index] : undefined,
      isActive: this.currentIndex === index,
      indicator: this.variant === 'segmented' ? 'pill' : this.indicator,
      isDark: this.isDark,
    })
  }

  @Builder
  segmentedBar() {
    Row() {
      ForEach(this.labels, (label: string, idx?: number) => {
        const i = idx ?? 0;
        Column() {
          Text(label)
            .fontSize(FontSizeToken.callout)
            .fontFamily(FontFamily.ui)
            .fontWeight(
              this.currentIndex === i ? FontWeightToken.semibold : FontWeightToken.regular
            )
            .fontColor(
              this.currentIndex === i
                ? useColor(AccentColors.primary, this.isDark)
                : useColor(TextColors.secondary, this.isDark)
            )
            .maxLines(1)
        }
        .layoutWeight(1)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(Radius.lg)
        .backgroundColor(
          this.currentIndex === i
            ? useColor(BgColors.elevated, this.isDark)
            : 'transparent'
        )
        .animation({ duration: MotionDuration.fast, curve: MotionEasing.standard })
        .onClick(() => {
          this.currentIndex = i;
          this.onChange?.(i);
        })
      }, (label: string) => label)
    }
    .width('100%')
    .height(44)
    .padding(Spacing.s1)
    .borderRadius(Radius.xl)
    .backgroundColor(useColor(BgColors.secondary, this.isDark))
    .margin({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s3, bottom: Spacing.s3 })
  }

  build() {
    Column() {
      // 分段控制器使用独立实现（视觉与系统 Tabs 差异较大）
      if (this.variant === 'segmented') {
        this.segmentedBar()
        // 内容区
        if (this.tabContentBuilder !== undefined) {
          this.tabContentBuilder(this.currentIndex)
        }
      } else {
        // 顶部 / 底部 Tab 使用系统 Tabs 组件以获得原生手势 & 过渡动效
        Tabs({ barPosition: this.barPosition, index: this.currentIndex }) {
          ForEach(this.labels, (_label: string, idx?: number) => {
            const i = idx ?? 0;
            TabContent() {
              if (this.tabContentBuilder !== undefined) {
                this.tabContentBuilder(i)
              }
            }
            .tabBar(this.buildTabBar(i))
          }, (label: string) => label)
        }
        .barMode(this.labels.length > 5 ? BarMode.Scrollable : BarMode.Fixed)
        .barWidth('100%')
        .barHeight(this.variant === 'top' ? 48 : 56)
        .barBackgroundColor(useColor(BgColors.elevated, this.isDark))
        .divider({
          strokeWidth: 0.5,
          color: useColor(SurfaceColors.divider, this.isDark),
        })
        .animationDuration(MotionDuration.normal)
        .onChange((index: number) => {
          this.currentIndex = index;
          this.onChange?.(index);
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

// ─────────────────────────────────────────────
// AppTabBar — 主导航底部 TabBar
// ─────────────────────────────────────────────

/**
 * AppTabBar — App 主导航底部 Bar
 *
 * 适用场景：书库 / 发现 / 笔记 / 我 四大主 Tab。
 * 特性：
 *   - 图标 + 标签 + 激活动效
 *   - 数字徽标（badge > 0）/ 小红点（showDot）
 *   - 底部安全区自适应（bottomSafeArea 参数）
 *   - 激活时图标缩放 1.0 → 1.08（弹簧曲线）
 */
@Component
export struct AppTabBar {
  /** 导航项列表 */
  items: TabBarItem[] = [];
  /** 当前激活 index（双向绑定） */
  @Link selectedIndex: number;
  /** 是否暗色模式 */
  isDark: boolean = false;
  /** 底部安全区高度（vp），HarmonyOS 设备通常为 34vp，无刘海设备为 0 */
  bottomSafeArea: number = 0;
  /** 切换回调 */
  onSelect?: (index: number, item: TabBarItem) => void;

  @Builder
  badgeView(item: TabBarItem) {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 图标
      Image(this.selectedIndex === this.items.indexOf(item) && item.iconActive
        ? item.iconActive!
        : item.icon)
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .fillColor(
          this.selectedIndex === this.items.indexOf(item)
            ? useColor(TabBarColors.iconActive, this.isDark)
            : useColor(TabBarColors.icon, this.isDark)
        )

      // 数字徽标
      if (item.badge && item.badge > 0) {
        Text(item.badge > 99 ? '99+' : `${item.badge}`)
          .fontSize(FontSizeToken.caption2)
          .fontFamily(FontFamily.ui)
          .fontWeight(FontWeightToken.medium)
          .fontColor('#FFFFFF')
          .backgroundColor('#FF6B6B')
          .borderRadius(Radius.full)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .minWidth(16)
          .height(16)
          .textAlign(TextAlign.Center)
          .offset({ x: 8, y: -4 })
      } else if (item.showDot) {
        // 小红点
        Column()
          .width(8)
          .height(8)
          .borderRadius(Radius.full)
          .backgroundColor('#FF6B6B')
          .offset({ x: 4, y: -2 })
      }
    }
  }

  build() {
    Column() {
      // 顶部分割线
      Divider()
        .color(useColor(SurfaceColors.divider, this.isDark))
        .strokeWidth(0.5)

      Row() {
        ForEach(this.items, (item: TabBarItem, idx?: number) => {
          const i = idx ?? 0;
          const isActive = this.selectedIndex === i;

          Column({ space: Spacing.s1 }) {
            // 图标（含徽标）
            this.badgeView(item)

            // 标签文字
            Text(item.label)
              .fontSize(FontSizeToken.caption1)
              .fontFamily(FontFamily.ui)
              .fontWeight(isActive ? FontWeightToken.medium : FontWeightToken.regular)
              .lineHeight(LineHeightToken.caption1)
              .fontColor(
                isActive
                  ? useColor(TabBarColors.iconActive, this.isDark)
                  : useColor(TabBarColors.icon, this.isDark)
              )
              .maxLines(1)
          }
          .layoutWeight(1)
          .height(49)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          // 激活时图标组整体微弹放大
          .scale(isActive ? { x: 1.05, y: 1.05 } : { x: 1.0, y: 1.0 })
          .animation({
            duration: MotionDuration.fast,
            curve: MotionEasing.spring,
          })
          .onClick(() => {
            if (this.selectedIndex !== i) {
              this.selectedIndex = i;
              this.onSelect?.(i, item);
            }
          })
        }, (item: TabBarItem) => item.label)
      }
      .width('100%')
      .backgroundColor(useColor(TabBarColors.bg, this.isDark))

      // 底部安全区占位
      if (this.bottomSafeArea > 0) {
        Column()
          .width('100%')
          .height(this.bottomSafeArea)
          .backgroundColor(useColor(TabBarColors.bg, this.isDark))
      }
    }
    .width('100%')
  }
}
