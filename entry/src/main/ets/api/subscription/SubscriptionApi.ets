import { HttpClient } from '../../api/client/HttpClient';

export type SubscriptionPlan = 'pro_monthly' | 'pro_yearly' | 'premium_monthly';
export type SubscriptionStatus = 'pending' | 'active' | 'cancelled' | 'expired' | 'failed';

/** 支付渠道（W17-A PaymentManager 提供）。 */
export type PaymentChannel = 'hms_iap' | 'wechat' | 'alipay';

export interface SubscriptionInfo {
  isPro: boolean;
  subscription: {
    id: string;
    plan: SubscriptionPlan;
    status: SubscriptionStatus;
    startedAt: string | null;
    expiresAt: string | null;
  } | null;
}

export interface VerifyIapPayload {
  productId: string;
  plan: SubscriptionPlan;
  purchaseToken: string;
  rawReceipt: string;
  /** 支付渠道，默认 hms_iap（向后兼容）。 */
  channel?: PaymentChannel;
}

/** 历史订单（W17-C5 / W17-C6 使用）。 */
export interface OrderRecord {
  orderId: string;
  productId: string;
  plan: SubscriptionPlan;
  channel: PaymentChannel;
  amount: number;
  currency: string;
  status: 'paid' | 'refunding' | 'refunded' | 'failed';
  paidAt: string;
  refundableUntil: string | null;
}

export interface RefundPayload {
  orderId: string;
  reason: string;
  detail?: string;
}

export interface RefundResponse {
  /** 'auto' = 7 天内无条件退款立即生效；'pending_review' = 进入人工审核。 */
  result: 'auto' | 'pending_review';
  refundId: string;
  message?: string;
}

export class SubscriptionApi {
  static me(): Promise<SubscriptionInfo> {
    return HttpClient.get<SubscriptionInfo>('/subscription/me');
  }

  static verify(payload: VerifyIapPayload): Promise<object> {
    return HttpClient.post<object>('/subscription/verify', payload);
  }

  static cancel(): Promise<void> {
    return HttpClient.post<void>('/subscription/cancel');
  }

  /** 历史订单列表。 */
  static listOrders(): Promise<OrderRecord[]> {
    return HttpClient.get<OrderRecord[]>('/subscription/orders');
  }

  /** 申请退款。7 天内自动通过，超期进人工审核。 */
  static requestRefund(payload: RefundPayload): Promise<RefundResponse> {
    return HttpClient.post<RefundResponse>('/subscription/refund', payload);
  }
}
