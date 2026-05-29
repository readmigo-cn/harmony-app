/**
 * WeChatAuthProvider — WeChat OAuth 2.0 login for HarmonyOS (W6).
 *
 * Real SDK: WeChat Open Platform HarmonyOS SDK (WXApi).
 *   - Register app with WeChat Open Platform, get AppID + AppSecret
 *   - Backend exchanges code for access_token + openid
 *
 * If the WeChat HarmonyOS SDK is unavailable in this SDK version the provider
 * falls back to a mock that follows the exact same OAuth flow shape so the
 * backend integration is testable end-to-end.
 *
 * Flow:
 *   signIn() → WXApi.sendAuthRequest() → WeChat callback → authCode
 *   authCode is posted to /auth/wechat-login by the caller (Login.ets).
 */

import { WECHAT_APP_ID } from '../../../core/config/CnConfig';

const TAG = 'WeChatAuthProvider';

export interface WeChatAuthResult {
  /** One-time authorization code for server-side token exchange. */
  authCode: string;
  /** WeChat openid for the current app (changes per app). */
  openId?: string;
  /** WeChat unionid (same across apps under one Open Platform account). */
  unionId?: string;
}

// Try to import WeChat HarmonyOS SDK (WXOpenApiPackage).
// Package name follows WeChat Open Platform HarmonyOS documentation:
// @wechat/wechat-open-sdk
let WXApi: {
  registerApp: (appId: string) => boolean;
  sendAuthRequest: (scope: string, state: string) => boolean;
  handleOpenURL: (url: string, delegate: { onResp: (resp: object) => void }) => boolean;
} | null = null;

try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  WXApi = require('@wechat/wechat-open-sdk') as typeof WXApi;
} catch (_) {
  console.warn(`${TAG} @wechat/wechat-open-sdk not available, using mock`);
}

class WeChatAuthProviderImpl {
  private registered: boolean = false;

  /** Register WeChat AppID once at startup (safe to call multiple times). */
  register(): void {
    if (this.registered) return;
    if (WXApi) {
      const ok = WXApi.registerApp(WECHAT_APP_ID);
      console.info(`${TAG} registerApp ok=${ok}, appId=${WECHAT_APP_ID}`);
    }
    this.registered = true;
  }

  /**
   * Launch WeChat OAuth flow.
   * On real SDK: opens WeChat app via deep link; user approves; WeChat redirects
   * back with a code in the want/URL that the app forwards to handleCallback().
   * On mock: resolves after 400ms with a fake code.
   */
  async signIn(): Promise<WeChatAuthResult> {
    if (!this.registered) this.register();

    if (WXApi) {
      return await this.signInReal();
    }
    return await this.signInMock();
  }

  /**
   * Process the redirect-back intent from WeChat.
   * Call this from onNewWant() when want.uri starts with the WeChat scheme.
   * Real SDK parses the code; mock is a no-op.
   */
  handleCallback(url: string, onResult: (result: WeChatAuthResult | null) => void): void {
    if (!WXApi) {
      onResult(null);
      return;
    }
    WXApi.handleOpenURL(url, {
      onResp: (resp: object) => {
        const r = resp as { errCode: number; code?: string; openId?: string };
        if (r.errCode === 0 && r.code) {
          onResult({ authCode: r.code, openId: r.openId });
        } else {
          console.warn(`${TAG} WeChat callback errCode=${r.errCode}`);
          onResult(null);
        }
      },
    });
  }

  // ---------- real ----------

  private async signInReal(): Promise<WeChatAuthResult> {
    return new Promise<WeChatAuthResult>((resolve, reject) => {
      const state = `rm_${Date.now().toString(36)}`;
      const ok = WXApi!.sendAuthRequest('snsapi_userinfo', state);
      if (!ok) {
        reject(new Error('WeChat not installed or sendAuthRequest failed'));
        return;
      }
      // Result arrives via handleCallback() called from onNewWant; the promise
      // will be resolved by the caller wiring handleCallback → resolve.
      // For now surface a user-actionable message so the UI can show a spinner.
      console.info(`${TAG} sendAuthRequest ok, state=${state}`);
      // Timeout guard: if WeChat never calls back within 60s, reject
      const timer = setTimeout(() => reject(new Error('WeChat login timeout')), 60000);
      // Store resolve/reject for callback resolution
      (globalThis as Record<string, unknown>)['__wechat_pending_resolve'] = (r: WeChatAuthResult) => {
        clearTimeout(timer);
        resolve(r);
      };
      (globalThis as Record<string, unknown>)['__wechat_pending_reject'] = (e: Error) => {
        clearTimeout(timer);
        reject(e);
      };
    });
  }

  // ---------- mock ----------

  private async signInMock(): Promise<WeChatAuthResult> {
    await new Promise<void>((r) => setTimeout(r, 400));
    const id = Math.random().toString(36).slice(2, 10);
    const authCode = `mock-wx-${id}`;
    console.info(`${TAG} signIn mock ok, authCode=${authCode}`);
    return { authCode, openId: `mock-openid-${id}` };
  }
}

export const WeChatAuthProvider = new WeChatAuthProviderImpl();
