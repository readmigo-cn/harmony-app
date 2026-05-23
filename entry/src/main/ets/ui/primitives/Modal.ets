/**
 * Modal.ets — 米果智读 HarmonyOS 弹窗组件集
 *
 * 包含三种弹窗变体：
 *   - AppModal   居中模态弹窗（fade + scale 动效）
 *   - AppSheet   底部弹窗（slide-up 动效，可拖拽关闭）
 *   - AppDialog  提示/确认/输入对话框
 *
 * 命令式 API：
 *   ModalManager.show / alert / confirm / dismiss
 *
 * Z-index 策略：
 *   - AppModal  zIndex=100（最低优先级弹窗层）
 *   - AppSheet  zIndex=200（底部弹窗，覆盖 Modal）
 *   - AppDialog zIndex=300（优先级最高，覆盖所有）
 *   - 多弹窗叠加时每层递增 10，由 ModalManager 统一管理栈深度。
 */

import {
  TextColors,
  BgColors,
  BorderColors,
  AccentColors,
  StateColors,
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
  Elevation,
  MotionDuration,
  MotionEasing,
} from '../../core/theme/AppSpacing';

// ─────────────────────────────────────────────
// 类型定义
// ─────────────────────────────────────────────

/** AppModal 尺寸变体 */
export type ModalSize = 'sm' | 'md' | 'lg' | 'fullscreen';

/** AppDialog 语义变体 */
export type DialogVariant = 'info' | 'warning' | 'error' | 'success';

/** ModalManager 返回结果 */
export interface ModalResult {
  /** 是否确认（confirm 弹窗）*/
  confirmed: boolean;
  /** prompt 弹窗输入值 */
  value?: string;
}

/** AppModal 配置选项（ModalManager.show 使用） */
export interface ModalOptions {
  title?: string;
  /** 是否允许点击遮罩关闭 */
  backdropDismiss?: boolean;
  size?: ModalSize;
  isDark?: boolean;
}

// ─────────────────────────────────────────────
// ModalManager — 命令式 API
// ─────────────────────────────────────────────

/**
 * ModalManager
 *
 * 使用 promptAction（HarmonyOS 系统弹窗）实现命令式调用。
 * 对于自定义 UI 弹窗（AppModal/AppSheet），提供 showCustomDialog 封装。
 *
 * Z-index 栈：
 *   - 内部维护 stackDepth 计数器
 *   - 每次 show 时 stackDepth++，dismiss 时 stackDepth--
 *   - zIndex = BASE_Z + stackDepth * 10
 *
 * 注意：HarmonyOS NEXT API 11+ 推荐使用 UIContext.getPromptAction() 替代全局
 * promptAction；此处为通用性保留旧 API，调用方可通过 uiContext 参数升级。
 */
export class ModalManager {
  private static stackDepth: number = 0;
  static readonly BASE_Z = 100;

  /** 当前栈顶 zIndex */
  static get currentZ(): number {
    return ModalManager.BASE_Z + ModalManager.stackDepth * 10;
  }

  /** 推入栈并返回分配的 zIndex */
  static push(): number {
    ModalManager.stackDepth++;
    return ModalManager.currentZ;
  }

  /** 弹出栈 */
  static pop(): void {
    if (ModalManager.stackDepth > 0) {
      ModalManager.stackDepth--;
    }
  }

  /** 清空弹窗栈（dismiss all） */
  static dismiss(): void {
    ModalManager.stackDepth = 0;
  }

  /**
   * 显示系统 alert 弹窗。
   * 底层使用 @ohos.promptAction showDialog。
   */
  static alert(title: string, message: string): Promise<void> {
    return new Promise<void>((resolve) => {
      import('@ohos.promptAction').then((promptAction) => {
        promptAction.default.showDialog({
          title,
          message,
          buttons: [{ text: '确定', color: '#A78BFA' }],
        }, () => resolve());
      });
    });
  }

  /**
   * 显示系统 confirm 弹窗。
   * @returns true = 确认，false = 取消
   */
  static confirm(title: string, message: string): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      import('@ohos.promptAction').then((promptAction) => {
        promptAction.default.showDialog({
          title,
          message,
          buttons: [
            { text: '取消', color: '#71717A' },
            { text: '确认', color: '#A78BFA' },
          ],
        }, (err, data) => {
          if (err) {
            resolve(false);
            return;
          }
          // index 1 = 确认按钮
          resolve(data?.index === 1);
        });
      });
    });
  }

  /**
   * 显示通用 ModalResult Promise，供自定义弹窗回调时使用。
   * 调用方在弹窗关闭时调用 resolve 即可。
   */
  static show(_options: ModalOptions): Promise<ModalResult> {
    return new Promise<ModalResult>((resolve) => {
      // 自定义弹窗通过 AppModal 组件声明式使用，
      // ModalManager.show 作为命令式触发入口，
      // 调用方在 onClose 回调中调用 resolve({ confirmed: ... })
      resolve({ confirmed: false });
    });
  }
}

// ─────────────────────────────────────────────
// AppModal — 居中模态弹窗
// ─────────────────────────────────────────────

/**
 * AppModal — 居中模态弹窗
 *
 * 动效：遮罩 fade-in + 内容面板 fade + scale(0.95 → 1.0)
 * Z-index：由 ModalManager.push() 动态分配，默认从 100 起步。
 *
 * 用法：
 *   AppModal({ visible: $showModal, title: '标题', size: 'md' }) {
 *     // body 内容
 *   }
 */
@Component
export struct AppModal {
  /** 是否显示弹窗（双向绑定） */
  @Link visible: boolean;
  /** 弹窗标题 */
  title: string = '';
  /** 弹窗尺寸 */
  size: ModalSize = 'md';
  /** 是否允许点击遮罩关闭 */
  backdropDismiss: boolean = true;
  /** 是否暗色模式 */
  isDark: boolean = false;
  /** 关闭回调 */
  onClose?: () => void;
  /** body 内容插槽 */
  @BuilderParam bodyBuilder: (() => void) | undefined = undefined;
  /** footer 操作区插槽 */
  @BuilderParam footerBuilder: (() => void) | undefined = undefined;

  /** 动画控制：内容面板缩放比 */
  @State private contentScale: number = 0.95;
  /** 动画控制：遮罩透明度 */
  @State private backdropOpacity: number = 0;
  /** 分配到的 zIndex */
  private assignedZ: number = ModalManager.BASE_Z;

  /** 弹窗宽度（根据 size 返回） */
  private get panelWidth(): string | number {
    switch (this.size) {
      case 'sm': return 320;
      case 'lg': return 640;
      case 'fullscreen': return '100%';
      default: return 480;
    }
  }

  aboutToAppear(): void {
    if (this.visible) {
      this.assignedZ = ModalManager.push();
      this.playEnterAnimation();
    }
  }

  aboutToDisappear(): void {
    ModalManager.pop();
  }

  private playEnterAnimation(): void {
    animateTo({
      duration: MotionDuration.normal,
      curve: MotionEasing.decelerate,
    }, () => {
      this.contentScale = 1.0;
      this.backdropOpacity = 1.0;
    });
  }

  private playExitAnimation(onFinish: () => void): void {
    animateTo({
      duration: MotionDuration.fast,
      curve: MotionEasing.accelerate,
      onFinish,
    }, () => {
      this.contentScale = 0.95;
      this.backdropOpacity = 0;
    });
  }

  private closeModal(): void {
    this.playExitAnimation(() => {
      this.visible = false;
      this.onClose?.();
    });
  }

  @Builder
  defaultHeader() {
    Row() {
      Text(this.title)
        .fontSize(FontSizeToken.headline)
        .fontFamily(FontFamily.ui)
        .fontWeight(FontWeightToken.semibold)
        .lineHeight(LineHeightToken.headline)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .layoutWeight(1)
      // 关闭按钮
      Text('✕')
        .fontSize(FontSizeToken.callout)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
        .padding(Spacing.s2)
        .onClick(() => this.closeModal())
    }
    .width('100%')
    .padding({
      left: Spacing.s6,
      right: Spacing.s4,
      top: Spacing.s5,
      bottom: Spacing.s4,
    })
  }

  build() {
    if (this.visible) {
      Stack() {
        // ── 遮罩层 ──
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(useColor(BgColors.overlay, this.isDark))
          .opacity(this.backdropOpacity)
          .onClick(() => {
            if (this.backdropDismiss) this.closeModal();
          })

        // ── 内容面板 ──
        Column() {
          // header
          this.defaultHeader()

          // 分割线
          Divider()
            .color(useColor(SurfaceColors.divider, this.isDark))
            .strokeWidth(0.5)

          // body
          Scroll() {
            Column() {
              if (this.bodyBuilder !== undefined) {
                this.bodyBuilder()
              }
            }
            .padding(Spacing.s6)
            .width('100%')
          }
          .scrollBar(BarState.Auto)
          .layoutWeight(1)

          // footer（可选）
          if (this.footerBuilder !== undefined) {
            Divider()
              .color(useColor(SurfaceColors.divider, this.isDark))
              .strokeWidth(0.5)
            Column() {
              this.footerBuilder()
            }
            .padding({
              left: Spacing.s6,
              right: Spacing.s6,
              top: Spacing.s4,
              bottom: Spacing.s5,
            })
            .width('100%')
          }
        }
        .width(this.size === 'fullscreen' ? '100%' : this.panelWidth)
        .constraintSize({ maxHeight: this.size === 'fullscreen' ? '100%' : '80%' })
        .backgroundColor(useColor(BgColors.elevated, this.isDark))
        .borderRadius(this.size === 'fullscreen' ? Radius.none : Radius.xl)
        .shadow(Elevation.e5 ?? undefined)
        .scale({ x: this.contentScale, y: this.contentScale })
        .opacity(this.backdropOpacity)
      }
      .width('100%')
      .height('100%')
      .zIndex(this.assignedZ)
      .position({ x: 0, y: 0 })
    }
  }
}

// ─────────────────────────────────────────────
// AppSheet — 底部弹窗
// ─────────────────────────────────────────────

/**
 * AppSheet — 底部弹窗
 *
 * 动效：遮罩 fade + 面板 slide-up
 * 拖拽手柄：panGesture 向下超过 80vp 触发关闭。
 * Snap points：[0.3, 0.6, 1.0] 对应面板占屏幕高度比（配置性）。
 *
 * Z-index：固定 200，覆盖 AppModal。
 */
@Component
export struct AppSheet {
  /** 是否显示（双向绑定） */
  @Link visible: boolean;
  /** 面板标题 */
  title: string = '';
  /**
   * 快照高度比（相对屏幕高度），默认 [0.3, 0.6, 1.0]。
   * 面板初始化时使用 snapPoints[0]。
   */
  snapPoints: number[] = [0.3, 0.6, 1.0];
  /** 是否暗色模式 */
  isDark: boolean = false;
  /** 关闭回调 */
  onClose?: () => void;
  /** 内容插槽 */
  @BuilderParam sheetBody: (() => void) | undefined = undefined;

  /** 面板当前高度比（0~1） */
  @State private heightRatio: number = 0;
  /** 遮罩透明度 */
  @State private backdropOpacity: number = 0;
  /** 拖拽起始 Y（用于计算拖拽位移） */
  private dragStartY: number = 0;
  /** 拖拽起始时的高度比 */
  private dragStartRatio: number = 0;

  aboutToAppear(): void {
    if (this.visible) {
      this.playEnterAnimation();
    }
  }

  private playEnterAnimation(): void {
    const targetRatio = this.snapPoints.length > 0 ? this.snapPoints[0] : 0.5;
    animateTo({
      duration: MotionDuration.normal,
      curve: MotionEasing.decelerate,
    }, () => {
      this.heightRatio = targetRatio;
      this.backdropOpacity = 1.0;
    });
  }

  private playExitAnimation(onFinish: () => void): void {
    animateTo({
      duration: MotionDuration.fast,
      curve: MotionEasing.accelerate,
      onFinish,
    }, () => {
      this.heightRatio = 0;
      this.backdropOpacity = 0;
    });
  }

  private closeSheet(): void {
    this.playExitAnimation(() => {
      this.visible = false;
      this.onClose?.();
    });
  }

  /** 根据拖拽结束位置吸附到最近 snapPoint */
  private snapToNearest(): void {
    const current = this.heightRatio;
    let nearest = this.snapPoints[0];
    let minDist = Math.abs(current - nearest);
    for (const sp of this.snapPoints) {
      const dist = Math.abs(current - sp);
      if (dist < minDist) {
        minDist = dist;
        nearest = sp;
      }
    }
    // 低于最小 snap point 的 50% 则关闭
    if (current < this.snapPoints[0] * 0.5) {
      this.closeSheet();
      return;
    }
    animateTo({
      duration: MotionDuration.normal,
      curve: MotionEasing.spring,
    }, () => {
      this.heightRatio = nearest;
    });
  }

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Bottom }) {
        // ── 遮罩层 ──
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(useColor(BgColors.overlay, this.isDark))
          .opacity(this.backdropOpacity)
          .onClick(() => this.closeSheet())

        // ── 面板 ──
        Column() {
          // 拖拽手柄
          Column() {
            Column()
              .width(36)
              .height(4)
              .borderRadius(Radius.full)
              .backgroundColor(useColor(BorderColors.primary, this.isDark))
          }
          .width('100%')
          .padding({ top: Spacing.s3, bottom: Spacing.s2 })
          .alignItems(HorizontalAlign.Center)
          // PanGesture 识别纵向拖拽
          .gesture(
            PanGesture({ direction: PanDirection.Vertical })
              .onActionStart((event: GestureEvent) => {
                this.dragStartY = event.offsetY;
                this.dragStartRatio = this.heightRatio;
              })
              .onActionUpdate((event: GestureEvent) => {
                // 向下拖拽（offsetY > dragStartY）时减小高度比
                const delta = (event.offsetY - this.dragStartY) / 800;
                const next = Math.max(0, Math.min(1.0, this.dragStartRatio - delta));
                this.heightRatio = next;
                this.backdropOpacity = Math.max(0, Math.min(1, next / (this.snapPoints[0] || 0.3)));
              })
              .onActionEnd(() => {
                this.snapToNearest();
              })
          )

          // 标题行
          if (this.title.length > 0) {
            Row() {
              Text(this.title)
                .fontSize(FontSizeToken.headline)
                .fontFamily(FontFamily.ui)
                .fontWeight(FontWeightToken.semibold)
                .lineHeight(LineHeightToken.headline)
                .fontColor(useColor(TextColors.primary, this.isDark))
                .layoutWeight(1)
              Text('✕')
                .fontSize(FontSizeToken.callout)
                .fontColor(useColor(TextColors.tertiary, this.isDark))
                .padding(Spacing.s2)
                .onClick(() => this.closeSheet())
            }
            .width('100%')
            .padding({ left: Spacing.s6, right: Spacing.s4, bottom: Spacing.s4 })

            Divider()
              .color(useColor(SurfaceColors.divider, this.isDark))
              .strokeWidth(0.5)
          }

          // body
          Scroll() {
            Column() {
              if (this.sheetBody !== undefined) {
                this.sheetBody()
              }
            }
            .padding(Spacing.s6)
            .width('100%')
          }
          .scrollBar(BarState.Auto)
          .layoutWeight(1)
        }
        .width('100%')
        .height(`${this.heightRatio * 100}%`)
        .constraintSize({ minHeight: 0 })
        .backgroundColor(useColor(BgColors.elevated, this.isDark))
        .borderRadius({ topLeft: Radius.xl, topRight: Radius.xl })
        .shadow(Elevation.e4 ?? undefined)
        .clip(true)
      }
      .width('100%')
      .height('100%')
      .zIndex(200)
      .position({ x: 0, y: 0 })
    }
  }
}

// ─────────────────────────────────────────────
// AppDialog — 提示 / 确认 / 输入对话框
// ─────────────────────────────────────────────

/**
 * AppDialog — 语义化对话框
 *
 * 支持三种内置 pattern：
 *   alert   — 单按钮确认
 *   confirm — 取消 + 确认双按钮
 *   prompt  — 输入框 + 取消 + 提交
 *
 * 四种语义变体（icon 颜色随变体变化）：
 *   info / warning / error / success
 *
 * Z-index：固定 300，在所有弹窗之上。
 */
@Component
export struct AppDialog {
  /** 是否显示（双向绑定） */
  @Link visible: boolean;
  /** 对话框语义变体 */
  variant: DialogVariant = 'info';
  /** 标题 */
  title: string = '';
  /** 正文消息 */
  message: string = '';
  /** 取消按钮文字（confirm/prompt 模式） */
  cancelLabel: string = '取消';
  /** 确认按钮文字 */
  confirmLabel: string = '确认';
  /** 是否为 prompt 模式（显示输入框） */
  isPrompt: boolean = false;
  /** prompt 输入框默认值 */
  defaultInputValue: string = '';
  /** 是否暗色模式 */
  isDark: boolean = false;
  /** 确认回调（confirm/prompt 模式） */
  onConfirm?: (value?: string) => void;
  /** 取消回调 */
  onCancel?: () => void;

  @State private inputValue: string = '';
  @State private contentScale: number = 0.92;
  @State private backdropOpacity: number = 0;

  aboutToAppear(): void {
    this.inputValue = this.defaultInputValue;
    if (this.visible) {
      animateTo({
        duration: MotionDuration.normal,
        curve: MotionEasing.decelerate,
      }, () => {
        this.contentScale = 1.0;
        this.backdropOpacity = 1.0;
      });
    }
  }

  /** 返回当前变体对应的图标文字 */
  private get variantIcon(): string {
    switch (this.variant) {
      case 'warning': return '⚠️';
      case 'error':   return '✕';
      case 'success': return '✓';
      default:        return 'ℹ';
    }
  }

  /** 返回当前变体对应的强调色 */
  private get variantColor(): ResourceColor {
    switch (this.variant) {
      case 'warning': return useColor(StateColors.warning, this.isDark);
      case 'error':   return useColor(StateColors.error, this.isDark);
      case 'success': return useColor(StateColors.success, this.isDark);
      default:        return useColor(StateColors.info, this.isDark);
    }
  }

  private handleCancel(): void {
    this.visible = false;
    this.onCancel?.();
  }

  private handleConfirm(): void {
    this.visible = false;
    this.onConfirm?.(this.isPrompt ? this.inputValue : undefined);
  }

  build() {
    if (this.visible) {
      Stack() {
        // ── 遮罩 ──
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(useColor(BgColors.overlay, this.isDark))
          .opacity(this.backdropOpacity)

        // ── 对话框面板 ──
        Column({ space: 0 }) {
          // 图标区
          Column() {
            Text(this.variantIcon)
              .fontSize(28)
              .fontColor(this.variantColor)
          }
          .width(56)
          .height(56)
          .borderRadius(Radius.full)
          .backgroundColor(useColor(BgColors.secondary, this.isDark))
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .margin({ top: Spacing.s6, bottom: Spacing.s4 })

          // 标题
          Text(this.title)
            .fontSize(FontSizeToken.title3)
            .fontFamily(FontFamily.ui)
            .fontWeight(FontWeightToken.semibold)
            .lineHeight(LineHeightToken.title3)
            .fontColor(useColor(TextColors.primary, this.isDark))
            .textAlign(TextAlign.Center)
            .padding({ left: Spacing.s6, right: Spacing.s6 })
            .margin({ bottom: Spacing.s3 })

          // 消息
          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(FontSizeToken.callout)
              .fontFamily(FontFamily.ui)
              .fontWeight(FontWeightToken.regular)
              .lineHeight(LineHeightToken.callout)
              .fontColor(useColor(TextColors.secondary, this.isDark))
              .textAlign(TextAlign.Center)
              .padding({ left: Spacing.s6, right: Spacing.s6 })
              .margin({ bottom: Spacing.s4 })
          }

          // prompt 输入框
          if (this.isPrompt) {
            TextInput({ text: this.inputValue, placeholder: '请输入…' })
              .width('100%')
              .height(44)
              .fontSize(FontSizeToken.callout)
              .fontFamily(FontFamily.ui)
              .padding({ left: Spacing.s4, right: Spacing.s4 })
              .borderRadius(Radius.lg)
              .backgroundColor(useColor(BgColors.secondary, this.isDark))
              .margin({
                left: Spacing.s6,
                right: Spacing.s6,
                bottom: Spacing.s4,
              })
              .onChange((value: string) => {
                this.inputValue = value;
              })
          }

          Divider()
            .color(useColor(SurfaceColors.divider, this.isDark))
            .strokeWidth(0.5)

          // 操作按钮区
          Row() {
            // 取消按钮（confirm / prompt 模式显示）
            if (!this.isPrompt || this.isPrompt) {
              Button(this.cancelLabel)
                .layoutWeight(1)
                .height(44)
                .backgroundColor('transparent')
                .fontColor(useColor(TextColors.secondary, this.isDark))
                .fontSize(FontSizeToken.callout)
                .fontFamily(FontFamily.ui)
                .onClick(() => this.handleCancel())

              // 垂直分割线
              Column()
                .width(0.5)
                .height(44)
                .backgroundColor(useColor(SurfaceColors.divider, this.isDark))
            }

            // 确认按钮
            Button(this.confirmLabel)
              .layoutWeight(1)
              .height(44)
              .backgroundColor('transparent')
              .fontColor(this.variantColor)
              .fontSize(FontSizeToken.callout)
              .fontFamily(FontFamily.ui)
              .fontWeight(FontWeightToken.medium)
              .onClick(() => this.handleConfirm())
          }
          .width('100%')
        }
        .width(300)
        .backgroundColor(useColor(BgColors.elevated, this.isDark))
        .borderRadius(Radius.xl)
        .shadow(Elevation.e5 ?? undefined)
        .clip(true)
        .scale({ x: this.contentScale, y: this.contentScale })
        .opacity(this.backdropOpacity)
      }
      .width('100%')
      .height('100%')
      .zIndex(300)
      .position({ x: 0, y: 0 })
    }
  }
}
