/**
 * Toast.ets — 米果智读 Toast / Snackbar 反馈组件（W6-C6）
 *
 * 提供：
 *   - ToastManager（imperative API，全局单例）
 *   - AppToast       （单条 toast 的呈现）
 *   - AppToastLayer  （挂载在根容器上的 overlay 层，订阅 AppStorage 渲染当前队列）
 *   - AppSnackbar    （底部带 action 的长 toast 变体）
 *
 * 全局状态实现：
 *   ToastManager 维护 toastList 数组，写入 AppStorage 'app_toast_list'。
 *   AppToastLayer 通过 @StorageProp 订阅，自动重渲染。
 *   每条 toast 由 setTimeout 在 duration 后从列表移除。
 */

import { EffectiveTheme } from '../../core/theme/Theme.types';
import {
  useColor,
  TextColors,
  BgColors,
  StateColors,
  BrandPalette,
} from '../../core/theme/AppColors';
import { LabelStyles, BodyStyles } from '../../core/theme/AppTypography';
import { Spacing, Radius, Elevation, MotionDuration, MotionEasing } from '../../core/theme/AppSpacing';

// ─────────────────────────────────────────────
// 类型
// ─────────────────────────────────────────────

export type ToastType = 'info' | 'success' | 'warning' | 'error';
export type ToastPosition = 'top' | 'center' | 'bottom';

export interface ToastAction {
  label: string;
  onPress: () => void;
}

export interface ToastOptions {
  message: string;
  type?: ToastType;
  /** ms；默认 2000，Snackbar 默认 4000；<=0 表示不自动消失 */
  duration?: number;
  position?: ToastPosition;
  action?: ToastAction;
  /** 强制为 snackbar 样式（底部 + action） */
  snackbar?: boolean;
}

export interface ToastEntry {
  id: number;
  message: string;
  type: ToastType;
  duration: number;
  position: ToastPosition;
  snackbar: boolean;
  action?: ToastAction;
  createdAt: number;
}

const TOAST_STORAGE_KEY = 'app_toast_list';
const MAX_VISIBLE = 3;

// ─────────────────────────────────────────────
// ToastManager — 命令式 API
// ─────────────────────────────────────────────

export class ToastManager {
  private static nextId: number = 1;
  private static timers: Map<number, number> = new Map();

  private static getList(): ToastEntry[] {
    return AppStorage.Get<ToastEntry[]>(TOAST_STORAGE_KEY) ?? [];
  }

  private static setList(list: ToastEntry[]): void {
    AppStorage.SetOrCreate<ToastEntry[]>(TOAST_STORAGE_KEY, list);
  }

  static show(opts: ToastOptions): number {
    const id = ToastManager.nextId++;
    const entry: ToastEntry = {
      id,
      message: opts.message,
      type: opts.type ?? 'info',
      duration: opts.duration ?? (opts.snackbar ? 4000 : 2000),
      position: opts.position ?? (opts.snackbar ? 'bottom' : 'bottom'),
      snackbar: opts.snackbar === true,
      action: opts.action,
      createdAt: Date.now(),
    };

    const list = ToastManager.getList().slice();
    // 最多 MAX_VISIBLE 条同时显示，超出顶部移除最旧
    while (list.length >= MAX_VISIBLE) {
      const removed = list.shift();
      if (removed) ToastManager.clearTimer(removed.id);
    }
    list.push(entry);
    ToastManager.setList(list);

    if (entry.duration > 0) {
      const timerId = setTimeout(() => {
        ToastManager.dismiss(id);
      }, entry.duration);
      ToastManager.timers.set(id, timerId);
    }

    return id;
  }

  static success(message: string, duration?: number): number {
    return ToastManager.show({ message, type: 'success', duration });
  }

  static error(message: string, duration?: number): number {
    return ToastManager.show({ message, type: 'error', duration });
  }

  static info(message: string, duration?: number): number {
    return ToastManager.show({ message, type: 'info', duration });
  }

  static warning(message: string, duration?: number): number {
    return ToastManager.show({ message, type: 'warning', duration });
  }

  static dismiss(toastId: number): void {
    const list = ToastManager.getList().filter((t) => t.id !== toastId);
    ToastManager.setList(list);
    ToastManager.clearTimer(toastId);
  }

  static dismissAll(): void {
    ToastManager.getList().forEach((t) => ToastManager.clearTimer(t.id));
    ToastManager.setList([]);
  }

  private static clearTimer(id: number): void {
    const t = ToastManager.timers.get(id);
    if (t !== undefined) {
      clearTimeout(t);
      ToastManager.timers.delete(id);
    }
  }
}

// ─────────────────────────────────────────────
// 颜色辅助
// ─────────────────────────────────────────────

function bgForType(type: ToastType, isDark: boolean): ResourceColor {
  switch (type) {
    case 'success': return useColor(StateColors.success, isDark);
    case 'warning': return useColor(StateColors.warning, isDark);
    case 'error':   return useColor(StateColors.error, isDark);
    case 'info':
    default:        return isDark ? '#2C2C2E' : '#2D2E4A';
  }
}

function textColorForType(type: ToastType): ResourceColor {
  // 所有 toast 文字都用白色，保证在彩色背景上对比度
  return '#FFFFFF';
}

function iconForType(type: ToastType): string {
  switch (type) {
    case 'success': return '✓';
    case 'warning': return '!';
    case 'error':   return '×';
    case 'info':
    default:        return 'i';
  }
}

// ─────────────────────────────────────────────
// AppToast — 单条 toast 渲染
// ─────────────────────────────────────────────

@Component
export struct AppToast {
  @Prop entry: ToastEntry = {
    id: 0,
    message: '',
    type: 'info',
    duration: 2000,
    position: 'bottom',
    snackbar: false,
    createdAt: 0,
  };

  @Consume('theme') theme: EffectiveTheme;
  @State private mounted: boolean = false;

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  aboutToAppear(): void {
    // 触发进入动画
    setTimeout(() => {
      this.mounted = true;
    }, 16);
  }

  build() {
    Row({ space: Spacing.s2 }) {
      Text(iconForType(this.entry.type))
        .fontSize(LabelStyles.medium.fontSize)
        .fontWeight(LabelStyles.large.fontWeight)
        .fontColor(textColorForType(this.entry.type))
        .width(20)
        .height(20)
        .borderRadius(10)
        .backgroundColor('rgba(255,255,255,0.18)')
        .textAlign(TextAlign.Center)

      Text(this.entry.message)
        .fontFamily(BodyStyles.medium.fontFamily)
        .fontSize(BodyStyles.medium.fontSize)
        .fontWeight(BodyStyles.medium.fontWeight)
        .lineHeight(BodyStyles.medium.lineHeight)
        .fontColor(textColorForType(this.entry.type))
        .layoutWeight(1)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.entry.action) {
        Text(this.entry.action.label)
          .fontFamily(LabelStyles.medium.fontFamily)
          .fontSize(LabelStyles.medium.fontSize)
          .fontWeight(LabelStyles.large.fontWeight)
          .fontColor('#FFFFFF')
          .padding({ left: Spacing.s2, right: Spacing.s2, top: Spacing.s1, bottom: Spacing.s1 })
          .borderRadius(Radius.sm)
          .backgroundColor('rgba(255,255,255,0.18)')
          .onClick(() => {
            this.entry.action?.onPress();
            ToastManager.dismiss(this.entry.id);
          })
      }
    }
    .padding({
      left: Spacing.s4,
      right: Spacing.s4,
      top: Spacing.s3,
      bottom: Spacing.s3,
    })
    .backgroundColor(bgForType(this.entry.type, this.isDark))
    .borderRadius(Radius.lg)
    .shadow(Elevation.e3 ?? undefined)
    .constraintSize({ minWidth: 120, maxWidth: '92%' })
    .opacity(this.mounted ? 1 : 0)
    .translate({ y: this.mounted ? 0 : (this.entry.position === 'top' ? -20 : 20) })
    .animation({
      duration: MotionDuration.normal,
      curve: MotionEasing.decelerate,
    })
    .accessibilityText(this.entry.message)
    .accessibilityLevel('yes')
  }
}

// ─────────────────────────────────────────────
// AppSnackbar — 底部 + action 强制变体
// ─────────────────────────────────────────────

export interface SnackbarOptions {
  message: string;
  action: ToastAction;
  type?: ToastType;
  duration?: number;
}

export class AppSnackbar {
  /** 强制底部 + action（duration 默认 4s） */
  static show(opts: SnackbarOptions): number {
    return ToastManager.show({
      message: opts.message,
      type: opts.type ?? 'info',
      duration: opts.duration ?? 4000,
      position: 'bottom',
      snackbar: true,
      action: opts.action,
    });
  }
}

// ─────────────────────────────────────────────
// AppToastLayer — 全局 overlay 层，挂在根容器
// ─────────────────────────────────────────────

@Component
export struct AppToastLayer {
  @StorageProp(TOAST_STORAGE_KEY) toasts: ToastEntry[] = [];
  @Consume('theme') theme: EffectiveTheme;

  private get topToasts(): ToastEntry[] {
    return this.toasts.filter((t) => t.position === 'top');
  }
  private get centerToasts(): ToastEntry[] {
    return this.toasts.filter((t) => t.position === 'center');
  }
  private get bottomToasts(): ToastEntry[] {
    return this.toasts.filter((t) => t.position === 'bottom');
  }

  build() {
    // 用 Column 把三个区域纵向铺满；中间区域 layoutWeight(1) 撑高，
    // 顶/底分别 alignItems(Top/Bottom)。这样不依赖 .position() API。
    Column() {
      // 顶部
      Column({ space: Spacing.s2 }) {
        ForEach(
          this.topToasts,
          (t: ToastEntry) => {
            AppToast({ entry: t })
          },
          (t: ToastEntry) => `${t.id}`,
        )
      }
      .width('100%')
      .padding({ top: Spacing.s10, left: Spacing.s4, right: Spacing.s4 })
      .alignItems(HorizontalAlign.Center)

      // 居中（撑满中间空间）
      Column({ space: Spacing.s2 }) {
        ForEach(
          this.centerToasts,
          (t: ToastEntry) => {
            AppToast({ entry: t })
          },
          (t: ToastEntry) => `${t.id}`,
        )
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)

      // 底部
      Column({ space: Spacing.s2 }) {
        ForEach(
          this.bottomToasts,
          (t: ToastEntry) => {
            AppToast({ entry: t })
          },
          (t: ToastEntry) => `${t.id}`,
        )
      }
      .width('100%')
      .padding({ bottom: Spacing.s10, left: Spacing.s4, right: Spacing.s4 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
