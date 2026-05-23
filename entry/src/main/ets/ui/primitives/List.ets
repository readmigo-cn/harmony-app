/**
 * List.ets — 米果智读 HarmonyOS 列表组件
 *
 * 包含：
 *   - ListItemData        列表项数据接口
 *   - ListGroupData       分组数据接口（供 AppList 分组渲染使用）
 *   - AppListDataSource   LazyForEach 数据源（实现 IDataSource）
 *   - AppListItem         单行列表项（leading / title / subtitle / trailing）
 *   - AppList             高性能列表容器（LazyForEach + 下拉刷新 + 上滑加载更多 + 空状态 + 错误状态）
 */

import {
  TextColors,
  BgColors,
  BorderColors,
  AccentColors,
  SurfaceColors,
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
// 数据类型
// ─────────────────────────────────────────────

/** 列表项变体 */
export type ListItemVariant = 'default' | 'compact' | 'detailed';

/** 列表项分割线位置 */
export type ListItemDivider = 'top' | 'bottom' | 'none';

/** 单行列表项数据契约 */
export interface ListItemData {
  /** 唯一 key（LazyForEach 必须） */
  id: string;
  /** 主标题 */
  title: string;
  /** 副标题（detailed 变体展示） */
  subtitle?: string;
  /** leading 图标资源 */
  leadingIcon?: ResourceStr;
  /** trailing 文字（badge 数字 / 标签等） */
  trailingText?: string;
  /** 是否显示右侧 chevron */
  showChevron?: boolean;
  /** 是否禁用 */
  disabled?: boolean;
  /** 透传给业务层的原始数据 */
  data?: object;
}

/** 分组数据（AppList 分组模式） */
export interface ListGroupData {
  /** 分组标题（sticky header） */
  groupLabel: string;
  /** 组内数据 */
  items: ListItemData[];
}

// ─────────────────────────────────────────────
// LazyForEach 数据源
// ─────────────────────────────────────────────

/**
 * AppListDataSource
 * 实现 IDataSource 接口，支持 LazyForEach 按需渲染。
 * 大列表（>100条）时显著减少内存占用。
 */
export class AppListDataSource implements IDataSource {
  private items: ListItemData[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(items: ListItemData[] = []) {
    this.items = items;
  }

  /** 重置数据（下拉刷新后调用） */
  reset(items: ListItemData[]): void {
    this.items = [...items];
    this.notifyDataReload();
  }

  /** 追加数据（加载更多后调用） */
  append(newItems: ListItemData[]): void {
    const start = this.items.length;
    this.items.push(...newItems);
    for (let i = start; i < this.items.length; i++) {
      this.notifyDataAdd(i);
    }
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ListItemData {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  private notifyDataReload(): void {
    this.listeners.forEach(l => l.onDataReloaded());
  }

  private notifyDataAdd(index: number): void {
    this.listeners.forEach(l => l.onDataAdd(index));
  }
}

// ─────────────────────────────────────────────
// AppListItem 单行列表项
// ─────────────────────────────────────────────

/**
 * AppListItem — 单行列表项组件
 *
 * 变体：
 *   default  — 标准高度 56vp，显示 title
 *   compact  — 紧凑高度 44vp，显示 title（密集列表）
 *   detailed — 高度 64vp，显示 title + subtitle（两行信息）
 *
 * Slots（通过 @BuilderParam 注入）：
 *   leadingBuilder  — 自定义 leading 区域（优先于 leadingIcon）
 *   trailingBuilder — 自定义 trailing 区域（优先于 trailingText + chevron）
 */
@Component
export struct AppListItem {
  /** 列表项数据 */
  item: ListItemData = { id: '', title: '' };
  /** 变体 */
  variant: ListItemVariant = 'default';
  /** 分割线位置 */
  divider: ListItemDivider = 'bottom';
  /** 是否暗色模式 */
  isDark: boolean = false;
  /** 点击回调 */
  onTap?: (item: ListItemData) => void;
  /** 自定义 leading 插槽 */
  @BuilderParam leadingBuilder: (() => void) | undefined = undefined;
  /** 自定义 trailing 插槽 */
  @BuilderParam trailingBuilder: (() => void) | undefined = undefined;

  @State private pressed: boolean = false;

  /** 根据变体返回行高 */
  private get rowHeight(): number {
    switch (this.variant) {
      case 'compact': return 44;
      case 'detailed': return 64;
      default: return 56;
    }
  }

  /** 根据按压 / 禁用状态返回背景色 */
  private get rowBg(): ResourceColor {
    if (this.item.disabled) {
      return useColor(BgColors.secondary, this.isDark);
    }
    if (this.pressed) {
      return useColor(BgColors.tertiary, this.isDark);
    }
    return useColor(BgColors.elevated, this.isDark);
  }

  @Builder
  defaultLeading() {
    if (this.item.leadingIcon) {
      Image(this.item.leadingIcon)
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .opacity(this.item.disabled ? 0.4 : 1.0)
    }
  }

  @Builder
  defaultTrailing() {
    Row({ space: Spacing.s2 }) {
      // trailing 文字（badge / 数量等）
      if (this.item.trailingText) {
        Text(this.item.trailingText)
          .fontSize(FontSizeToken.footnote)
          .fontFamily(FontFamily.ui)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
          .opacity(this.item.disabled ? 0.4 : 1.0)
      }
      // 右箭头
      if (this.item.showChevron) {
        Text('›')
          .fontSize(FontSizeToken.title3)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
          .opacity(this.item.disabled ? 0.4 : 1.0)
      }
    }
  }

  build() {
    Column() {
      // 顶部分割线
      if (this.divider === 'top') {
        Divider()
          .color(useColor(SurfaceColors.divider, this.isDark))
          .strokeWidth(0.5)
      }

      // 行主体
      Row({ space: Spacing.s4 }) {
        // ── Leading 区域 ──
        if (this.leadingBuilder !== undefined) {
          this.leadingBuilder()
        } else {
          this.defaultLeading()
        }

        // ── 文字区域 ──
        Column({ space: Spacing.s0_5 }) {
          Text(this.item.title)
            .fontSize(FontSizeToken.body)
            .fontFamily(FontFamily.ui)
            .fontWeight(FontWeightToken.regular)
            .lineHeight(LineHeightToken.body)
            .fontColor(
              this.item.disabled
                ? useColor(TextColors.disabled, this.isDark)
                : useColor(TextColors.primary, this.isDark)
            )
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // subtitle：仅 detailed 变体展示
          if (this.variant === 'detailed' && this.item.subtitle) {
            Text(this.item.subtitle)
              .fontSize(FontSizeToken.footnote)
              .fontFamily(FontFamily.ui)
              .fontWeight(FontWeightToken.regular)
              .lineHeight(LineHeightToken.footnote)
              .fontColor(
                this.item.disabled
                  ? useColor(TextColors.disabled, this.isDark)
                  : useColor(TextColors.secondary, this.isDark)
              )
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // ── Trailing 区域 ──
        if (this.trailingBuilder !== undefined) {
          this.trailingBuilder()
        } else {
          this.defaultTrailing()
        }
      }
      .width('100%')
      .height(this.rowHeight)
      .padding({ left: Spacing.s4, right: Spacing.s4 })
      .backgroundColor(this.rowBg)
      .alignItems(VerticalAlign.Center)

      // 底部分割线
      if (this.divider === 'bottom') {
        Divider()
          .color(useColor(SurfaceColors.divider, this.isDark))
          .strokeWidth(0.5)
          .margin({ left: Spacing.s4 })
      }
    }
    .width('100%')
    .opacity(this.item.disabled ? 0.6 : 1.0)
    // 触摸反馈
    .onTouch((event: TouchEvent) => {
      if (this.item.disabled) return;
      if (event.type === TouchType.Down) {
        animateTo({ duration: MotionDuration.fast, curve: MotionEasing.decelerate }, () => {
          this.pressed = true;
        });
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        animateTo({ duration: MotionDuration.fast, curve: MotionEasing.accelerate }, () => {
          this.pressed = false;
        });
      }
    })
    .onClick(() => {
      if (!this.item.disabled) {
        this.onTap?.(this.item);
      }
    })
  }
}

// ─────────────────────────────────────────────
// AppList 列表容器
// ─────────────────────────────────────────────

/**
 * AppList — 高性能列表容器
 *
 * 特性：
 *   - LazyForEach 按需渲染，降低大列表内存占用
 *   - Refresh 组件集成下拉刷新（onRefresh 回调）
 *   - 触底时触发 onLoadMore 回调（加载更多）
 *   - 分组模式：传入 groups 时自动渲染 sticky ListItemGroup header
 *   - 空状态 / 错误状态插槽（@BuilderParam）
 */
@Component
export struct AppList {
  /** 扁平数据（与 groups 二选一） */
  dataSource: AppListDataSource = new AppListDataSource();
  /** 分组数据（与 dataSource 二选一） */
  groups?: ListGroupData[];
  /** 列表项变体 */
  variant: ListItemVariant = 'default';
  /** 列表项分割线 */
  divider: ListItemDivider = 'bottom';
  /** 是否暗色模式 */
  isDark: boolean = false;
  /** 是否显示列表项之间的 Divider */
  showDividers: boolean = true;
  /** 是否正在刷新 */
  refreshing: boolean = false;
  /** 是否正在加载更多 */
  loadingMore: boolean = false;
  /** 是否还有更多数据 */
  hasMore: boolean = false;
  /** 是否错误状态 */
  isError: boolean = false;
  /** 下拉刷新回调 */
  onRefresh?: () => void;
  /** 加载更多回调 */
  onLoadMore?: () => void;
  /** 列表项点击回调 */
  onItemTap?: (item: ListItemData) => void;
  /** 空状态插槽 */
  @BuilderParam emptyBuilder: (() => void) | undefined = undefined;
  /** 错误状态插槽 */
  @BuilderParam errorBuilder: (() => void) | undefined = undefined;
  /** 自定义列表项渲染插槽（如需完全自定义行） */
  @BuilderParam itemBuilder: ((item: ListItemData) => void) | undefined = undefined;

  @Builder
  defaultEmpty() {
    Column({ space: Spacing.s4 }) {
      Text('暂无内容')
        .fontSize(FontSizeToken.callout)
        .fontFamily(FontFamily.ui)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
    }
    .width('100%')
    .padding({ top: Spacing.s16 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  defaultError() {
    Column({ space: Spacing.s4 }) {
      Text('加载失败，请下拉重试')
        .fontSize(FontSizeToken.callout)
        .fontFamily(FontFamily.ui)
        .fontColor(useColor(TextColors.secondary, this.isDark))
    }
    .width('100%')
    .padding({ top: Spacing.s16 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  loadMoreFooter() {
    Row({ space: Spacing.s3 }) {
      if (this.loadingMore) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(useColor(AccentColors.primary, this.isDark))
        Text('加载中...')
          .fontSize(FontSizeToken.footnote)
          .fontFamily(FontFamily.ui)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
      } else if (!this.hasMore && this.dataSource.totalCount() > 0) {
        Text('已全部加载')
          .fontSize(FontSizeToken.footnote)
          .fontFamily(FontFamily.ui)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
      }
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  groupStickyHeader(label: string) {
    Row() {
      Text(label)
        .fontSize(FontSizeToken.footnote)
        .fontFamily(FontFamily.ui)
        .fontWeight(FontWeightToken.medium)
        .fontColor(useColor(TextColors.secondary, this.isDark))
        .textCase(TextCase.UpperCase)
    }
    .width('100%')
    .height(28)
    .padding({ left: Spacing.s4, right: Spacing.s4 })
    .backgroundColor(useColor(BgColors.secondary, this.isDark))
  }

  @Builder
  flatList() {
    // 数据为空时展示空状态
    if (this.dataSource.totalCount() === 0 && !this.refreshing) {
      if (this.isError) {
        if (this.errorBuilder !== undefined) {
          this.errorBuilder()
        } else {
          this.defaultError()
        }
      } else {
        if (this.emptyBuilder !== undefined) {
          this.emptyBuilder()
        } else {
          this.defaultEmpty()
        }
      }
    } else {
      List() {
        // 使用 LazyForEach 按需渲染，cachedCount=5 保留屏幕外缓冲
        LazyForEach(this.dataSource, (item: ListItemData) => {
          ListItem() {
            if (this.itemBuilder !== undefined) {
              this.itemBuilder(item)
            } else {
              AppListItem({
                item: item,
                variant: this.variant,
                divider: this.showDividers ? this.divider : 'none',
                isDark: this.isDark,
                onTap: this.onItemTap,
              })
            }
          }
        }, (item: ListItemData) => item.id)
        // 加载更多 footer
        ListItem() {
          this.loadMoreFooter()
        }
      }
      .width('100%')
      .cachedCount(5)
      .divider(this.showDividers ? {
        strokeWidth: 0,  // 分割线由 AppListItem 内部自行绘制
        color: 'transparent',
      } : undefined)
      .onScrollIndex((_start: number, end: number) => {
        // 触底触发加载更多
        const total = this.dataSource.totalCount();
        if (end >= total - 2 && this.hasMore && !this.loadingMore) {
          this.onLoadMore?.();
        }
      })
    }
  }

  @Builder
  groupedList() {
    if (!this.groups || this.groups.length === 0) {
      if (this.emptyBuilder !== undefined) {
        this.emptyBuilder()
      } else {
        this.defaultEmpty()
      }
    } else {
      List({ space: 0 }) {
        ForEach(this.groups, (group: ListGroupData) => {
          ListItemGroup({
            header: this.groupStickyHeader(group.groupLabel),
          }) {
            ForEach(group.items, (item: ListItemData) => {
              ListItem() {
                if (this.itemBuilder !== undefined) {
                  this.itemBuilder(item)
                } else {
                  AppListItem({
                    item: item,
                    variant: this.variant,
                    divider: this.showDividers ? this.divider : 'none',
                    isDark: this.isDark,
                    onTap: this.onItemTap,
                  })
                }
              }
            }, (item: ListItemData) => item.id)
          }
        }, (g: ListGroupData) => g.groupLabel)
      }
      .width('100%')
      .sticky(StickyStyle.Header)
    }
  }

  build() {
    Refresh({ refreshing: $$this.refreshing }) {
      // 分组 vs 扁平
      if (this.groups && this.groups.length >= 0) {
        this.groupedList()
      } else {
        this.flatList()
      }
    }
    .onRefreshing(() => {
      this.onRefresh?.();
    })
    .width('100%')
    .height('100%')
  }
}
