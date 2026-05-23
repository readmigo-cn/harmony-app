/**
 * Breakpoints.ets — 设备断点 + 折叠屏状态感知
 *
 * 职责：
 *   1. 定义统一断点 (XS/SM/MD/LG/XL)，与 ArkUI GridRow 默认断点对齐
 *   2. 监听折叠屏状态变化（仅在支持折叠屏的设备上生效）
 *   3. 注册到 AppStorage：
 *        - 'app_breakpoint'  → Breakpoint
 *        - 'app_fold_status' → FoldStatus
 *      UI 层通过 @StorageProp 消费，无需手动监听 window 尺寸变化
 *
 * 用法：
 *   // 在 EntryAbility.onWindowStageCreate 调用一次：
 *   import { initBreakpoints, disposeBreakpoints } from '../theme/Breakpoints';
 *   initBreakpoints(windowStage);
 *
 *   // 在组件内：
 *   @StorageProp('app_breakpoint') bp: Breakpoint = Breakpoint.MD;
 */

import display from '@ohos.display';
import window from '@ohos.window';

// ─────────────────────────────────────────────
// 断点枚举
// 划分依据：HarmonyOS 设计规范 + ArkUI GridRow 默认断点
//   xs: <320vp   超小屏（手机竖屏 small）
//   sm: 320~519  手机竖屏标准 (常见 360/375/414)
//   md: 520~839  手机横屏 / 折叠屏 inner / 小平板 7"
//   lg: 840~1279 平板 / 折叠屏 expand / 大屏手机横屏
//   xl: ≥1280    大平板 / 桌面投屏
// ─────────────────────────────────────────────

export enum Breakpoint {
  XS = 'xs',
  SM = 'sm',
  MD = 'md',
  LG = 'lg',
  XL = 'xl',
}

// ─────────────────────────────────────────────
// 折叠屏状态
// 对应 @ohos.display.FoldStatus（HarmonyOS NEXT 5.0+）
//   FOLDED      = 折叠态（外屏）
//   EXPAND      = 完全展开
//   HALF_FOLDED = 半折（hover/Mate X5 角度）
//   UNKNOWN     = 不支持折叠屏 / 未知
// ─────────────────────────────────────────────

export enum FoldStatus {
  UNKNOWN = 0,
  EXPAND = 1,
  FOLDED = 2,
  HALF_FOLDED = 3,
}

// ─────────────────────────────────────────────
// AppStorage Keys（全局唯一，UI 层透过 @StorageProp 订阅）
// ─────────────────────────────────────────────

export const STORAGE_KEY_BREAKPOINT = 'app_breakpoint';
export const STORAGE_KEY_FOLD_STATUS = 'app_fold_status';
export const STORAGE_KEY_WINDOW_WIDTH_VP = 'app_window_width_vp';

// ─────────────────────────────────────────────
// 工具函数
// ─────────────────────────────────────────────

/** 把宽度（vp）映射到 Breakpoint */
export function getCurrentBreakpoint(widthVp: number): Breakpoint {
  if (widthVp < 320) return Breakpoint.XS;
  if (widthVp < 520) return Breakpoint.SM;
  if (widthVp < 840) return Breakpoint.MD;
  if (widthVp < 1280) return Breakpoint.LG;
  return Breakpoint.XL;
}

/** 同步获取当前折叠屏状态（不订阅事件） */
export function getCurrentFoldStatus(): FoldStatus {
  try {
    if (typeof display.isFoldable === 'function' && !display.isFoldable()) {
      return FoldStatus.UNKNOWN;
    }
    if (typeof display.getFoldStatus === 'function') {
      const native: number = display.getFoldStatus();
      // @ohos.display.FoldStatus 的整型枚举值与本枚举对齐：
      // 0 UNKNOWN / 1 EXPAND / 2 FOLDED / 3 HALF_FOLDED
      return native as FoldStatus;
    }
  } catch (_e) {
    // 旧设备 / 模拟器 没有该 API
  }
  return FoldStatus.UNKNOWN;
}

// ─────────────────────────────────────────────
// 初始化 / 销毁
// ─────────────────────────────────────────────

let foldListenerRegistered: boolean = false;
let windowSizeListener: ((data: window.Size) => void) | null = null;
let trackedWindow: window.Window | null = null;

/**
 * 初始化断点监听 —— 在 EntryAbility.onWindowStageCreate 调用一次
 * - 写入初始 Breakpoint / FoldStatus 到 AppStorage
 * - 监听窗口尺寸变化 → 重新计算 Breakpoint
 * - 监听折叠屏状态变化 → 更新 FoldStatus
 */
export async function initBreakpoints(windowStage: window.WindowStage): Promise<void> {
  try {
    const mainWin: window.Window = await windowStage.getMainWindow();
    trackedWindow = mainWin;

    const props: window.WindowProperties = mainWin.getWindowProperties();
    const initialWidthPx: number = props.windowRect.width;
    const initialWidthVp: number = pxToVp(initialWidthPx);

    AppStorage.setOrCreate(STORAGE_KEY_WINDOW_WIDTH_VP, initialWidthVp);
    AppStorage.setOrCreate(STORAGE_KEY_BREAKPOINT, getCurrentBreakpoint(initialWidthVp));
    AppStorage.setOrCreate(STORAGE_KEY_FOLD_STATUS, getCurrentFoldStatus());

    // 监听窗口尺寸变化（横竖屏切换 / 多窗口拖拽 / 折叠屏开合）
    windowSizeListener = (size: window.Size) => {
      const widthVp: number = pxToVp(size.width);
      AppStorage.setOrCreate(STORAGE_KEY_WINDOW_WIDTH_VP, widthVp);
      AppStorage.setOrCreate(STORAGE_KEY_BREAKPOINT, getCurrentBreakpoint(widthVp));
    };
    mainWin.on('windowSizeChange', windowSizeListener);

    // 监听折叠屏状态（不支持的设备静默 fail）
    if (!foldListenerRegistered) {
      try {
        display.on('foldStatusChange', (status: number) => {
          AppStorage.setOrCreate(STORAGE_KEY_FOLD_STATUS, status as FoldStatus);
        });
        foldListenerRegistered = true;
      } catch (_e) {
        // 老设备没有此 API
      }
    }
  } catch (e) {
    console.error(`[Breakpoints] init failed: ${JSON.stringify(e)}`);
  }
}

/** 释放监听 —— 在 EntryAbility.onWindowStageDestroy 调用 */
export function disposeBreakpoints(): void {
  try {
    if (trackedWindow && windowSizeListener) {
      trackedWindow.off('windowSizeChange', windowSizeListener);
    }
    if (foldListenerRegistered) {
      display.off('foldStatusChange');
      foldListenerRegistered = false;
    }
  } catch (_e) {
    // 静默
  } finally {
    trackedWindow = null;
    windowSizeListener = null;
  }
}

// ─────────────────────────────────────────────
// 内部：px → vp（HarmonyOS 设计像素），ArkUI 1vp ≈ 1 物理 dp
// ─────────────────────────────────────────────

function pxToVp(px: number): number {
  try {
    const d: display.Display = display.getDefaultDisplaySync();
    const density: number = d.densityPixels || 1;
    return Math.round(px / density);
  } catch (_e) {
    return px;
  }
}
