/**
 * PaymentDeepLinkHandler.ets — 支付宝 / 微信 DeepLink 回调中转（W6）
 *
 * 当 Alipay SDK / WeChat SDK（Phase 5）通过 URL Scheme 回调时，
 * EntryAbility.onNewWant 把 want.uri 转发到此处，
 * 对应 Provider 的 pendingResolver 消费结果。
 *
 * Phase 4 mock 阶段：SDK 调用阻塞等待后直接返回，不经过 deeplink。
 * Phase 5 启用：AlipayProvider.invokeAlipay / WechatProvider.invokeWxPay
 *   在调用 SDK 前先调 PaymentDeepLinkHandler.register()，
 *   SDK 通过 URL Scheme 唤起 EntryAbility.onNewWant，
 *   onNewWant 调 PaymentDeepLinkHandler.dispatch(uri)，
 *   resolver 拿到 uri 解析结果。
 */

export type DeepLinkScheme = 'alipay' | 'wechat';

type Resolver = (uri: string) => void;

/** 单例：每次只允许一个待处理支付 */
export class PaymentDeepLinkHandler {
  private static pending: Map<DeepLinkScheme, Resolver> = new Map();

  /**
   * Provider 在唤起 SDK 前注册 resolver。
   * 超时后应由 Provider 主动取消注册（cancel）。
   */
  static register(scheme: DeepLinkScheme, resolver: Resolver): void {
    PaymentDeepLinkHandler.pending.set(scheme, resolver);
  }

  /** Provider 超时 / 完成时主动取消注册（防止残留 resolver 被错误触发）。 */
  static cancel(scheme: DeepLinkScheme): void {
    PaymentDeepLinkHandler.pending.delete(scheme);
  }

  /**
   * EntryAbility.onNewWant 调用：检测 URI scheme 并派发给对应 resolver。
   * 返回 true 表示已由支付回调消费，false 表示应继续走普通 deeplink 路由。
   */
  static dispatch(uri: string): boolean {
    if (!uri) return false;
    const lower = uri.toLowerCase();
    if (lower.startsWith('alipays://') || lower.startsWith('alipay://')) {
      const resolver = PaymentDeepLinkHandler.pending.get('alipay');
      if (resolver) {
        PaymentDeepLinkHandler.pending.delete('alipay');
        resolver(uri);
        return true;
      }
    }
    if (lower.startsWith('weixin://') || lower.startsWith('weixinpay://')) {
      const resolver = PaymentDeepLinkHandler.pending.get('wechat');
      if (resolver) {
        PaymentDeepLinkHandler.pending.delete('wechat');
        resolver(uri);
        return true;
      }
    }
    return false;
  }
}
