/**
 * PaymentManager.ets — 支付统一调度器（W17-C3 / W6）
 *
 * 职责：
 *   - 管理 3 家 Provider 单例（懒加载）
 *   - 端到端调度：getProvider → createOrder → pay → 错误反馈
 *   - 与 ToastManager 集成（成功/失败 toast）
 *   - 支付成功后触发 SubscriptionState.refresh()
 *   - 埋点：payment.initiated / payment.succeeded / payment.failed
 *   - 暴露 query 用于支付中断后兜底
 *
 * 与 W3 SubscriptionApi 集成：
 *   - createOrder 阶段由各 Provider 内部调用 SubscriptionApi（HMS 直接 verify，
 *     微信/支付宝 通过 /subscription/orders + /:id/{wechat,alipay}-prepay）
 *   - pay 阶段成功后由各 Provider 内部触发后端 verify 或等异步通知
 */

import { ToastManager } from '../../../../ui/primitives/Toast';
import { SubscriptionPlan, PaymentChannel } from '../../../../api/subscription/SubscriptionApi';
import {
  PaymentProvider,
  PaymentProviderType,
  PayResult,
  OrderStatus,
  PaymentError,
  PaymentErrorCode,
} from './PaymentProvider';
import { HmsIapProvider } from './HmsIapProvider';
import { WechatProvider } from './WechatProvider';
import { AlipayProvider } from './AlipayProvider';
import { SubscriptionState } from '../subscription/SubscriptionState';
import { Analytics } from '../../../../core/analytics/AnalyticsProvider';

/** PaymentChannel (UI layer) -> PaymentProviderType (provider layer) */
const CHANNEL_TO_PROVIDER: Record<PaymentChannel, PaymentProviderType> = {
  hms_iap: 'hms-iap',
  wechat: 'wechat',
  alipay: 'alipay',
};

/** 错误码 -> 用户可见提示文案（中文） */
const ERROR_TOAST_MAP: Record<PaymentErrorCode, string> = {
  user_cancelled: '已取消支付',
  network_error: '网络异常，请稍后再试',
  invalid_params: '订单参数错误',
  not_logged_in: '请先登录账号',
  sdk_not_ready: '支付组件初始化失败',
  sdk_not_installed: '请先安装对应支付应用',
  order_not_found: '订单不存在',
  verify_failed: '订阅核销失败，请联系客服',
  sign_invalid: '订单签名校验失败',
  unknown: '支付失败，请稍后再试',
};

/** 统一支付入口参数 */
export interface PayRequest {
  /** UI 层传入的支付通道（与 PaymentChannel 对齐） */
  channel: PaymentChannel;
  /** 订阅计划 */
  planCode: SubscriptionPlan;
  /** 金额（人民币元） */
  amountCny: number;
}

export class PaymentManager {
  private static providers: Map<PaymentProviderType, PaymentProvider> = new Map();

  /** 取（或懒创建）指定通道的 Provider */
  static getProvider(type: PaymentProviderType): PaymentProvider {
    let provider = PaymentManager.providers.get(type);
    if (provider) return provider;
    switch (type) {
      case 'hms-iap':
        provider = new HmsIapProvider();
        break;
      case 'wechat':
        provider = new WechatProvider();
        break;
      case 'alipay':
        provider = new AlipayProvider();
        break;
      default:
        throw new PaymentError('invalid_params', `unknown provider: ${type}`);
    }
    PaymentManager.providers.set(type, provider);
    return provider;
  }

  /**
   * 统一入口（供 Paywall / Subscriptions 调用）：
   *   1. channel -> providerType 映射
   *   2. provider.initialize()
   *   3. provider.createOrder(planCode, amountCny)
   *   4. provider.pay(orderRef)
   *   5. 埋点 + toast 反馈 + SubscriptionState.refresh()
   */
  static async pay(req: PayRequest): Promise<PayResult> {
    const type = CHANNEL_TO_PROVIDER[req.channel];
    if (!type) {
      const pe = new PaymentError('invalid_params', `unknown channel: ${req.channel}`);
      ToastManager.error(ERROR_TOAST_MAP['invalid_params']);
      return { success: false, status: 'failed', orderId: '', errorCode: 'invalid_params', errorMessage: pe.message };
    }
    const provider = PaymentManager.getProvider(type);
    Analytics.track('payment.initiated', { channel: req.channel, plan: req.planCode, amount: req.amountCny });
    try {
      await provider.initialize();
      const orderRef = await provider.createOrder(req.planCode, req.amountCny);
      const result = await provider.pay(orderRef);
      PaymentManager.notifyResult(result);
      if (result.success) {
        Analytics.track('payment.succeeded', { channel: req.channel, plan: req.planCode, orderId: result.orderId });
        SubscriptionState.getInstance().refresh().catch((_e: Error) => {});
      } else {
        Analytics.track('payment.failed', {
          channel: req.channel,
          plan: req.planCode,
          errorCode: result.errorCode ?? 'unknown',
        });
      }
      return result;
    } catch (err) {
      const pe = err instanceof PaymentError
        ? err
        : new PaymentError('unknown', (err as Error)?.message ?? 'pay_failed');
      Analytics.track('payment.failed', { channel: req.channel, plan: req.planCode, errorCode: pe.code });
      ToastManager.error(ERROR_TOAST_MAP[pe.code]);
      return {
        success: false,
        status: pe.code === 'user_cancelled' ? 'cancelled' : 'failed',
        orderId: '',
        errorCode: pe.code,
        errorMessage: pe.message,
      };
    }
  }

  /** @deprecated Use pay(PayRequest) instead */
  static async payLegacy(
    planCode: SubscriptionPlan,
    amountCny: number,
    type: PaymentProviderType,
  ): Promise<PayResult> {
    const channelMap: Record<PaymentProviderType, PaymentChannel> = {
      'hms-iap': 'hms_iap',
      'wechat': 'wechat',
      'alipay': 'alipay',
    };
    return PaymentManager.pay({ channel: channelMap[type], planCode, amountCny });
  }

  /** 查询订单状态（用于 app 重启 / 切回前台时的状态恢复） */
  static async query(type: PaymentProviderType, orderId: string): Promise<OrderStatus> {
    const provider = PaymentManager.getProvider(type);
    return await provider.query(orderId);
  }

  /** 统一根据 PayResult 出 toast */
  private static notifyResult(result: PayResult): void {
    if (result.success) {
      ToastManager.success('支付成功');
      return;
    }
    if (result.status === 'cancelled') {
      ToastManager.info(ERROR_TOAST_MAP['user_cancelled']);
      return;
    }
    if (result.status === 'pending') {
      ToastManager.info('支付处理中，稍后请到「我的订阅」查看结果');
      return;
    }
    const code = result.errorCode ?? 'unknown';
    ToastManager.error(ERROR_TOAST_MAP[code]);
  }
}
