/**
 * WechatProvider.ets — 微信支付 Provider 实现（W17-C2，微信部分）
 *
 * 当前阶段（Phase 4）：
 *   - 微信开放平台 SDK 未集成，全部 SDK 调用走 mock。
 *   - 真实接入：https://pay.weixin.qq.com/wiki/doc/api/wxa/wxa_api.php
 *
 * Phase 5 切换步骤：
 *   1. ohpm install @wechat/openSdk（占位包名，以微信官方发布为准）
 *   2. 在 module.json5 配置 wxAppId、universalLink
 *   3. 解开 import 注释，把 mockWxPay 替换为 wx.sendReq(payReq)
 *   4. 实现 deeplink callback 处理（onWxRequest）
 *   5. 后端补 /subscription/orders/:id/wechat-prepay 接口（返回 prepayId + 签名）
 *
 * 流程：
 *   1. createOrder: POST /subscription/orders   → 后端返回 orderId
 *      然后 POST /subscription/orders/:id/wechat-prepay → 返回微信预下单参数
 *   2. pay: 用预下单参数构造 PayReq，调 wx.sendReq() 唤起微信
 *   3. query: 微信回调 / 后端轮询 /subscription/orders/:id
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
// import wx from '@wechat/openSdk';

/** 微信预下单返回（后端 /wechat-prepay 接口） */
interface WechatPrepayPayload {
  appId: string;
  partnerId: string;
  prepayId: string;
  packageValue: string;  // 固定 "Sign=WXPay"
  nonceStr: string;
  timeStamp: string;
  sign: string;          // 后端签好的二次签名
}

/** 后端创建订单响应 */
interface CreateOrderResponse {
  orderId: string;
  amountCny: number;
}

/** 微信 SDK 错误码 -> 统一错误码（参考微信开放平台） */
const WX_ERROR_CODE_MAP: Record<number, PaymentErrorCode> = {
  0: 'unknown',           // 占位（0 实际是成功）
  '-1': 'unknown',
  '-2': 'user_cancelled', // 用户取消
  '-3': 'sign_invalid',   // 签名错误
  '-4': 'not_logged_in',
  '-5': 'sdk_not_installed',
} as Record<number, PaymentErrorCode>;

interface WxPayResult {
  errCode: number;
  errStr?: string;
  prepayId: string;
  transactionId?: string;
}

export class WechatProvider implements PaymentProvider {
  readonly name: PaymentProviderType = 'wechat';
  private static readonly NATIVE_AVAILABLE: boolean = false;
  /** 微信开放平台分配的 AppID（Phase 5 从配置读取） */
  private static readonly WX_APP_ID: string = 'wxXXXXXXXXXXXXXXXX';
  private initialized: boolean = false;

  /** SDK 初始化：注册 AppID + universalLink */
  async initialize(): Promise<void> {
    if (this.initialized) return;
    if (!WechatProvider.NATIVE_AVAILABLE) {
      await this.sleep(40);
      this.initialized = true;
      return;
    }
    // Phase 5：
    // const installed = await wx.isWXAppInstalled();
    // if (!installed) throw new PaymentError('sdk_not_installed', '请先安装微信');
    // const ok = await wx.registerApp({ appId: WechatProvider.WX_APP_ID, universalLink: 'https://m.readmigo.cn/wx' });
    // if (!ok) throw new PaymentError('sdk_not_ready', 'register wx app failed');
    this.initialized = true;
  }

  /**
   * 创建订单（两步）：
   *   1. POST /subscription/orders 拿 orderId
   *   2. POST /subscription/orders/:id/wechat-prepay 拿微信预下单参数
   */
  async createOrder(planCode: SubscriptionPlan, amountCny: number): Promise<OrderRef> {
    await this.ensureInitialized();
    if (amountCny <= 0) {
      throw new PaymentError('invalid_params', `invalid amountCny: ${amountCny}`);
    }
    try {
      const order = await this.requestCreateOrder(planCode, amountCny);
      const prepay = await this.requestWechatPrepay(order.orderId);
      return {
        orderId: order.orderId,
        planCode,
        amountCny: order.amountCny,
        provider: 'wechat',
        channelProductId: prepay.prepayId,
        channelPrepayPayload: JSON.stringify(prepay),
      };
    } catch (err) {
      throw this.toPaymentError(err);
    }
  }

  /** 唤起微信支付 */
  async pay(orderRef: OrderRef): Promise<PayResult> {
    await this.ensureInitialized();
    if (!orderRef.channelPrepayPayload) {
      return this.buildFailResult(orderRef.orderId, 'invalid_params', 'missing prepay payload');
    }
    try {
      const prepay = JSON.parse(orderRef.channelPrepayPayload) as WechatPrepayPayload;
      // 客户端签名校验（防止后端下发被中间人篡改）
      this.assertPrepaySignature(prepay);
      const result = await this.invokeWxPay(prepay);
      if (result.errCode !== 0) {
        const code = WX_ERROR_CODE_MAP[result.errCode] ?? 'unknown';
        return this.buildFailResult(orderRef.orderId, code, result.errStr ?? `wx_err_${result.errCode}`);
      }
      return {
        success: true,
        status: 'paid',  // 真正 verified 由后端微信回调推送
        orderId: orderRef.orderId,
        channelToken: result.prepayId,
        rawReceipt: JSON.stringify(result),
      };
    } catch (err) {
      const pe = this.toPaymentError(err);
      return this.buildFailResult(orderRef.orderId, pe.code, pe.message);
    }
  }

  /** 查询订单状态：调后端轮询（微信本身不提供客户端查单 API） */
  async query(orderId: string): Promise<OrderStatus> {
    try {
      const resp = await HttpClient.get<{ status: OrderStatus }>(`/subscription/orders/${orderId}`);
      return resp.status;
    } catch (err) {
      // 网络异常时返回 pending，由 PaymentManager 决定是否重试
      return 'pending';
    }
  }

  // ─────────── 私有：HTTP 调用 ───────────

  private async requestCreateOrder(
    planCode: SubscriptionPlan,
    amountCny: number,
  ): Promise<CreateOrderResponse> {
    if (!WechatProvider.NATIVE_AVAILABLE) {
      // mock：本地生成
      await this.sleep(150);
      return { orderId: `wx-${Date.now()}`, amountCny };
    }
    return await HttpClient.post<CreateOrderResponse>('/subscription/orders', {
      planCode,
      amountCny,
      paymentChannel: 'wechat',
    });
  }

  private async requestWechatPrepay(orderId: string): Promise<WechatPrepayPayload> {
    if (!WechatProvider.NATIVE_AVAILABLE) {
      // mock 微信预下单返回
      await this.sleep(200);
      return {
        appId: WechatProvider.WX_APP_ID,
        partnerId: '1900000109',
        prepayId: `wx-prepay-mock-${orderId}`,
        packageValue: 'Sign=WXPay',
        nonceStr: this.randomNonce(),
        timeStamp: Math.floor(Date.now() / 1000).toString(),
        sign: 'MOCK_SIGN_DO_NOT_USE_IN_PROD',
      };
    }
    return await HttpClient.post<WechatPrepayPayload>(
      `/subscription/orders/${orderId}/wechat-prepay`,
    );
  }

  // ─────────── 私有：SDK 调用 ───────────

  private async invokeWxPay(prepay: WechatPrepayPayload): Promise<WxPayResult> {
    if (!WechatProvider.NATIVE_AVAILABLE) {
      return await this.mockWxPay(prepay);
    }
    // Phase 5：
    // const payReq = {
    //   appId: prepay.appId,
    //   partnerId: prepay.partnerId,
    //   prepayId: prepay.prepayId,
    //   packageValue: prepay.packageValue,
    //   nonceStr: prepay.nonceStr,
    //   timeStamp: prepay.timeStamp,
    //   sign: prepay.sign,
    // };
    // const resp = await wx.sendReq(payReq);
    // return { errCode: resp.errCode, errStr: resp.errStr, prepayId: prepay.prepayId, transactionId: resp.transactionId };
    return await this.mockWxPay(prepay);
  }

  private async mockWxPay(prepay: WechatPrepayPayload): Promise<WxPayResult> {
    await this.sleep(900);
    return {
      errCode: 0,
      prepayId: prepay.prepayId,
      transactionId: `mock-tx-${Date.now()}`,
    };
  }

  // ─────────── 私有：签名校验 ───────────

  /**
   * 客户端签名结构校验（不做 MD5/HMAC 二次签名，由微信 SDK 自行校验）
   * 防御点：必填字段缺失 / packageValue 被篡改
   */
  private assertPrepaySignature(prepay: WechatPrepayPayload): void {
    if (!prepay.appId || !prepay.partnerId || !prepay.prepayId) {
      throw new PaymentError('sign_invalid', 'prepay payload missing required fields');
    }
    if (prepay.packageValue !== 'Sign=WXPay') {
      throw new PaymentError('sign_invalid', `unexpected packageValue: ${prepay.packageValue}`);
    }
    if (!prepay.sign || prepay.sign.length < 16) {
      throw new PaymentError('sign_invalid', 'sign too short');
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
    return new PaymentError('unknown', e?.message ?? 'wechat_unknown_error');
  }

  private randomNonce(): string {
    return Math.random().toString(36).slice(2, 18);
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, ms));
  }
}
