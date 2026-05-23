/**
 * DeviceSelectorSheet.ets — W13-C3 设备选择 sheet（接续阅读 transferTo 入口）
 *
 * 基于 W6 AppSheet，snap [0.4, 0.7]。
 * 列表展示附近受信设备：图标（按 deviceType）+ 名称 + 在线状态。
 * 选中后回调 onSelect(deviceId)，sheet 自动关闭。
 *
 * 状态：
 *   loading: 首次扫描中（占位 AppSkeleton list-item）
 *   error:   扫描失败（AppEmptyState variant=error，可重试）
 *   empty:   附近无可用设备（AppEmptyState variant=no-data 自定义文案）
 *   ready:   渲染设备列表
 *
 * 数据源：
 *   DeviceManager.discoverDevices() — W13-C1 提供的封装
 *   首次 visible=true 时拉一次；用户手动下拉可点击「刷新」按钮重拉
 */

import {
  TextColors,
  BgColors,
  AccentColors,
  BorderColors,
  StateColors,
  SurfaceColors,
  useColor,
} from '../../../core/theme/AppColors';
import {
  FontFamily,
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius } from '../../../core/theme/AppSpacing';
import { AppSheet } from '../../../ui/primitives/Modal';
import { AppSkeleton } from '../../../ui/primitives/Loading';
import { AppEmptyState } from '../../../ui/primitives/EmptyState';
import { DeviceManager, TrustedDevice, DeviceType } from '../../../features/multi-device/service/distributed/DeviceManager';

/** 设备类型 → emoji 图标（占位，后续可换成 SVG resource） */
const TYPE_ICON: Record<DeviceType, string> = {
  phone: '📱',
  tablet: '📲',
  watch: '⌚',
  pc: '💻',
  tv: '📺',
  car: '🚗',
  unknown: '🔌',
};

const TYPE_LABEL: Record<DeviceType, string> = {
  phone: '手机',
  tablet: '平板',
  watch: '手表',
  pc: '电脑',
  tv: '电视',
  car: '车机',
  unknown: '其它',
};

@Component
export struct DeviceSelectorSheet {
  /** 是否显示（双向绑定） */
  @Link @Watch('onVisibleChange') visible: boolean;
  /** 是否暗色模式 */
  @Prop isDark: boolean;
  /** 选中设备回调；sheet 关闭后再调用，避免 UI 卡顿 */
  onSelect?: (deviceId: string, device: TrustedDevice) => void;

  @State private devices: TrustedDevice[] = [];
  @State private loading: boolean = false;
  @State private errMsg: string = '';

  aboutToAppear(): void {
    if (this.visible) {
      this.refresh();
    }
  }

  /** 每次重新打开都刷新一次（设备状态可能在两次打开间变化） */
  onVisibleChange(): void {
    if (this.visible) {
      this.refresh();
    }
  }

  private async refresh(): Promise<void> {
    this.errMsg = '';
    this.loading = true;
    try {
      const list = await DeviceManager.discoverDevices();
      // 过滤本机（接续目标必须是非本机）
      this.devices = list.filter((d) => !d.isLocal);
    } catch (e) {
      this.errMsg = (e as Error).message ?? '设备扫描失败';
    } finally {
      this.loading = false;
    }
  }

  private handleSelect(d: TrustedDevice): void {
    this.visible = false;
    // 异步回调，避免 sheet 关闭动画期间触发业务跳转
    setTimeout(() => {
      this.onSelect?.(d.deviceId, d);
    }, 150);
  }

  // ─── 子视图 ────────────────────────────────

  @Builder
  rowView(d: TrustedDevice) {
    Row({ space: Spacing.s3 }) {
      // 类型图标
      Text(TYPE_ICON[d.deviceType] ?? TYPE_ICON.unknown)
        .fontSize(28)
        .width(40)
        .textAlign(TextAlign.Center)

      // 名称 + 类型标签
      Column({ space: Spacing.s0_5 }) {
        Text(d.deviceName || '未知设备')
          .fontSize(FontSizeToken.callout)
          .fontFamily(FontFamily.ui)
          .fontWeight(FontWeightToken.semibold)
          .lineHeight(LineHeightToken.callout)
          .fontColor(useColor(TextColors.primary, this.isDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(TYPE_LABEL[d.deviceType] ?? '其它')
          .fontSize(FontSizeToken.footnote)
          .fontFamily(FontFamily.ui)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 在线状态指示
      Row({ space: Spacing.s1 }) {
        Text('●')
          .fontSize(FontSizeToken.footnote)
          .fontColor(
            d.online
              ? useColor(StateColors.success, this.isDark)
              : useColor(TextColors.tertiary, this.isDark),
          )
        Text(d.online ? '在线' : '离线')
          .fontSize(FontSizeToken.footnote)
          .fontFamily(FontFamily.ui)
          .fontColor(useColor(TextColors.secondary, this.isDark))
      }
    }
    .width('100%')
    .padding({
      left: Spacing.s4,
      right: Spacing.s4,
      top: Spacing.s3,
      bottom: Spacing.s3,
    })
    .borderRadius(Radius.md)
    .backgroundColor(
      d.online
        ? useColor(BgColors.tertiary, this.isDark)
        : 'transparent',
    )
    .opacity(d.online ? 1.0 : 0.5)
    .onClick(() => {
      if (!d.online) return;
      this.handleSelect(d);
    })
  }

  private readonly skeletonIdx: number[] = [0, 1, 2];

  @Builder
  loadingView() {
    Column({ space: Spacing.s2 }) {
      ForEach(this.skeletonIdx, (i: number) => {
        AppSkeleton({ variant: 'list-item' })
      }, (i: number) => `dskel-${i}`)
    }
    .width('100%')
  }

  @Builder
  errorView() {
    AppEmptyState({
      variant: 'error',
      description: this.errMsg,
      actionLabel: '重试',
      onAction: () => this.refresh(),
    })
  }

  @Builder
  emptyView() {
    AppEmptyState({
      variant: 'no-data',
      title: '附近没有可接续的设备',
      description: '请确保其它设备已登录同账号且开启「附近的设备」',
      actionLabel: '刷新',
      onAction: () => this.refresh(),
    })
  }

  @Builder
  sheetBody() {
    Column() {
      // 顶部 hint
      Text('选择目标设备后，当前阅读位置将同步过去')
        .fontSize(FontSizeToken.footnote)
        .fontFamily(FontFamily.ui)
        .fontColor(useColor(TextColors.secondary, this.isDark))
        .margin({ bottom: Spacing.s3 })

      if (this.loading) {
        this.loadingView()
      } else if (this.errMsg.length > 0) {
        this.errorView()
      } else if (this.devices.length === 0) {
        this.emptyView()
      } else {
        List({ space: Spacing.s1 }) {
          ForEach(this.devices, (d: TrustedDevice) => {
            ListItem() {
              this.rowView(d)
            }
          }, (d: TrustedDevice) => d.deviceId)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({
          strokeWidth: 0.5,
          color: useColor(SurfaceColors.divider, this.isDark),
          startMargin: Spacing.s4,
          endMargin: Spacing.s4,
        })

        // 底部刷新按钮
        Row({ space: Spacing.s2 }) {
          Text('🔄 刷新')
            .fontSize(FontSizeToken.callout)
            .fontFamily(FontFamily.ui)
            .fontColor(useColor(AccentColors.primary, this.isDark))
            .padding(Spacing.s3)
            .onClick(() => this.refresh())
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: Spacing.s3 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    AppSheet({
      visible: $visible,
      title: '转到其它设备',
      snapPoints: [0.4, 0.7],
      isDark: this.isDark,
      sheetBody: () => this.sheetBody(),
    })
  }
}
