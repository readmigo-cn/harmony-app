/**
 * HuaweiAccountProvider — Huawei Account Kit (HMS AccountKit) integration (W6).
 *
 * Real SDK: @kit.AccountKit (HarmonyOS NEXT Stage Mode).
 * Fallback: mock with same shape when SDK is unavailable in build env.
 *
 * Flow:
 *   signIn() → AccountKit.presentLoginPage() → returns authCode
 *   authCode is exchanged by backend via /auth/huawei-login
 *
 * Wire-up:
 *   Login.ets calls HuaweiAccountProvider.signIn() instead of the inline mock.
 *   AuthService calls getCurrentUser() for IAP user-binding.
 */

const TAG = 'HuaweiAccountProvider';

export interface HuaweiUser {
  unionId: string;
  openId: string;
  displayName?: string;
  avatarUri?: string;
  email?: string;
}

export interface HuaweiAuthResult {
  authCode: string;
  user: HuaweiUser;
}

// Attempt to import the real HMS Account Kit SDK.
// The 'try-import' pattern keeps this file compilable when the SDK is absent.
let AccountKit: {
  presentLoginPage: (params: object) => Promise<{ authCode: string; unionId: string; openId: string; displayName?: string; avatarUri?: string; email?: string }>;
} | null = null;

try {
  // Real import — available when HMS AccountKit HAR is declared in oh-package.json5
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  AccountKit = require('@kit.AccountKit') as typeof AccountKit;
} catch (_) {
  console.warn(`${TAG} @kit.AccountKit not available, using mock`);
}

class HuaweiAccountProviderImpl {
  private currentUser: HuaweiUser | null = null;

  /**
   * Trigger Huawei Account one-tap login sheet.
   * Returns an authCode the backend exchanges for tokens.
   */
  async signIn(): Promise<HuaweiAuthResult> {
    if (AccountKit) {
      return await this.signInReal();
    }
    return await this.signInMock();
  }

  async signOut(): Promise<void> {
    this.currentUser = null;
    if (AccountKit) {
      // Real SDK does not require an explicit signOut call; clearing local state is sufficient.
      // If the SDK exposes a revoke method in future, call it here.
    }
    console.info(`${TAG} signed out`);
  }

  getCurrentUser(): HuaweiUser | null {
    return this.currentUser;
  }

  // ---------- real ----------

  private async signInReal(): Promise<HuaweiAuthResult> {
    const sdk = AccountKit!;
    const raw = await sdk.presentLoginPage({
      // Request authCode scope for server-side exchange
      scopes: ['profile', 'email'],
      requestCode: 8888,
    });
    const user: HuaweiUser = {
      unionId: raw.unionId,
      openId: raw.openId,
      displayName: raw.displayName,
      avatarUri: raw.avatarUri,
      email: raw.email,
    };
    this.currentUser = user;
    console.info(`${TAG} signIn real ok, unionId=${user.unionId}`);
    return { authCode: raw.authCode, user };
  }

  // ---------- mock ----------

  private async signInMock(): Promise<HuaweiAuthResult> {
    await new Promise<void>((r) => setTimeout(r, 400));
    const id = Math.random().toString(36).slice(2, 10);
    const user: HuaweiUser = {
      unionId: `mock-union-${id}`,
      openId: `mock-open-${id}`,
      displayName: '华为用户_' + id.slice(0, 4),
    };
    this.currentUser = user;
    const authCode = `mock-hw-${id}`;
    console.info(`${TAG} signIn mock ok, authCode=${authCode}`);
    return { authCode, user };
  }
}

export const HuaweiAccountProvider = new HuaweiAccountProviderImpl();
