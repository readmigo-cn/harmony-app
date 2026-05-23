/**
 * HmsIapProvider.ets — HMS IAP 支付 Provider 实现（W17-C2，HMS 部分）
 *
 * 当前阶段（Phase 4）：
 *   - HMS Account Kit / IAP Kit 未集成，全部 SDK 调用走 mock。
 *   - 真实接入参考：https://developer.huawei.com/consumer/cn/doc/HMSCore-References/iap-overview-0000001050033062
 *
 * Phase 5 切换步骤：
 *   1. ohpm install @hms.iap @hms.account
 *   2. 解开 import 注释
 *   3. 把 mockCreatePurchaseIntent / mockStartPay / mockObtainOwnedPurchases 替换为真实 API
 *   4. 单测覆盖：取消、网络异常、未登录、参数错误
 */

import { SubscriptionApi, SubscriptionPlan, VerifyIapPayload } from '../../../../api/subscription/SubscriptionApi';
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
// import iap from '@hms.iap';
// import account from '@hms.account';

/** SubscriptionPlan -> HMS productId 映射（与 IAPService.IAP_PRODUCTS 保持一致） */
const PLAN_TO_HMS_PRODUCT: Record<SubscriptionPlan, string> = {
  pro_monthly: 'cn.readmigo.harmony.pro_monthly',
  pro_yearly: 'cn.readmigo.harmony.pro_yearly',
  premium_monthly: 'cn.readmigo.harmony.premium_monthly',
};

/** HMS IAP 错误码 -> 统一错误码映射（参考华为官方文档） */
const HMS_ERROR_CODE_MAP: Record<number, PaymentErrorCode> = {
  60000: 'user_cancelled',     // OrderStatusCode.ORDER_STATE_CANCEL
  60050: 'not_logged_in',      // OrderStatusCode.ORDER_HWID_NOT_LOGIN
  60051: 'invalid_params',     // OrderStatusCode.ORDER_PRODUCT_OWNED
  60054: 'invalid_params',     // OrderStatusCode.ORDER_ACCOUNT_AREA_NOT_SUPPORTED
  60055: 'sdk_not_ready',      // OrderStatusCode.ORDER_NOT_ACCEPT_AGREEMENT
  -1: 'network_error',
};

interface HmsPurchaseIntentResult {
  productId: string;
  purchaseToken: string;
  rawReceipt: string;
}

interface HmsOwnedPurchase {
  productId: string;
  purchaseToken: string;
  purchaseTime: number;
  purchaseState: number; // 0 = 已支付，1 = 已取消
}

export class HmsIapProvider implements PaymentProvider {
  readonly name: PaymentProviderType = 'hms-iap';
  private static readonly NATIVE_AVAILABLE: boolean = false;
  private initialized: boolean = false;

  /** SDK 初始化 + 登录态检查 */
  async initialize(): Promise<void> {
    if (this.initialized) return;
    if (!HmsIapProvider.NATIVE_AVAILABLE) {
      // mock：模拟 SDK 初始化
      await this.sleep(50);
      this.initialized = true;
      return;
    }
    // Phase 5 真实接入：
    // try {
    //   const env = await iap.isEnvReady();
    //   if (env.returnCode !== 0) throw new PaymentError('sdk_not_ready', 'IAP env not ready');
    //   const session = await account.getAuthorization();
    //   if (!session) throw new PaymentError('not_logged_in', 'HMS account required');
    //   this.initialized = true;
    // } catch (err) {
    //   throw this.mapError(err);
    // }
    this.initialized = true;
  }

  /**
   * 创建订单
   * HMS IAP 流程：通道侧不需预下单，直接由后端记录订单 ID，
   * 通道 productId 由 PLAN_TO_HMS_PRODUCT 映射。
   */
  async createOrder(planCode: SubscriptionPlan, amountCny: number): Promise<OrderRef> {
    await this.ensureInitialized();
    const channelProductId = PLAN_TO_HMS_PRODUCT[planCode];
    if (!channelProductId) {
      throw new PaymentError('invalid_params', `unknown plan: ${planCode}`);
    }
    // mock：本地生成订单 ID（Phase 5 应调 SubscriptionApi.createOrder）
    const orderId = `hms-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
    return {
      orderId,
      planCode,
      amountCny,
      provider: 'hms-iap',
      channelProductId,
    };
  }

  /** 唤起 HMS IAP 支付，成功后调用后端 verify */
  async pay(orderRef: OrderRef): Promise<PayResult> {
    await this.ensureInitialized();
    try {
      const intent = await this.startPurchase(orderRef.channelProductId!);
      // 调用后端核销（与现有 SubscriptionApi.verify 保持一致）
      const verifyPayload: VerifyIapPayload = {
        productId: intent.productId,
        plan: orderRef.planCode,
        purchaseToken: intent.purchaseToken,
        rawReceipt: intent.rawReceipt,
      };
      await SubscriptionApi.verify(verifyPayload);
      // 核销成功后消耗订阅凭证（订阅类无需 consume，但保留接口对齐 IAP Kit）
      await this.consumeOwnedPurchase(intent.purchaseToken);
      return {
        success: true,
        status: 'verified',
        orderId: orderRef.orderId,
        channelToken: intent.purchaseToken,
        rawReceipt: intent.rawReceipt,
      };
    } catch (err) {
      const pe = this.toPaymentError(err);
      return {
        success: false,
        status: pe.code === 'user_cancelled' ? 'cancelled' : 'failed',
        orderId: orderRef.orderId,
        errorCode: pe.code,
        errorMessage: pe.message,
      };
    }
  }

  /** 查询订单状态：先查后端，再兜底查 HMS owned purchases */
  async query(orderId: string): Promise<OrderStatus> {
    await this.ensureInitialized();
    // Phase 5：调 SubscriptionApi.getOrderStatus(orderId)
    // mock 阶段直接返回 created
    if (!HmsIapProvider.NATIVE_AVAILABLE) {
      return 'created';
    }
    const owned = await this.obtainOwnedPurchases();
    const matched = owned.find((p) => p.purchaseToken.includes(orderId));
    if (!matched) return 'created';
    return matched.purchaseState === 0 ? 'paid' : 'cancelled';
  }

  // ─────────── 私有：SDK 调用层（mock + 真实接入开关） ───────────

  private async startPurchase(productId: string): Promise<HmsPurchaseIntentResult> {
    if (!HmsIapProvider.NATIVE_AVAILABLE) {
      return await this.mockCreatePurchaseIntent(productId);
    }
    // Phase 5：
    // const intent = await iap.createPurchaseIntent({ productId, priceType: 2 });
    // const result = await iap.startPay(intent);
    // return { productId, purchaseToken: result.purchaseToken, rawReceipt: result.inAppPurchaseData };
    return await this.mockCreatePurchaseIntent(productId);
  }

  private async obtainOwnedPurchases(): Promise<HmsOwnedPurchase[]> {
    if (!HmsIapProvider.NATIVE_AVAILABLE) return [];
    // Phase 5：
    // const result = await iap.obtainOwnedPurchases({ priceType: 2 });
    // return result.itemList.map((item) => JSON.parse(item) as HmsOwnedPurchase);
    return [];
  }

  private async consumeOwnedPurchase(purchaseToken: string): Promise<void> {
    if (!HmsIapProvider.NATIVE_AVAILABLE) {
      await this.sleep(20);
      return;
    }
    // Phase 5（订阅一般不需 consume，但保留接口）：
    // await iap.consumeOwnedPurchase({ purchaseToken });
  }

  // ─────────── 私有：mock 实现 ───────────

  private async mockCreatePurchaseIntent(productId: string): Promise<HmsPurchaseIntentResult> {
    await this.sleep(800);
    const purchaseToken = `hms-mock-${productId}-${Date.now()}`;
    const rawReceipt = JSON.stringify({
      productId,
      purchaseToken,
      purchaseState: 0,
      purchaseTime: Date.now(),
      orderId: purchaseToken,
    });
    return { productId, purchaseToken, rawReceipt };
  }

  // ─────────── 私有：辅助 ───────────

  private async ensureInitialized(): Promise<void> {
    if (!this.initialized) await this.initialize();
  }

  private toPaymentError(err: unknown): PaymentError {
    if (err instanceof PaymentError) return err;
    const e = err as Error & { code?: number };
    if (typeof e?.code === 'number' && HMS_ERROR_CODE_MAP[e.code]) {
      return new PaymentError(HMS_ERROR_CODE_MAP[e.code], e.message ?? 'hms_iap_error');
    }
    return new PaymentError('unknown', e?.message ?? 'unknown_error');
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, ms));
  }
}
