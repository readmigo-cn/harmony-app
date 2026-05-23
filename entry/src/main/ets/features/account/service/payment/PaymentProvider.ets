/**
 * PaymentProvider.ets — 米果智读 HarmonyOS 支付 Provider 抽象层（W17-C1）
 *
 * 设计目标：
 *   - 屏蔽 HMS IAP / 微信 / 支付宝 三家 SDK 调用差异
 *   - 统一订单创建、支付唤起、订单查询接口
 *   - 上层 PaymentManager 与 UI（Paywall）只面向接口编程
 *   - Phase 4 mock 阶段提供桩实现，Phase 5 替换为真实 SDK 调用
 */

import { SubscriptionPlan } from '../../../../api/subscription/SubscriptionApi';

/** 支付通道枚举 */
export type PaymentProviderType = 'hms-iap' | 'wechat' | 'alipay';

/** 订单状态：参与本地状态机 + 后端轮询统一 */
export type OrderStatus =
  | 'created'      // 订单已创建，等待用户支付
  | 'pending'      // 已发起支付，等待结果
  | 'paid'         // 支付成功，待后端核销
  | 'verified'     // 后端已核销订阅生效
  | 'cancelled'    // 用户取消
  | 'failed'       // 支付失败
  | 'refunded';    // 已退款

/** 支付错误码：统一映射各家 SDK 异常 */
export type PaymentErrorCode =
  | 'user_cancelled'      // 用户取消支付
  | 'network_error'       // 网络异常
  | 'invalid_params'      // 参数错误（productId / amount）
  | 'not_logged_in'       // 未登录（HMS / 微信 / 支付宝账号）
  | 'sdk_not_ready'       // SDK 未初始化
  | 'sdk_not_installed'   // 微信 / 支付宝未安装
  | 'order_not_found'     // 订单不存在
  | 'verify_failed'       // 后端核销失败
  | 'sign_invalid'        // 签名校验失败
  | 'unknown';            // 未分类异常

/** 后端订单引用（createOrder 返回） */
export interface OrderRef {
  /** 后端订单 ID（UUID） */
  orderId: string;
  /** 订阅计划 */
  planCode: SubscriptionPlan;
  /** 金额（人民币元，保留 2 位小数） */
  amountCny: number;
  /** 支付通道 */
  provider: PaymentProviderType;
  /** 通道侧产品 ID（HMS productId / 微信商品号 / 支付宝商品号） */
  channelProductId?: string;
  /** 通道侧预下单参数（微信预支付串 / 支付宝 orderInfo / HMS PurchaseIntent） */
  channelPrepayPayload?: string;
}

/** 支付结果 */
export interface PayResult {
  success: boolean;
  status: OrderStatus;
  orderId: string;
  /** 通道侧凭证（IAP purchaseToken / 微信 prepayId / 支付宝 tradeNo） */
  channelToken?: string;
  /** 通道侧原始回执 JSON（用于后端 verify） */
  rawReceipt?: string;
  /** 失败时填充 */
  errorCode?: PaymentErrorCode;
  errorMessage?: string;
}

/** 支付异常（throw 时使用，PaymentManager 会捕获并转 PayResult） */
export class PaymentError extends Error {
  code: PaymentErrorCode;
  constructor(code: PaymentErrorCode, message: string) {
    super(message);
    this.code = code;
    this.name = 'PaymentError';
  }
}

/**
 * 支付 Provider 接口
 *
 * 三家 SDK 都需实现：
 *   1. initialize: SDK 初始化 + 登录态检查
 *   2. createOrder: 调后端创建订单 + 拉通道预下单参数
 *   3. pay: 唤起 SDK 支付界面
 *   4. query: 查询订单状态（用于支付中断后兜底）
 */
export interface PaymentProvider {
  readonly name: PaymentProviderType;
  initialize(): Promise<void>;
  createOrder(planCode: SubscriptionPlan, amountCny: number): Promise<OrderRef>;
  pay(orderRef: OrderRef): Promise<PayResult>;
  query(orderId: string): Promise<OrderStatus>;
}
