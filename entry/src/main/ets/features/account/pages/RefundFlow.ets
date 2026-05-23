/**
 * RefundFlow.ets — W17-C6 退款申请页
 *
 * 流程：
 *   step 1  选订单（默认从路由参数 orderId 预选；否则列出最近订单）
 *   step 2  选退款原因（预设原因 + 可选补充说明）
 *   step 3  提交 → SubscriptionApi.requestRefund → 反馈结果
 *
 * 业务规则：
 *   - 订单 paidAt 距今 ≤ 7 天 → 自动退款立即到账（result = 'auto'）
 *   - 超过 7 天 → 进入人工审核（result = 'pending_review'）
 *   - 已 refunding / refunded 订单不可再次申请
 */

import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import {
  SubscriptionApi,
  OrderRecord,
  RefundResponse,
} from '../../../api/subscription/SubscriptionApi';
import { SubscriptionState } from '../../../features/account/service/subscription/SubscriptionState';
import { PricingTable } from '../../../features/account/service/subscription/PricingTable';

interface RefundReason {
  key: string;
  label: string;
}

const REASONS: RefundReason[] = [
  { key: 'mistaken',     label: '误操作 / 不小心购买' },
  { key: 'no_use',       label: '没有使用过相关功能' },
  { key: 'feature_lack', label: '功能未达到预期' },
  { key: 'too_expensive',label: '价格偏高' },
  { key: 'duplicate',    label: '重复购买' },
  { key: 'other',        label: '其他原因' },
];

interface RefundParams {
  orderId?: string;
}

@Entry
@Component
struct RefundFlow {
  @State step: number = 1; // 1: 选订单 / 2: 选原因 / 3: 提交结果
  @State orders: OrderRecord[] = [];
  @State selectedOrder: OrderRecord | null = null;
  @State selectedReason: string = '';
  @State detail: string = '';
  @State submitting: boolean = false;
  @State result: RefundResponse | null = null;
  @State errorMsg: string = '';
  @State loading: boolean = true;

  aboutToAppear(): void {
    this.loadOrders();
  }

  private async loadOrders(): Promise<void> {
    this.loading = true;
    try {
      const list = await SubscriptionApi.listOrders();
      this.orders = list.filter((o) => o.status === 'paid');
      const params = router.getParams() as RefundParams | null;
      if (params && params.orderId) {
        const found = this.orders.find((o) => o.orderId === params.orderId);
        if (found) {
          this.selectedOrder = found;
          this.step = 2;
        }
      }
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? '加载订单失败';
    } finally {
      this.loading = false;
    }
  }

  private isAutoRefundable(order: OrderRecord): boolean {
    if (!order.refundableUntil) return false;
    const until = Date.parse(order.refundableUntil);
    return !isNaN(until) && until > Date.now();
  }

  private async submit(): Promise<void> {
    if (!this.selectedOrder || this.selectedReason.length === 0 || this.submitting) return;
    this.submitting = true;
    this.errorMsg = '';
    try {
      const res = await SubscriptionApi.requestRefund({
        orderId: this.selectedOrder.orderId,
        reason: this.selectedReason,
        detail: this.detail.length > 0 ? this.detail : undefined,
      });
      this.result = res;
      this.step = 3;
      // 自动退款会立即生效，刷新订阅状态
      if (res.result === 'auto') {
        await SubscriptionState.getInstance().refresh();
      }
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? '申请失败，请稍后重试';
    } finally {
      this.submitting = false;
    }
  }

  // ─── builders ────────────────────────────────

  @Builder
  orderRow(order: OrderRecord) {
    Column({ space: AppSpacing.xs }) {
      Row() {
        Text(PricingTable.getPlan(order.plan as 'pro_monthly')?.title ?? order.plan)
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.medium)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text(`${order.currency === 'CNY' ? '￥' : ''}${order.amount}`)
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.brand)
      }
      .width('100%')
      Row() {
        Text(order.paidAt.slice(0, 10))
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textSecondary)
          .layoutWeight(1)
        Text(this.isAutoRefundable(order) ? '7 天内可秒退' : '超期需审核')
          .fontSize(AppFontSize.xs)
          .fontColor(this.isAutoRefundable(order) ? AppColors.brand : AppColors.textSecondary)
      }
      .width('100%')
    }
    .padding(AppSpacing.base)
    .borderRadius(AppRadius.md)
    .border({
      width: this.selectedOrder?.orderId === order.orderId ? 2 : 1,
      color: this.selectedOrder?.orderId === order.orderId ? AppColors.brand : AppColors.border,
    })
    .backgroundColor(this.selectedOrder?.orderId === order.orderId ? AppColors.bgElevated : AppColors.bgPrimary)
    .onClick(() => { this.selectedOrder = order; })
  }

  @Builder
  reasonRow(r: RefundReason) {
    Row({ space: AppSpacing.sm }) {
      Text(this.selectedReason === r.key ? '●' : '○')
        .fontSize(AppFontSize.md)
        .fontColor(this.selectedReason === r.key ? AppColors.brand : AppColors.textSecondary)
      Text(r.label)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .padding(AppSpacing.sm)
    .borderRadius(AppRadius.sm)
    .backgroundColor(this.selectedReason === r.key ? AppColors.bgElevated : AppColors.bgPrimary)
    .onClick(() => { this.selectedReason = r.key; })
  }

  @Builder
  step1() {
    Column({ space: AppSpacing.base }) {
      Text('选择要退款的订单')
        .fontSize(AppFontSize.lg)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .width('100%')
      if (this.loading) {
        Text('加载中...')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textSecondary)
      } else if (this.orders.length === 0) {
        Text('暂无可退款订单')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textSecondary)
      } else {
        ForEach(this.orders, (o: OrderRecord) => {
          this.orderRow(o)
        }, (o: OrderRecord) => o.orderId)
      }
      Button('下一步：选择原因')
        .width('100%')
        .height(48)
        .backgroundColor(AppColors.brand)
        .fontColor(AppColors.textInverse)
        .borderRadius(AppRadius.base)
        .enabled(this.selectedOrder !== null)
        .onClick(() => { this.step = 2; })
    }
    .width('100%')
  }

  @Builder
  step2() {
    Column({ space: AppSpacing.base }) {
      Text('请选择退款原因')
        .fontSize(AppFontSize.lg)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .width('100%')
      if (this.selectedOrder && this.isAutoRefundable(this.selectedOrder)) {
        Text('该订单在 7 天无理由期内，提交后将立即退款到原支付渠道')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.brand)
          .width('100%')
      } else {
        Text('该订单已超过 7 天无理由期，需进入人工审核（通常 3 个工作日内反馈）')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textSecondary)
          .width('100%')
      }
      ForEach(REASONS, (r: RefundReason) => {
        this.reasonRow(r)
      }, (r: RefundReason) => r.key)
      TextArea({ placeholder: '补充说明（可选）', text: this.detail })
        .height(96)
        .borderRadius(AppRadius.sm)
        .backgroundColor(AppColors.bgElevated)
        .padding(AppSpacing.sm)
        .onChange((v: string) => { this.detail = v; })
      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.danger)
      }
      Row({ space: AppSpacing.sm }) {
        Button('上一步')
          .layoutWeight(1)
          .height(48)
          .fontColor(AppColors.textPrimary)
          .backgroundColor(AppColors.bgSecondary)
          .borderRadius(AppRadius.base)
          .onClick(() => { this.step = 1; })
        Button(this.submitting ? '提交中...' : '提交申请')
          .layoutWeight(1)
          .height(48)
          .backgroundColor(AppColors.brand)
          .fontColor(AppColors.textInverse)
          .borderRadius(AppRadius.base)
          .enabled(!this.submitting && this.selectedReason.length > 0)
          .onClick(() => this.submit())
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  step3() {
    Column({ space: AppSpacing.base }) {
      Text(this.result?.result === 'auto' ? '退款成功' : '已提交审核')
        .fontSize(AppFontSize.xl)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
      Text(this.result?.result === 'auto'
        ? '款项将在 1-3 个工作日内原路返回到您的支付渠道'
        : '我们会在 3 个工作日内通过站内消息反馈处理结果')
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textSecondary)
        .textAlign(TextAlign.Center)
      if (this.result?.message) {
        Text(this.result.message)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textSecondary)
      }
      Button('完成')
        .width('100%')
        .height(48)
        .backgroundColor(AppColors.brand)
        .fontColor(AppColors.textInverse)
        .borderRadius(AppRadius.base)
        .onClick(() => router.back())
    }
    .width('100%')
    .padding({ top: AppSpacing.xl })
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('<')
          .fontSize(AppFontSize.lg)
          .fontColor(AppColors.textPrimary)
          .padding(AppSpacing.base)
          .onClick(() => router.back())
        Text('申请退款')
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
          if (this.step === 1) {
            this.step1()
          } else if (this.step === 2) {
            this.step2()
          } else {
            this.step3()
          }
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
