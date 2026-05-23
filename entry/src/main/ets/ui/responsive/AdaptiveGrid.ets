/**
 * AdaptiveGrid.ets — 自适应栅格容器
 *
 * 基于 ArkUI 原生 GridRow / GridCol，封装 BreakpointMap 配置：
 *   - columns:    每个断点的总列数      默认 { xs:4, sm:6, md:8, lg:12 }
 *   - gutter:     每个断点的间距(vp)    默认 { xs:8, sm:12, md:16, lg:16 }
 *   - childSpan:  每个断点子元素占多少列 由 children 数组传入
 *
 * 这里不做花哨的二级封装：把 GridRow 的 BreakpointMap 字面量直接透传给框架，
 * 避免与原生断点机制双轨。AppStorage 中的 'app_breakpoint' 仅作为 UI 决策辅助。
 *
 * ArkTS 限制：struct 不支持泛型，因此 items 用 ESObject 数组承载，
 * 由调用方在 itemBuilder 内做类型断言。
 *
 * 用法：
 *   AdaptiveGrid({
 *     items: data as ESObject[],
 *     columns: { xs: 4, sm: 6, md: 8, lg: 12 },
 *     childSpan: { xs: 2, sm: 3, md: 2, lg: 2 },
 *     itemBuilder: (item, index) => {
 *       const b = item as Book;
 *       Text(b.title)
 *     }
 *   })
 */

import { Spacing } from '../../core/theme/AppSpacing';
import { Breakpoint, STORAGE_KEY_BREAKPOINT } from '../../core/theme/Breakpoints';

/** 与 ArkUI BreakpointMap 形状一致的配置 */
export interface AdaptiveBreakpointMap {
  xs?: number;
  sm?: number;
  md?: number;
  lg?: number;
  xl?: number;
}

/** 缺省列数 —— 跟随 HarmonyOS 设计规范 4/6/8/12 */
const DEFAULT_COLUMNS: AdaptiveBreakpointMap = {
  xs: 4,
  sm: 6,
  md: 8,
  lg: 12,
  xl: 12,
};

/** 缺省间距（vp） */
const DEFAULT_GUTTER: AdaptiveBreakpointMap = {
  xs: Spacing.s2, // 8
  sm: Spacing.s3, // 12
  md: Spacing.s4, // 16
  lg: Spacing.s4, // 16
  xl: Spacing.s4, // 16
};

/** 缺省子元素占用列数（每个断点都占整行的固定份额） */
const DEFAULT_CHILD_SPAN: AdaptiveBreakpointMap = {
  xs: 2, // 4 列布局 → 一行放 2 个
  sm: 3, // 6 列布局 → 一行放 2 个
  md: 2, // 8 列布局 → 一行放 4 个
  lg: 2, // 12 列布局 → 一行放 6 个
  xl: 2, // 同 lg
};

/**
 * 通用自适应栅格 —— 元素同质场景（书库、卡片墙）
 *
 * @param items        数据数组（ESObject[]，调用方做类型断言）
 * @param columns      每断点总列数（覆盖默认）
 * @param gutter       每断点间距（覆盖默认）
 * @param childSpan    每断点单元素占多少列（覆盖默认）
 * @param itemBuilder  单元素 Builder
 * @param keyExtractor 唯一 key（默认 index）
 */
@Component
export struct AdaptiveGrid {
  @Prop @Watch('onItemsChanged') items: ESObject[] = [];
  @Prop columns: AdaptiveBreakpointMap | undefined = undefined;
  @Prop gutter: AdaptiveBreakpointMap | undefined = undefined;
  @Prop childSpan: AdaptiveBreakpointMap | undefined = undefined;
  @StorageProp(STORAGE_KEY_BREAKPOINT) currentBp: Breakpoint = Breakpoint.MD;

  @BuilderParam itemBuilder: ((item: ESObject, index: number) => void) | undefined = undefined;
  keyExtractor: ((item: ESObject, index: number) => string) | undefined = undefined;

  @State private renderTick: number = 0;

  onItemsChanged(): void {
    // items 引用变更时手动触发一次重渲染
    this.renderTick++;
  }

  /** 合并用户传入的 BreakpointMap 与默认值 */
  private mergeMap(
    user: AdaptiveBreakpointMap | undefined,
    fallback: AdaptiveBreakpointMap,
  ): AdaptiveBreakpointMap {
    if (!user) return fallback;
    return {
      xs: user.xs ?? fallback.xs,
      sm: user.sm ?? fallback.sm,
      md: user.md ?? fallback.md,
      lg: user.lg ?? fallback.lg,
      xl: user.xl ?? fallback.xl,
    };
  }

  /** 当前断点对应的子元素 span（用于 GridCol.span） */
  private spanForCurrent(): number {
    const span: AdaptiveBreakpointMap = this.mergeMap(this.childSpan, DEFAULT_CHILD_SPAN);
    switch (this.currentBp) {
      case Breakpoint.XS: return span.xs ?? 2;
      case Breakpoint.SM: return span.sm ?? 3;
      case Breakpoint.MD: return span.md ?? 2;
      case Breakpoint.LG: return span.lg ?? 2;
      case Breakpoint.XL: return span.xl ?? 2;
      default: return 2;
    }
  }

  build() {
    const cols: AdaptiveBreakpointMap = this.mergeMap(this.columns, DEFAULT_COLUMNS);
    const gut: AdaptiveBreakpointMap = this.mergeMap(this.gutter, DEFAULT_GUTTER);

    GridRow({
      columns: {
        xs: cols.xs,
        sm: cols.sm,
        md: cols.md,
        lg: cols.lg,
        xl: cols.xl,
      },
      gutter: {
        x: {
          xs: gut.xs,
          sm: gut.sm,
          md: gut.md,
          lg: gut.lg,
          xl: gut.xl,
        },
        y: {
          xs: gut.xs,
          sm: gut.sm,
          md: gut.md,
          lg: gut.lg,
          xl: gut.xl,
        },
      },
      breakpoints: {
        // 阈值与 Breakpoints.ets 中的 getCurrentBreakpoint 对齐
        value: ['320vp', '520vp', '840vp', '1280vp'],
        reference: BreakpointsReference.WindowSize,
      },
    }) {
      ForEach(this.items, (item: ESObject, index: number) => {
        GridCol({
          span: this.spanForCurrent(),
        }) {
          if (this.itemBuilder) {
            this.itemBuilder(item, index);
          }
        }
      }, (item: ESObject, index: number) => {
        if (this.keyExtractor) {
          return this.keyExtractor(item, index);
        }
        return `idx-${index}-${this.renderTick}`;
      })
    }
    .width('100%')
  }
}
