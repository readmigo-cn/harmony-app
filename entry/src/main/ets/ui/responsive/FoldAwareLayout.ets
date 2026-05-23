/**
 * FoldAwareLayout.ets — 折叠屏感知布局
 *
 * 三种排布：
 *   - 折叠态 (FOLDED)         → 单列，调用 folded()
 *   - 半折态 (HALF_FOLDED)    → 上下分屏，halfFoldedTop() + halfFoldedBottom()
 *                                若仅提供 halfFolded() 单 Builder 则等同折叠态
 *   - 展开态 (EXPAND / 默认)  → 左右分屏，expandedLeft() + expandedRight()
 *                                若用户用 expanded() 单 Builder 则全宽
 *
 * 不支持折叠屏的设备 (UNKNOWN)：
 *   - 当宽度 ≥ MD 时按 EXPAND 处理（让普通平板也能享受双栏）
 *   - 否则走 FOLDED
 *
 * 用法：
 *   FoldAwareLayout({
 *     foldedProvided: true,
 *     expandedLeftProvided: true,
 *     expandedRightProvided: true,
 *     folded:        () => this.singleColumn(),
 *     expandedLeft:  () => this.list(),
 *     expandedRight: () => this.detail(),
 *   })
 */

import { AppColors } from '../../core/theme/AppColors';
import { Spacing } from '../../core/theme/AppSpacing';
import {
  Breakpoint,
  FoldStatus,
  STORAGE_KEY_BREAKPOINT,
  STORAGE_KEY_FOLD_STATUS,
} from '../../core/theme/Breakpoints';

/** 当前布局模式 —— 决定 build() 走哪个分支 */
export enum FoldLayoutMode {
  FOLDED = 'folded',
  HALF_FOLDED = 'halfFolded',
  EXPANDED = 'expanded',
}

@Component
export struct FoldAwareLayout {
  @StorageProp(STORAGE_KEY_FOLD_STATUS) @Watch('refreshMode') foldStatus: FoldStatus = FoldStatus.UNKNOWN;
  @StorageProp(STORAGE_KEY_BREAKPOINT) @Watch('refreshMode') currentBp: Breakpoint = Breakpoint.MD;

  /** 标记 Builder 是否真的传了（@BuilderParam 没有 null 状态） */
  @Prop foldedProvided: boolean = true;
  @Prop halfFoldedProvided: boolean = false;
  @Prop halfFoldedTopProvided: boolean = false;
  @Prop halfFoldedBottomProvided: boolean = false;
  @Prop expandedProvided: boolean = false;
  @Prop expandedLeftProvided: boolean = false;
  @Prop expandedRightProvided: boolean = false;

  /** 单列 / 单 Builder 折叠态布局 */
  @BuilderParam folded: (() => void) | undefined = undefined;

  /** 半折态：可选 单 Builder（halfFolded） 或 上下分屏 (top + bottom) */
  @BuilderParam halfFolded: (() => void) | undefined = undefined;
  @BuilderParam halfFoldedTop: (() => void) | undefined = undefined;
  @BuilderParam halfFoldedBottom: (() => void) | undefined = undefined;

  /** 展开态：可选 单 Builder（expanded） 或 左右分屏 (left + right) */
  @BuilderParam expanded: (() => void) | undefined = undefined;
  @BuilderParam expandedLeft: (() => void) | undefined = undefined;
  @BuilderParam expandedRight: (() => void) | undefined = undefined;

  /** 左右分屏中左栏占比 (0~1)，默认 0.4 */
  @Prop expandedLeftRatio: number = 0.4;
  /** 上下分屏中上栏占比 (0~1)，默认 0.5 */
  @Prop halfFoldedTopRatio: number = 0.5;

  @State private mode: FoldLayoutMode = FoldLayoutMode.FOLDED;

  aboutToAppear(): void {
    this.refreshMode();
  }

  /** 根据 foldStatus + currentBp 决定布局模式 */
  private refreshMode(): void {
    if (this.foldStatus === FoldStatus.HALF_FOLDED
        && (this.halfFoldedProvided || (this.halfFoldedTopProvided && this.halfFoldedBottomProvided))) {
      this.mode = FoldLayoutMode.HALF_FOLDED;
      return;
    }

    const isWideEnough: boolean = this.currentBp === Breakpoint.LG
      || this.currentBp === Breakpoint.XL
      || this.currentBp === Breakpoint.MD;

    if (this.foldStatus === FoldStatus.EXPAND && isWideEnough
        && (this.expandedProvided || (this.expandedLeftProvided && this.expandedRightProvided))) {
      this.mode = FoldLayoutMode.EXPANDED;
      return;
    }

    // 普通平板（无折叠屏）：宽度足够也走 EXPANDED
    if (this.foldStatus === FoldStatus.UNKNOWN && isWideEnough
        && this.currentBp !== Breakpoint.MD  // MD 暂不强制双栏
        && (this.expandedProvided || (this.expandedLeftProvided && this.expandedRightProvided))) {
      this.mode = FoldLayoutMode.EXPANDED;
      return;
    }

    this.mode = FoldLayoutMode.FOLDED;
  }

  build() {
    if (this.mode === FoldLayoutMode.HALF_FOLDED) {
      // 半折态：上下分屏
      Column() {
        if (this.halfFoldedTopProvided && this.halfFoldedBottomProvided
            && this.halfFoldedTop && this.halfFoldedBottom) {
          Column() { this.halfFoldedTop() }
            .layoutWeight(this.halfFoldedTopRatio)
            .width('100%')
          Divider().strokeWidth(1).color(AppColors.divider)
          Column() { this.halfFoldedBottom() }
            .layoutWeight(1 - this.halfFoldedTopRatio)
            .width('100%')
        } else if (this.halfFoldedProvided && this.halfFolded) {
          this.halfFolded();
        } else if (this.folded) {
          this.folded();
        }
      }
      .width('100%')
      .height('100%')
    } else if (this.mode === FoldLayoutMode.EXPANDED) {
      // 展开态：左右分屏
      Row() {
        if (this.expandedLeftProvided && this.expandedRightProvided
            && this.expandedLeft && this.expandedRight) {
          Column() { this.expandedLeft() }
            .layoutWeight(this.expandedLeftRatio)
            .height('100%')
          Divider().vertical(true).strokeWidth(1).color(AppColors.divider)
          Column() { this.expandedRight() }
            .layoutWeight(1 - this.expandedLeftRatio)
            .height('100%')
        } else if (this.expandedProvided && this.expanded) {
          this.expanded();
        } else if (this.folded) {
          this.folded();
        }
      }
      .width('100%')
      .height('100%')
    } else {
      // 折叠态：单列
      Column() {
        if (this.foldedProvided && this.folded) {
          this.folded();
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: Spacing.s0, bottom: Spacing.s0 })
    }
  }
}
