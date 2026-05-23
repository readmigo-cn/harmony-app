/**
 * RouterAdapter.ets — W14-C 路由适配器
 *
 * 职责：
 *   - 检测设备 / 当前 breakpoint，决定是 push 手机版还是平板版页面
 *   - 提供语义化 API（pushLibrary / pushDiscover / pushReader / pushNotes），
 *     调用方不再关心 mobile vs tablet 的差异
 *   - 实际 NavPathStack 仍使用同一组 RoutePath；具体 mobile/tablet 切换
 *     在页面 build() 中通过 ResponsiveContainer / ifElse 完成（推荐做法）。
 *     本 Adapter 只负责给业务层 / 跨端接续 / Deep Link 一个一致的 API。
 *
 * 用法：
 *   RouterAdapter.pushLibrary();
 *   RouterAdapter.pushReader({ bookId: 'xxx', slug: 'xxx' });
 *   if (RouterAdapter.isTablet()) { ... }
 */

import { RouterService } from './RouterService';
import { RoutePath, ReaderRouteParams, NotesRouteParams, DiscoverRouteParams } from './RouteConstants';
import {
  Breakpoint,
  STORAGE_KEY_BREAKPOINT,
  STORAGE_KEY_FOLD_STATUS,
  STORAGE_KEY_WINDOW_WIDTH_VP,
  FoldStatus,
} from '../theme/Breakpoints';

/** 设备形态 —— UI 层语义化分类 */
export type DeviceClass = 'phone' | 'foldable-inner' | 'tablet';

export class RouterAdapter {
  /**
   * 当前是否为「平板宽度」。
   * 阈值：lg / xl 视为 tablet；md (520-839vp) 视为大手机 / 折叠内屏。
   * 折叠屏处于 EXPAND 状态时强制视为 tablet（即使宽度不到 lg，也启用双栏）。
   */
  static isTablet(): boolean {
    const bp: Breakpoint = AppStorage.Get<Breakpoint>(STORAGE_KEY_BREAKPOINT) ?? Breakpoint.MD;
    if (bp === Breakpoint.LG || bp === Breakpoint.XL) return true;
    const fold: FoldStatus = AppStorage.Get<FoldStatus>(STORAGE_KEY_FOLD_STATUS) ?? FoldStatus.UNKNOWN;
    return fold === FoldStatus.EXPAND;
  }

  /** 当前设备形态分类（粗粒度） */
  static getDeviceClass(): DeviceClass {
    const bp: Breakpoint = AppStorage.Get<Breakpoint>(STORAGE_KEY_BREAKPOINT) ?? Breakpoint.MD;
    const fold: FoldStatus = AppStorage.Get<FoldStatus>(STORAGE_KEY_FOLD_STATUS) ?? FoldStatus.UNKNOWN;
    if (fold === FoldStatus.EXPAND) return 'foldable-inner';
    if (bp === Breakpoint.LG || bp === Breakpoint.XL) return 'tablet';
    return 'phone';
  }

  /** 当前窗口 vp 宽度（直接读 AppStorage，UI 层做粗判用） */
  static getWindowWidthVp(): number {
    return AppStorage.Get<number>(STORAGE_KEY_WINDOW_WIDTH_VP) ?? 0;
  }

  // ─────────────────────────────────────────────
  // 语义化 push（route name 与 mobile 共用，平板差异由页面 build() 内部决定）
  // 这样路由栈 / Deep Link / 跨端接续不必区分手机 / 平板
  // ─────────────────────────────────────────────

  static pushLibrary(): void {
    RouterService.push(RoutePath.LIBRARY);
  }

  static pushDiscover(params?: DiscoverRouteParams): void {
    RouterService.push(RoutePath.DISCOVER, params ?? {});
  }

  static pushReader(params: ReaderRouteParams): void {
    RouterService.push(RoutePath.READER, params);
  }

  static pushNotes(params?: NotesRouteParams): void {
    RouterService.push(RoutePath.NOTES, params ?? {});
  }
}
