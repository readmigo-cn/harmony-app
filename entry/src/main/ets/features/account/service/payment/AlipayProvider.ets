/**
 * AlipayProvider.ets — 支付宝支付 Provider 实现（W17-C2，支付宝部分）
 *
 * 当前阶段（Phase 4）：
 *   - 支付宝开放平台 SDK 未集成，全部 SDK 调用走 mock。
 *   - 真实接入：https://opendocs.alipay.com/open/204/105051
 *
 * Phase 5 切换步骤：
 *   1. ohpm install @alipay/openSdk（占位包名，以支付宝官方发布为准）
 *   2. 在 module.json5 配置 alipayAppId、urlScheme（用于 deeplink 回调）
 *   3. 解开 import 注释，把 mockAlipay 替换为 alipay.payV2(orderInfo)
 *   4. 后端补 /subscription/orders/:id/alipay-prepay 接口（返回 orderInfo 字符串）
 *
 * 流程：
 *   1. createOrder: POST /subscription/orders 拿 orderId
 *      然后 POST /subscription/orders/:id/alipay-prepay 返回签好的 orderInfo
 *   2. pay: 把 orderInfo 透传给支付宝 SDK
 *   3. query: 后端轮询 /subscription/orders/:id（支付宝异步通知到后端）
 */

import { HttpClient } from '../../../../api/client/HttpClient';
import { SubscriptionPlan } from '../../../../api/subscription/SubscriptionApi';
import {
  PaymentProvider,
  PaymentProviderType,
  OrderRef,
  PayResult,
  OrderStatus,
  PaymentError,
  PaymentErrorCode,
} from './PaymentProvider';

// Phase 5 启用：
// import alipay from '@alipay/openSdk';

interface CreateOrderResponse {
  orderId: string;
  amountCny: number;
}

/** 支付宝 alipay.trade.app.pay 同步返回 resultStatus 码 */
const ALIPAY_RESULT_CODE_MAP: Record<string, PaymentErrorCode> = {
  '9000': 'unknown',         // 9000 = 支付成功（占位，不会进 error map）
  '8000': 'unknown',         // 处理中（待异步通知）
  '4000': 'unknown',         // 订单支付失败
  '5000': 'invalid_params',  // 重复请求
  '6001': 'user_cancelled',  // 用户中途取消
  '6002': 'network_error',   // 网络连接出错
  '6004': 'unknown',         // 支付结果未知
};

interface AlipayResult {
  resultStatus: string;       // 9000 = 成功
  result?: string;            // 业务结果 JSON
  memo?: string;
}

export class AlipayProvider implements PaymentProvider {
  readonly name: PaymentProviderType = 'alipay';
  private static readonly NATIVE_AVAILABLE: boolean = false;
  private static readonly ALIPAY_APP_ID: string = '2021XXXXXXXXXXXX';
  private initialized: boolean = false;

  /** SDK 初始化 */
  async initialize(): Promise<void> {
    if (this.initialized) return;
    if (!AlipayProvider.NATIVE_AVAILABLE) {
      await this.sleep(40);
      this.initialized = true;
      return;
    }
    // Phase 5：
    // const installed = await alipay.isAlipayInstalled();
    // if (!installed) throw new PaymentError('sdk_not_installed', '请先安装支付宝');
    this.initialized = true;
  }

  /**
   * 创建订单（两步）：
   *   1. POST /subscription/orders 拿 orderId
   *   2. POST /subscription/orders/:id/alipay-prepay 拿 orderInfo 字符串（已签名）
   */
  async createOrder(planCode: SubscriptionPlan, amountCny: number): Promise<OrderRef> {
    await this.ensureInitialized();
    if (amountCny <= 0) {
      throw new PaymentError('invalid_params', `invalid amountCny: ${amountCny}`);
    }
    try {
      const order = await this.requestCreateOrder(planCode, amountCny);
      const orderInfo = await this.requestAlipayOrderInfo(order.orderId);
      return {
        orderId: order.orderId,
        planCode,
        amountCny: order.amountCny,
        provider: 'alipay',
        channelProductId: AlipayProvider.ALIPAY_APP_ID,
        channelPrepayPayload: orderInfo,
      };
    } catch (err) {
      throw this.toPaymentError(err);
    }
  }

  /** 唤起支付宝支付 */
  async pay(orderRef: OrderRef): Promise<PayResult> {
    await this.ensureInitialized();
    if (!orderRef.channelPrepayPayload) {
      return this.buildFailResult(orderRef.orderId, 'invalid_params', 'missing orderInfo');
    }
    try {
      const result = await this.invokeAlipay(orderRef.channelPrepayPayload);
      return this.parseAlipayResult(orderRef.orderId, result);
    } catch (err) {
      const pe = this.toPaymentError(err);
      return this.buildFailResult(orderRef.orderId, pe.code, pe.message);
    }
  }

  /** 查询订单状态：调后端轮询（支付宝异步通知由后端接收） */
  async query(orderId: string): Promise<OrderStatus> {
    try {
      const resp = await HttpClient.get<{ status: OrderStatus }>(`/subscription/orders/${orderId}`);
      return resp.status;
    } catch (err) {
      return 'pending';
    }
  }

  // ─────────── 私有：HTTP 调用 ───────────

  private async requestCreateOrder(
    planCode: SubscriptionPlan,
    amountCny: number,
  ): Promise<CreateOrderResponse> {
    if (!AlipayProvider.NATIVE_AVAILABLE) {
      await this.sleep(150);
      return { orderId: `ali-${Date.now()}`, amountCny };
    }
    return await HttpClient.post<CreateOrderResponse>('/subscription/orders', {
      planCode,
      amountCny,
      paymentChannel: 'alipay',
    });
  }

  /**
   * 拿支付宝 orderInfo（已由后端用商户私钥签名）
   * orderInfo 是 RFC3986 编码的 key=value&... 字符串
   */
  private async requestAlipayOrderInfo(orderId: string): Promise<string> {
    if (!AlipayProvider.NATIVE_AVAILABLE) {
      await this.sleep(180);
      // mock orderInfo（仅供本地调试，真实接入由后端返回）
      const params = [
        `app_id=${AlipayProvider.ALIPAY_APP_ID}`,
        `method=alipay.trade.app.pay`,
        `charset=utf-8`,
        `sign_type=RSA2`,
        `timestamp=${encodeURIComponent(new Date().toISOString())}`,
        `version=1.0`,
        `notify_url=${encodeURIComponent('https://api.readmigo.cn/subscription/alipay/notify')}`,
        `biz_content=${encodeURIComponent(JSON.stringify({
          out_trade_no: orderId,
          total_amount: '0.01',
          subject: 'Readmigo Subscription',
          product_code: 'QUICK_MSECURITY_PAY',
        }))}`,
        `sign=MOCK_SIGN_DO_NOT_USE_IN_PROD`,
      ];
      return params.join('&');
    }
    const resp = await HttpClient.post<{ orderInfo: string }>(
      `/subscription/orders/${orderId}/alipay-prepay`,
    );
    return resp.orderInfo;
  }

  // ─────────── 私有：SDK 调用 ───────────

  private async invokeAlipay(orderInfo: string): Promise<AlipayResult> {
    if (!AlipayProvider.NATIVE_AVAILABLE) {
      return await this.mockAlipay(orderInfo);
    }
    // Phase 5：
    // return await alipay.payV2(orderInfo);
    return await this.mockAlipay(orderInfo);
  }

  private async mockAlipay(_orderInfo: string): Promise<AlipayResult> {
    await this.sleep(900);
    return {
      resultStatus: '9000',
      result: JSON.stringify({
        alipay_trade_app_pay_response: {
          code: '10000',
          msg: 'Success',
          out_trade_no: 'mock-out-trade-no',
          trade_no: `mock-ali-tx-${Date.now()}`,
        },
      }),
      memo: '',
    };
  }

  // ─────────── 私有：结果解析 ───────────

  private parseAlipayResult(orderId: string, result: AlipayResult): PayResult {
    if (result.resultStatus === '9000') {
      return {
        success: true,
        status: 'paid',  // 真正 verified 由后端 notify 回调推送
        orderId,
        channelToken: this.extractTradeNo(result.result),
        rawReceipt: JSON.stringify(result),
      };
    }
    if (result.resultStatus === '8000' || result.resultStatus === '6004') {
      // 支付处理中，结果未知 → pending（PaymentManager 轮询）
      return {
        success: false,
        status: 'pending',
        orderId,
        errorCode: 'unknown',
        errorMessage: `alipay_pending_${result.resultStatus}`,
      };
    }
    const code = ALIPAY_RESULT_CODE_MAP[result.resultStatus] ?? 'unknown';
    return this.buildFailResult(
      orderId,
      code,
      result.memo ?? `alipay_err_${result.resultStatus}`,
    );
  }

  private extractTradeNo(resultJson?: string): string | undefined {
    if (!resultJson) return undefined;
    try {
      const parsed = JSON.parse(resultJson) as {
        alipay_trade_app_pay_response?: { trade_no?: string };
      };
      return parsed.alipay_trade_app_pay_response?.trade_no;
    } catch {
      return undefined;
    }
  }

  // ─────────── 私有：辅助 ───────────

  private async ensureInitialized(): Promise<void> {
    if (!this.initialized) await this.initialize();
  }

  private buildFailResult(
    orderId: string,
    code: PaymentErrorCode,
    message: string,
  ): PayResult {
    return {
      success: false,
      status: code === 'user_cancelled' ? 'cancelled' : 'failed',
      orderId,
      errorCode: code,
      errorMessage: message,
    };
  }

  private toPaymentError(err: unknown): PaymentError {
    if (err instanceof PaymentError) return err;
    const e = err as Error;
    return new PaymentError('unknown', e?.message ?? 'alipay_unknown_error');
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, ms));
  }
}
