/**
 * PaywallSheet.ets — W17-C5 订阅墙（重写）
 *
 * 设计：
 *   - 4 套餐 tab 切换（free / pro_monthly / pro_yearly / premium_monthly）
 *   - 推荐徽章（pro_yearly 高亮 -50%）
 *   - 功能对比表（按 PricingTable.featureRows 渲染勾选）
 *   - 试用提示（pro_yearly 显示 7 天免费）
 *   - 支付方式三选一（HMS IAP / 微信 / 支付宝）
 *   - 协议链接（订阅协议 + 自动续费协议）
 *   - 「恢复购买」按钮 → 调 SubscriptionState.refresh()
 *   - Loading + 错误态
 *
 * 与 W17-A PaymentManager 集成：
 *   - 通过 onCheckout 回调把 (PlanMeta, PaymentChannel) 交给页面层
 *   - 页面层调 PaymentManager.purchase(...)，避免组件直接耦合具体支付实现
 *   - 支付完成后调 SubscriptionState.refresh()
 *
 * 设计 token 沿用现有 PaywallSheet.ets 的 AppColors / AppFontSize 等约定。
 */

import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import promptAction from '@ohos.promptAction';
import { SubscriptionState } from '../../../features/account/service/subscription/SubscriptionState';
import { PricingTable, PlanMeta, PlanTier, FeatureRow } from '../../../features/account/service/subscription/PricingTable';
import { PaymentChannel } from '../../../api/subscription/SubscriptionApi';
// W18-C1：付费漏斗埋点
import { Analytics } from '../../../core/analytics/AnalyticsProvider';
import { SaEvents } from '../../../core/analytics/SensorsAnalytics';

/** 支付方式选项展示用。 */
interface PayOption {
  channel: PaymentChannel;
  label: string;
  hint: string;
}

const PAY_OPTIONS: PayOption[] = [
  { channel: 'hms_iap', label: '华为支付', hint: '推荐 · 走 HMS IAP 通道' },
  { channel: 'wechat',  label: '微信支付', hint: '通过微信完成支付' },
  { channel: 'alipay',  label: '支付宝',   hint: '通过支付宝完成支付' },
];

@CustomDialog
export struct PaywallSheet {
  controller?: CustomDialogController;
  /**
   * 支付确认回调 — 由页面层调 PaymentManager。
   * 返回 true 表示成功（弹窗自动关闭 + 触发 onPurchaseSuccess）。
   */
  onCheckout?: (meta: PlanMeta, channel: PaymentChannel) => Promise<boolean>;
  onPurchaseSuccess?: () => void;
  onAgreementTap?: () => void;
  onAutoRenewTap?: () => void;

  @State purchasing: boolean = false;
  @State restoring: boolean = false;
  @State errorMsg: string = '';
  /** 选中套餐 tier；默认推荐套餐。 */
  @State selectedTier: PlanTier = 'pro_yearly';
  /** 选中支付通道。 */
  @State selectedChannel: PaymentChannel = 'hms_iap';

  private i18n = PricingTable.i18n();

  aboutToAppear(): void {
    const rec = PricingTable.getRecommended();
    this.selectedTier = rec.tier;
    Analytics.track(SaEvents.PAYWALL_VIEWED, { recommended_tier: rec.tier });
    Analytics.track(SaEvents.PAGE_VIEW, { page: 'paywall' });
  }

  // ─── 支付 / 恢复 ─────────────────────────────

  private async onConfirm(): Promise<void> {
    if (this.purchasing) return;
    const meta = PricingTable.getPlan(this.selectedTier);
    if (!meta || meta.tier === 'free') {
      promptAction.showToast({ message: '免费版无需购买' });
      this.controller?.close();
      return;
    }
    if (!this.onCheckout) {
      this.errorMsg = '支付通道未就绪';
      return;
    }
    this.purchasing = true;
    this.errorMsg = '';
    Analytics.track(SaEvents.PAYMENT_STARTED, {
      tier: meta.tier,
      channel: this.selectedChannel,
      product_id: meta.productId,
    });
    try {
      const ok = await this.onCheckout(meta, this.selectedChannel);
      if (ok) {
        Analytics.track(SaEvents.PAYMENT_SUCCEEDED, {
          tier: meta.tier,
          channel: this.selectedChannel,
        });
        promptAction.showToast({ message: '订阅成功' });
        await SubscriptionState.getInstance().refresh();
        this.controller?.close();
        this.onPurchaseSuccess?.();
      } else {
        Analytics.track(SaEvents.PAYMENT_FAILED, {
          tier: meta.tier,
          channel: this.selectedChannel,
          reason: 'user_cancel_or_unknown',
        });
        this.errorMsg = '支付未完成，请重试';
      }
    } catch (e) {
      const err = e as Error;
      Analytics.track(SaEvents.PAYMENT_FAILED, {
        tier: meta.tier,
        channel: this.selectedChannel,
        reason: err.message ?? 'exception',
      });
      this.errorMsg = err.message ?? '支付失败';
    } finally {
      this.purchasing = false;
    }
  }

  private async onRestore(): Promise<void> {
    if (this.restoring) return;
    this.restoring = true;
    this.errorMsg = '';
    try {
      await SubscriptionState.getInstance().refresh();
      const active = SubscriptionState.getInstance().isProActive();
      promptAction.showToast({ message: active ? '已恢复 Pro 订阅' : '未发现可恢复订阅' });
      if (active) this.controller?.close();
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? '恢复失败';
    } finally {
      this.restoring = false;
    }
  }

  // ─── builders ────────────────────────────────

  @Builder
  planTab(meta: PlanMeta) {
    Column({ space: AppSpacing.xs }) {
      if (meta.recommendLevel >= 2 && meta.badge.length > 0) {
        Text(meta.badge)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textInverse)
          .backgroundColor(AppColors.brand)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(AppRadius.sm)
      }
      Text(meta.title)
        .fontSize(AppFontSize.sm)
        .fontWeight(this.selectedTier === meta.tier ? AppFontWeight.bold : AppFontWeight.medium)
        .fontColor(this.selectedTier === meta.tier ? AppColors.brand : AppColors.textPrimary)
      Text(meta.prices.CN.display + (meta.tier === 'free' ? '' : ' / ' + meta.cycleLabel))
        .fontSize(AppFontSize.md)
        .fontWeight(AppFontWeight.bold)
        .fontColor(this.selectedTier === meta.tier ? AppColors.brand : AppColors.textPrimary)
      if (meta.prices.CN.originalDisplay) {
        Text(meta.prices.CN.originalDisplay)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textSecondary)
          .decoration({ type: TextDecorationType.LineThrough })
      }
    }
    .padding(AppSpacing.sm)
    .layoutWeight(1)
    .borderRadius(AppRadius.md)
    .border({
      width: this.selectedTier === meta.tier ? 2 : 1,
      color: this.selectedTier === meta.tier ? AppColors.brand : AppColors.border,
    })
    .backgroundColor(this.selectedTier === meta.tier ? AppColors.bgElevated : AppColors.bgPrimary)
    .onClick(() => { this.selectedTier = meta.tier; this.errorMsg = ''; })
  }

  @Builder
  featureCheckRow(row: FeatureRow) {
    Row({ space: AppSpacing.xs }) {
      Text(this.tierHas(row, this.selectedTier) ? '✓' : '–')
        .fontSize(AppFontSize.sm)
        .fontColor(this.tierHas(row, this.selectedTier) ? AppColors.brand : AppColors.textSecondary)
        .width(20)
      Text(row.label)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  payOptionRow(opt: PayOption) {
    Row({ space: AppSpacing.sm }) {
      Text(this.selectedChannel === opt.channel ? '●' : '○')
        .fontSize(AppFontSize.md)
        .fontColor(this.selectedChannel === opt.channel ? AppColors.brand : AppColors.textSecondary)
      Column({ space: 2 }) {
        Text(opt.label)
          .fontSize(AppFontSize.sm)
          .fontWeight(AppFontWeight.medium)
          .fontColor(AppColors.textPrimary)
        Text(opt.hint)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(AppSpacing.sm)
    .borderRadius(AppRadius.sm)
    .backgroundColor(this.selectedChannel === opt.channel ? AppColors.bgElevated : AppColors.bgPrimary)
    .onClick(() => { this.selectedChannel = opt.channel; })
  }

  // ─── helpers ─────────────────────────────────

  private tierHas(row: FeatureRow, tier: PlanTier): boolean {
    switch (tier) {
      case 'pro_monthly':     return row.proMonthly;
      case 'pro_yearly':      return row.proYearly;
      case 'premium_monthly': return row.premiumMonthly;
      default:                return row.free;
    }
  }

  build() {
    Scroll() {
      Column({ space: AppSpacing.base }) {
        // 标题
        Column({ space: AppSpacing.xs }) {
          Text(this.i18n.title)
            .fontSize(AppFontSize.xl)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textPrimary)
          Text(this.i18n.subtitle)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
        }
        .padding({ top: AppSpacing.lg })

        // 4 套餐 tab
        Row({ space: AppSpacing.xs }) {
          ForEach(PricingTable.listPlans(), (meta: PlanMeta) => {
            this.planTab(meta)
          }, (meta: PlanMeta) => meta.tier)
        }
        .width('100%')

        // 试用 / 折扣提示
        if (PricingTable.getPlan(this.selectedTier)?.trialDays! > 0) {
          Text(PricingTable.trialText(PricingTable.getPlan(this.selectedTier)!))
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.brand)
            .width('100%')
        }
        if ((PricingTable.getPlan(this.selectedTier)?.discountLabel ?? '').length > 0) {
          Text(PricingTable.getPlan(this.selectedTier)!.discountLabel)
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textSecondary)
            .width('100%')
        }

        // 功能对比表
        Column({ space: 0 }) {
          Text(this.i18n.compareTableTitle)
            .fontSize(AppFontSize.sm)
            .fontWeight(AppFontWeight.medium)
            .fontColor(AppColors.textPrimary)
            .width('100%')
            .padding({ bottom: AppSpacing.xs })
          ForEach(PricingTable.featureRows(), (row: FeatureRow) => {
            this.featureCheckRow(row)
          }, (row: FeatureRow) => row.key)
        }
        .width('100%')
        .padding(AppSpacing.sm)
        .borderRadius(AppRadius.md)
        .backgroundColor(AppColors.bgElevated)

        // 支付方式
        Column({ space: AppSpacing.xs }) {
          Text(this.i18n.paySelectorTitle)
            .fontSize(AppFontSize.sm)
            .fontWeight(AppFontWeight.medium)
            .fontColor(AppColors.textPrimary)
            .width('100%')
          ForEach(PAY_OPTIONS, (opt: PayOption) => {
            this.payOptionRow(opt)
          }, (opt: PayOption) => opt.channel)
        }
        .width('100%')

        // 错误态
        if (this.errorMsg.length > 0) {
          Text(this.errorMsg)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.danger)
            .width('100%')
        }

        // 主按钮
        Button(this.purchasing ? '处理中...' : this.i18n.btnSubscribe)
          .width('100%')
          .height(48)
          .backgroundColor(AppColors.brand)
          .fontColor(AppColors.textInverse)
          .borderRadius(AppRadius.base)
          .enabled(!this.purchasing && this.selectedTier !== 'free')
          .onClick(() => this.onConfirm())

        // 恢复购买
        Button(this.restoring ? '恢复中...' : this.i18n.btnRestore)
          .width('100%')
          .height(40)
          .fontColor(AppColors.brand)
          .backgroundColor(AppColors.bgSecondary)
          .borderRadius(AppRadius.base)
          .enabled(!this.restoring)
          .onClick(() => this.onRestore())

        // 协议
        Row({ space: AppSpacing.xs }) {
          Text(this.i18n.legalAgreement)
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.brand)
            .onClick(() => this.onAgreementTap?.())
          Text('·')
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textSecondary)
          Text(this.i18n.legalAutoRenew)
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.brand)
            .onClick(() => this.onAutoRenewTap?.())
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)

        Text(this.i18n.legalNote)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textSecondary)
          .textAlign(TextAlign.Center)
          .width('100%')

        Text(this.i18n.btnCancel)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textSecondary)
          .padding(AppSpacing.sm)
          .onClick(() => this.controller?.close())
      }
      .padding(AppSpacing.lg)
      .backgroundColor(AppColors.bgPrimary)
      .width('100%')
      .borderRadius({ topLeft: AppRadius.xl, topRight: AppRadius.xl })
    }
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: '85%' })
  }
}
