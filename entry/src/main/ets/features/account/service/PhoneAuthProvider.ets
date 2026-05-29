/**
 * PhoneAuthProvider — Phone OTP authentication (W6).
 *
 * Delegates to backend-driven OTP flow (sendSmsCode / loginByCode from AuthApi).
 * HMS Auth SDK integration is a future option but the backend-driven approach
 * is preferred here to avoid HMS Auth SDK dependency and keep OTP logic server-side.
 *
 * This provider wraps AuthApi calls and adds:
 *   - Input validation
 *   - requestId tracking for correlation (backend returns it on sendCode)
 *   - Structured result types consistent with HuaweiAuthResult / WeChatAuthResult
 */

import { AuthApi, LoginResult } from '../../../api/auth/AuthApi';

const TAG = 'PhoneAuthProvider';

const PHONE_REGEX = new RegExp('^1[3-9]\\d{9}$');

export interface OtpRequestResult {
  /** Correlation id returned by backend; forward to verifyOtp. */
  requestId: string;
  /** Seconds until the code expires / resend is allowed. */
  expireSeconds: number;
}

export interface AuthResult {
  token: string;
  refreshToken: string;
  userId: string;
  nickname?: string;
  avatarUrl?: string;
}

class PhoneAuthProviderImpl {
  /** Send OTP to phone number. Throws ApiError on failure. */
  async requestOtp(phoneNumber: string): Promise<OtpRequestResult> {
    if (!PHONE_REGEX.test(phoneNumber)) {
      throw new Error('invalid_phone');
    }
    await AuthApi.sendSmsCode(phoneNumber);
    // Backend does not return requestId in current schema; generate a local
    // correlation key. Replace when /auth/sms/send starts returning one.
    const requestId = `${phoneNumber}:${Date.now()}`;
    console.info(`${TAG} OTP sent, requestId=${requestId}`);
    return { requestId, expireSeconds: 60 };
  }

  /** Verify OTP and return auth tokens. Throws ApiError on wrong code. */
  async verifyOtp(phone: string, code: string): Promise<AuthResult> {
    if (!PHONE_REGEX.test(phone)) {
      throw new Error('invalid_phone');
    }
    if (code.length !== 6) {
      throw new Error('invalid_code_length');
    }
    const res: LoginResult = await AuthApi.loginByCode(phone, code);
    console.info(`${TAG} OTP verified, userId=${res.userId}`);
    return {
      token: res.token,
      refreshToken: res.refreshToken,
      userId: res.userId,
      nickname: res.nickname,
      avatarUrl: res.avatarUrl,
    };
  }

  /** Phone + password login (existing accounts). */
  async loginByPassword(emailOrPhone: string, password: string): Promise<AuthResult> {
    const res: LoginResult = await AuthApi.loginByPassword(emailOrPhone, password);
    return {
      token: res.token,
      refreshToken: res.refreshToken,
      userId: res.userId,
      nickname: res.nickname,
      avatarUrl: res.avatarUrl,
    };
  }
}

export const PhoneAuthProvider = new PhoneAuthProviderImpl();
