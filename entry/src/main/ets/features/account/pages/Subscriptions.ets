/**
 * Subscriptions.ets — W17-C5 订阅管理页
 *
 * 内容：
 *   - 当前订阅状态卡（plan / 状态 / 开始 / 到期）
 *   - 升级 / 降级 / 取消按钮
 *   - 历史订单列表（含退款状态）
 *   - 「申请退款」入口（跳 RefundFlow）
 *
 * 使用 W6 components（AppCard / AppButton / AppEmptyState / AppList）
 */

import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import {
  SubscriptionApi,
  OrderRecord,
  SubscriptionStatus,
} from '../../../api/subscription/SubscriptionApi';
import { SubscriptionState } from '../../../features/account/service/subscription/SubscriptionState';
import { PricingTable, PlanMeta } from '../../../features/account/service/subscription/PricingTable';
import { PaywallSheet } from '../../../features/account/components/PaywallSheet';
import { RoutePath } from '../../../core/router/RouteConstants';

interface OrderParams {
  orderId: string;
}

@Entry
@Component
struct Subscriptions {
  @State currentPlan: PlanMeta = PricingTable.getPlan('free')!;
  @State status: SubscriptionStatus | null = null;
  @State expiresAt: string | null = null;
  @State startedAt: string | null = null;
  @State orders: OrderRecord[] = [];
  @State loadingOrders: boolean = true;
  @State cancelling: boolean = false;

  private unsubscribe: (() => void) | null = null;

  private paywall: CustomDialogController = new CustomDialogController({
    builder: PaywallSheet({
      onCheckout: (meta: PlanMeta, channel) => this.handleCheckout(meta, channel),
      onPurchaseSuccess: () => this.refreshAll(),
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
  });

  aboutToAppear(): void {
    const state = SubscriptionState.getInstance();
    this.unsubscribe = state.subscribeChange((s) => {
      this.currentPlan = s.getCurrentPlan();
      this.status = s.getStatus();
      this.expiresAt = s.getExpiresAt();
      this.startedAt = s.getStartedAt();
    });
    this.loadOrders();
    state.refresh().catch((_e: Error) => {});
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
  }

  private async refreshAll(): Promise<void> {
    await SubscriptionState.getInstance().refresh();
    await this.loadOrders();
  }

  private async loadOrders(): Promise<void> {
    this.loadingOrders = true;
    try {
      this.orders = await SubscriptionApi.listOrders();
    } catch (_e) {
      this.orders = [];
    } finally {
      this.loadingOrders = false;
    }
  }

  /**
   * Paywall 的支付回调占位：W17-A PaymentManager 还未集成时直接返回 false。
   * 真正接入时改为：
   *   const ok = await PaymentManager.purchase({ productId, plan, channel });
   *   return ok;
   */
  private async handleCheckout(_meta: PlanMeta, _channel: string): Promise<boolean> {
    promptAction.showToast({ message: '支付通道接入中（W17-A）' });
    return false;
  }

  private async onCancel(): Promise<void> {
    if (this.cancelling) return;
    this.cancelling = true;
    try {
      await SubscriptionApi.cancel();
      await SubscriptionState.getInstance().refresh();
      promptAction.showToast({ message: '订阅已取消，到期后将不再续费' });
    } catch (e) {
      const err = e as Error;
      promptAction.showToast({ message: err.message ?? '取消失败' });
    } finally {
      this.cancelling = false;
    }
  }

  private statusLabel(): string {
    if (!this.status) return '免费版';
    switch (this.status) {
      case 'active':    return '生效中';
      case 'pending':   return '待处理';
      case 'cancelled': return '已取消（到期失效）';
      case 'expired':   return '已到期';
      case 'failed':    return '支付失败';
      default:          return '未知';
    }
  }

  // ─── builders ────────────────────────────────

  @Builder
  currentCard() {
    Column({ space: AppSpacing.xs }) {
      Row() {
        Text(this.currentPlan.title)
          .fontSize(AppFontSize.lg)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text(this.statusLabel())
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.brand)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(AppRadius.sm)
          .backgroundColor(AppColors.bgElevated)
      }
      .width('100%')
      Text(this.currentPlan.subtitle)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textSecondary)
        .width('100%')
      if (this.startedAt) {
        Text(`开始时间：${this.startedAt.slice(0, 10)}`)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textSecondary)
          .width('100%')
      }
      if (this.expiresAt) {
        Text(`到期时间：${this.expiresAt.slice(0, 10)}`)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textSecondary)
          .width('100%')
      }
    }
    .padding(AppSpacing.base)
    .borderRadius(AppRadius.md)
    .backgroundColor(AppColors.bgElevated)
    .width('100%')
  }

  @Builder
  actions() {
    Column({ space: AppSpacing.sm }) {
      Button(this.currentPlan.tier === 'free' ? '升级 Pro' : '升级 / 切换套餐')
        .width('100%')
        .height(48)
        .backgroundColor(AppColors.brand)
        .fontColor(AppColors.textInverse)
        .borderRadius(AppRadius.base)
        .onClick(() => this.paywall.open())

      if (this.currentPlan.tier !== 'free' && this.status === 'active') {
        Button(this.cancelling ? '取消中...' : '取消订阅')
          .width('100%')
          .height(44)
          .fontColor(AppColors.danger)
          .backgroundColor(AppColors.bgSecondary)
          .borderRadius(AppRadius.base)
          .enabled(!this.cancelling)
          .onClick(() => this.onCancel())
      }
    }
    .width('100%')
  }

  @Builder
  orderRow(order: OrderRecord) {
    Column({ space: 4 }) {
      Row() {
        Text(PricingTable.getPlan(order.plan as 'pro_monthly')?.title ?? order.plan)
          .fontSize(AppFontSize.sm)
          .fontWeight(AppFontWeight.medium)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text(`${order.currency === 'CNY' ? '￥' : ''}${order.amount}`)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.brand)
      }
      .width('100%')
      Row() {
        Text(`${order.paidAt.slice(0, 10)} · ${this.channelLabel(order.channel)}`)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textSecondary)
          .layoutWeight(1)
        Text(this.orderStatusLabel(order.status))
          .fontSize(AppFontSize.xs)
          .fontColor(order.status === 'paid' ? AppColors.brand : AppColors.textSecondary)
      }
      .width('100%')
      if (order.status === 'paid') {
        Text('申请退款 >')
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.brand)
          .width('100%')
          .textAlign(TextAlign.End)
          .onClick(() => {
            const params: OrderParams = { orderId: order.orderId };
            router.pushUrl({ url: 'features/account/pages/RefundFlow', params })
              .catch((_e: Error) => {});
          })
      }
    }
    .padding(AppSpacing.sm)
    .borderRadius(AppRadius.sm)
    .backgroundColor(AppColors.bgPrimary)
    .border({ width: 1, color: AppColors.border })
    .width('100%')
  }

  private channelLabel(c: string): string {
    if (c === 'hms_iap') return '华为支付';
    if (c === 'wechat')  return '微信支付';
    if (c === 'alipay')  return '支付宝';
    return c;
  }

  private orderStatusLabel(s: string): string {
    if (s === 'paid')      return '已支付';
    if (s === 'refunding') return '退款中';
    if (s === 'refunded')  return '已退款';
    if (s === 'failed')    return '失败';
    return s;
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(AppFontSize.lg)
          .fontColor(AppColors.textPrimary)
          .padding(AppSpacing.base)
          .onClick(() => router.back())
        Text('订阅管理')
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('')
          .width(48)
      }
      .width('100%')
      .backgroundColor(AppColors.bgPrimary)

      Scroll() {
        Column({ space: AppSpacing.lg }) {
          this.currentCard()
          this.actions()

          // 历史订单
          Column({ space: AppSpacing.sm }) {
            Text('历史订单')
              .fontSize(AppFontSize.md)
              .fontWeight(AppFontWeight.bold)
              .fontColor(AppColors.textPrimary)
              .width('100%')
            if (this.loadingOrders) {
              Text('加载中...')
                .fontSize(AppFontSize.sm)
                .fontColor(AppColors.textSecondary)
            } else if (this.orders.length === 0) {
              Text('暂无订单记录')
                .fontSize(AppFontSize.sm)
                .fontColor(AppColors.textSecondary)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(AppSpacing.lg)
            } else {
              ForEach(this.orders, (o: OrderRecord) => {
                this.orderRow(o)
              }, (o: OrderRecord) => o.orderId)
            }
          }
          .width('100%')

          // 通用退款入口
          Button('申请退款')
            .width('100%')
            .height(44)
            .fontColor(AppColors.brand)
            .backgroundColor(AppColors.bgSecondary)
            .borderRadius(AppRadius.base)
            .onClick(() => {
              router.pushUrl({ url: 'features/account/pages/RefundFlow' })
                .catch((_e: Error) => {});
            })
        }
        .padding(AppSpacing.lg)
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }
}
