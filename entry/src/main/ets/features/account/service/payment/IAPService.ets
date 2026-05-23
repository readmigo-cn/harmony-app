import { SubscriptionApi, SubscriptionPlan } from '../../../../api/subscription/SubscriptionApi';

/**
 * HMS IAP 客户端封装。
 * 当前阶段：HMS Account Kit 未接入，purchase 走 mock。
 * Phase 4 切换到 `import iap from '@hms.iap'`，调用 createPurchaseIntentAsync 等真实 API。
 */

export interface IapProduct {
  productId: string;
  plan: SubscriptionPlan;
  priceCny: string;
  title: string;
  desc: string;
}

export const IAP_PRODUCTS: IapProduct[] = [
  {
    productId: 'cn.readmigo.harmony.pro_monthly',
    plan: 'pro_monthly',
    priceCny: '¥35',
    title: 'Pro 月订阅',
    desc: 'AI 划词 + 全本图书 + 进度同步',
  },
  {
    productId: 'cn.readmigo.harmony.pro_yearly',
    plan: 'pro_yearly',
    priceCny: '¥213',
    title: 'Pro 年订阅（省 50%）',
    desc: '一年使用，平均每月仅 ¥17.75',
  },
  {
    productId: 'cn.readmigo.harmony.premium_monthly',
    plan: 'premium_monthly',
    priceCny: '¥71',
    title: 'Premium 月订阅',
    desc: 'Pro 全部功能 + 高级 TTS + 听书无限',
  },
];

export interface PurchaseResult {
  success: boolean;
  productId: string;
  plan: SubscriptionPlan;
  errorMessage?: string;
}

export class IAPService {
  private static readonly NATIVE_AVAILABLE: boolean = false;

  static async purchase(product: IapProduct): Promise<PurchaseResult> {
    if (!IAPService.NATIVE_AVAILABLE) {
      // dev mock：模拟 1 秒"用户支付"延迟，然后向后端走 verify 流程
      await IAPService.sleep(800);
      const mockToken = `mock-${product.productId}-${Date.now()}`;
      const mockReceipt = JSON.stringify({
        productId: product.productId,
        purchaseToken: mockToken,
        purchaseState: 0,
        purchaseTime: Date.now(),
      });
      try {
        await SubscriptionApi.verify({
          productId: product.productId,
          plan: product.plan,
          purchaseToken: mockToken,
          rawReceipt: mockReceipt,
        });
        return { success: true, productId: product.productId, plan: product.plan };
      } catch (err) {
        const e = err as Error;
        return {
          success: false,
          productId: product.productId,
          plan: product.plan,
          errorMessage: e.message ?? 'verify_failed',
        };
      }
    }

    // 真实 HMS IAP（Phase 4 启用）：
    // 1. import iap from '@hms.iap';
    // 2. const intent = await iap.createPurchaseIntent({ productId, priceType: 2 });
    // 3. const receipt = await iap.startPay(intent);
    // 4. SubscriptionApi.verify(...)
    return { success: false, productId: product.productId, plan: product.plan, errorMessage: 'native_iap_not_ready' };
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, ms));
  }
}
