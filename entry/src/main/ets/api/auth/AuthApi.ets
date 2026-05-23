import { HttpClient } from '../../api/client/HttpClient';

/**
 * AuthApi —— 与 server-cn `/api/v1/auth/*` 一一对应。
 * 仅暴露 Promise 接口，不做 toast / store 写入；调用方自行处理。
 */

export interface SendCodeRequest {
  phone: string;
}

export interface LoginByCodeRequest {
  phone: string;
  code: string;
}

export interface LoginByPasswordRequest {
  emailOrPhone: string;
  password: string;
}

export interface RegisterRequest {
  phone?: string;
  email?: string;
  password: string;
  code?: string;
  nickname?: string;
}

export interface RefreshRequest {
  refreshToken: string;
}

export interface ResetPasswordRequest {
  phone: string;
  code: string;
  newPassword: string;
}

export interface LoginResult {
  token: string;
  refreshToken: string;
  userId: string;
  /** 后端可选返回的用户基本信息，可能为空 */
  nickname?: string;
  avatarUrl?: string;
}

export interface RefreshResult {
  token: string;
  refreshToken: string;
}

export class AuthApi {
  /** 发送 6 位短信验证码到手机号；后端限频 60s 一次 */
  static sendSmsCode(phone: string): Promise<void> {
    return HttpClient.post<void>('/auth/sms/send', { phone }, { auth: false });
  }

  /** 短信验证码登录 / 注册（首次登录时后端自动注册） */
  static loginByCode(phone: string, code: string): Promise<LoginResult> {
    return HttpClient.post<LoginResult>('/auth/sms/login', { phone, code }, { auth: false });
  }

  /** 邮箱/手机号 + 密码登录（管理员或老用户） */
  static loginByPassword(emailOrPhone: string, password: string): Promise<LoginResult> {
    return HttpClient.post<LoginResult>('/auth/login', { emailOrPhone, password }, { auth: false });
  }

  /** 注册（密码模式） */
  static register(dto: RegisterRequest): Promise<LoginResult> {
    return HttpClient.post<LoginResult>('/auth/register', dto, { auth: false });
  }

  /** 刷新 token */
  static refresh(refreshToken: string): Promise<RefreshResult> {
    return HttpClient.post<RefreshResult>('/auth/refresh', { refreshToken }, { auth: false });
  }

  /** 华为账号登录：authCode 由 HMS Account Kit 取得 */
  static huaweiLogin(authCode: string): Promise<LoginResult> {
    return HttpClient.post<LoginResult>('/auth/huawei-login', { authCode }, { auth: false });
  }

  /** 微信登录：authCode 由微信开放平台 SDK 取得 */
  static wechatLogin(authCode: string): Promise<LoginResult> {
    return HttpClient.post<LoginResult>('/auth/wechat-login', { authCode }, { auth: false });
  }

  /** 登出（让后端 refreshToken 失效） */
  static logout(): Promise<void> {
    return HttpClient.post<void>('/auth/logout');
  }

  /** 重置密码：先 sendSmsCode，再调用此方法 */
  static resetPassword(phone: string, code: string, newPassword: string): Promise<void> {
    return HttpClient.post<void>('/auth/reset-password', { phone, code, newPassword }, { auth: false });
  }
}
