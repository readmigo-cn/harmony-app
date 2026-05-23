/**
 * ResponsiveContainer.ets — 响应式 Builder 路由器
 *
 * 不同断点 / 折叠状态 选用不同 Builder：
 *   xs / sm  →  mobile (默认)
 *   md       →  tablet (折叠屏 inner / 7-9" 平板)
 *   lg / xl  →  desktop (10"+ 平板 / 桌面投屏)
 *
 * 当对应 Builder 缺失时，回退到 fallback。
 *
 * 用法：
 *   ResponsiveContainer({
 *     mobile:   () => { this.buildMobile() },
 *     tablet:   () => { this.buildTablet() },
 *     desktop:  () => { this.buildDesktop() },
 *     fallback: () => { this.buildMobile() },  // required
 *   })
 *
 * 设计权衡：
 *   - ArkUI @Builder 不能直接当 optional 字段判空（值都是 () => void 不为 null），
 *     用 *Provided 布尔标记 + @Watch 同步当前 layout flavor。
 */

import { Breakpoint, STORAGE_KEY_BREAKPOINT, FoldStatus, STORAGE_KEY_FOLD_STATUS } from '../../core/theme/Breakpoints';

/** 当前选中的布局口味 */
export enum LayoutFlavor {
  MOBILE = 'mobile',
  TABLET = 'tablet',
  DESKTOP = 'desktop',
  FALLBACK = 'fallback',
}

@Component
export struct ResponsiveContainer {
  @StorageProp(STORAGE_KEY_BREAKPOINT) @Watch('refreshFlavor') currentBp: Breakpoint = Breakpoint.MD;
  @StorageProp(STORAGE_KEY_FOLD_STATUS) @Watch('refreshFlavor') foldStatus: FoldStatus = FoldStatus.UNKNOWN;

  /** 是否提供了对应 Builder（外部传入时务必置 true） */
  @Prop mobileProvided: boolean = false;
  @Prop tabletProvided: boolean = false;
  @Prop desktopProvided: boolean = false;

  /** Builder slot —— mobile / tablet / desktop 都是可选；fallback 必填 */
  @BuilderParam mobile: (() => void) | undefined = undefined;
  @BuilderParam tablet: (() => void) | undefined = undefined;
  @BuilderParam desktop: (() => void) | undefined = undefined;
  @BuilderParam fallback: (() => void) | undefined = undefined;

  @State private flavor: LayoutFlavor = LayoutFlavor.FALLBACK;

  aboutToAppear(): void {
    this.refreshFlavor();
  }

  /** 根据当前断点 + 折叠态选择布局口味 */
  private refreshFlavor(): void {
    let next: LayoutFlavor = LayoutFlavor.FALLBACK;

    // 折叠屏完全展开优先走 desktop
    if (this.foldStatus === FoldStatus.EXPAND
        && (this.currentBp === Breakpoint.LG || this.currentBp === Breakpoint.XL)) {
      next = this.desktopProvided ? LayoutFlavor.DESKTOP : LayoutFlavor.TABLET;
    } else if (this.currentBp === Breakpoint.LG || this.currentBp === Breakpoint.XL) {
      next = this.desktopProvided ? LayoutFlavor.DESKTOP : LayoutFlavor.TABLET;
    } else if (this.currentBp === Breakpoint.MD) {
      next = this.tabletProvided ? LayoutFlavor.TABLET : LayoutFlavor.MOBILE;
    } else {
      // XS / SM → 默认 mobile
      next = this.mobileProvided ? LayoutFlavor.MOBILE : LayoutFlavor.FALLBACK;
    }

    // 选中的口味实际未提供 Builder → 进一步降级
    if (next === LayoutFlavor.DESKTOP && !this.desktopProvided) {
      next = this.tabletProvided ? LayoutFlavor.TABLET : (this.mobileProvided ? LayoutFlavor.MOBILE : LayoutFlavor.FALLBACK);
    }
    if (next === LayoutFlavor.TABLET && !this.tabletProvided) {
      next = this.mobileProvided ? LayoutFlavor.MOBILE : LayoutFlavor.FALLBACK;
    }
    if (next === LayoutFlavor.MOBILE && !this.mobileProvided) {
      next = LayoutFlavor.FALLBACK;
    }

    this.flavor = next;
  }

  build() {
    Stack() {
      if (this.flavor === LayoutFlavor.DESKTOP && this.desktopProvided && this.desktop) {
        this.desktop();
      } else if (this.flavor === LayoutFlavor.TABLET && this.tabletProvided && this.tablet) {
        this.tablet();
      } else if (this.flavor === LayoutFlavor.MOBILE && this.mobileProvided && this.mobile) {
        this.mobile();
      } else if (this.fallback) {
        this.fallback();
      }
    }
    .width('100%')
    .height('100%')
  }
}
