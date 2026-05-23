import router from '@ohos.router';
import promptAction from '@ohos.promptAction';

import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { AuthApi } from '../../../api/auth/AuthApi';
import { ApiError } from '../../../api/client/HttpClient';

/**
 * PasswordReset —— 忘记密码 / 密码重置页（W4-C1 续）。
 *
 * 流程：
 *   1) 输入手机号 + 点「获取验证码」（60s 倒计时，复用 Login 的 OTP 模式）
 *   2) 输入 6 位验证码
 *   3) 输入新密码 + 确认新密码（≥6 位、两次必须一致）
 *   4) 提交：AuthApi.resetPassword(phone, code, newPassword)
 *   5) 成功 → toast 提示 + router.back() 回 Login
 *
 * 路由：通过 router.pushUrl({ url: 'features/account/pages/PasswordReset', params: { phone? } }) 进入。
 * 不需要 auth guard（未登录用户使用）。
 */

interface PasswordResetParams {
  phone?: string;
}

const PHONE_REGEX = new RegExp('^1[3-9]\\d{9}$');

@Entry
@Component
struct PasswordReset {
  @State phone: string = '';
  @State code: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';
  @State sending: boolean = false;
  @State submitting: boolean = false;
  @State countdown: number = 0;
  @State errorMsg: string = '';
  private timer: number = -1;

  aboutToAppear(): void {
    // 从路由参数取上一页传入的手机号（Login 跳转时会带 phone）
    const params = router.getParams() as PasswordResetParams | undefined;
    if (params && params.phone && PHONE_REGEX.test(params.phone)) {
      this.phone = params.phone;
    }
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  // ---------- 校验 ----------

  private validPhone(): boolean {
    return PHONE_REGEX.test(this.phone);
  }

  private validCode(): boolean {
    return this.code.length === 6;
  }

  private validPassword(): boolean {
    return this.newPassword.length >= 6;
  }

  private passwordsMatch(): boolean {
    return this.newPassword === this.confirmPassword;
  }

  private setError(msg: string): void {
    this.errorMsg = msg;
  }

  private clearError(): void {
    if (this.errorMsg) this.errorMsg = '';
  }

  private startCountdown(): void {
    this.countdown = 60;
    this.timer = setInterval(() => {
      this.countdown -= 1;
      if (this.countdown <= 0) {
        clearInterval(this.timer);
        this.timer = -1;
      }
    }, 1000) as number;
  }

  private handleApiError(err: Object, fallback: string): void {
    const e = err as ApiError;
    const msg = e?.message ?? fallback;
    this.setError(msg);
    promptAction.showToast({ message: msg });
  }

  // ---------- 动作 ----------

  private async onSendCode(): Promise<void> {
    this.clearError();
    if (!this.validPhone()) {
      this.setError('请输入正确的手机号');
      return;
    }
    if (this.sending || this.countdown > 0) return;
    this.sending = true;
    try {
      await AuthApi.sendSmsCode(this.phone);
      this.startCountdown();
      promptAction.showToast({ message: '验证码已发送' });
    } catch (err) {
      this.handleApiError(err as Object, '发送失败');
    } finally {
      this.sending = false;
    }
  }

  private async onSubmit(): Promise<void> {
    this.clearError();
    if (!this.validPhone()) {
      this.setError('请输入正确的手机号');
      return;
    }
    if (!this.validCode()) {
      this.setError('请输入 6 位验证码');
      return;
    }
    if (!this.validPassword()) {
      this.setError('新密码至少 6 位');
      return;
    }
    if (!this.passwordsMatch()) {
      this.setError('两次输入的密码不一致');
      return;
    }
    if (this.submitting) return;
    this.submitting = true;
    try {
      await AuthApi.resetPassword(this.phone, this.code, this.newPassword);
      promptAction.showToast({ message: '密码重置成功，请重新登录' });
      // 成功后回到 Login 页
      router.back();
    } catch (err) {
      this.handleApiError(err as Object, '重置失败');
    } finally {
      this.submitting = false;
    }
  }

  // ---------- UI ----------

  build() {
    Column({ space: AppSpacing.lg }) {
      // header
      Row({ space: AppSpacing.sm }) {
        Text('< 返回')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.brand)
          .onClick(() => router.back())
        Blank()
        Text('重置密码')
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
        Blank()
      }
      .width('100%')
      .padding(AppSpacing.base)

      // 手机号
      TextInput({ placeholder: '请输入手机号', text: this.phone })
        .type(InputType.PhoneNumber)
        .maxLength(11)
        .height(48)
        .padding(AppSpacing.base)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.base)
        .onChange((v: string) => {
          this.phone = v;
          this.clearError();
        });

      // 验证码 + 发送按钮
      Row({ space: AppSpacing.sm }) {
        TextInput({ placeholder: '6 位验证码', text: this.code })
          .type(InputType.Number)
          .maxLength(6)
          .height(48)
          .layoutWeight(1)
          .padding(AppSpacing.base)
          .backgroundColor(AppColors.bgSecondary)
          .borderRadius(AppRadius.base)
          .onChange((v: string) => {
            this.code = v;
            this.clearError();
          });

        Button(this.countdown > 0 ? `${this.countdown}s` : '获取验证码')
          .height(48)
          .width(120)
          .fontSize(AppFontSize.sm)
          .backgroundColor(this.countdown > 0 ? AppColors.bgSecondary : AppColors.brand)
          .fontColor(this.countdown > 0 ? AppColors.textSecondary : AppColors.textInverse)
          .enabled(this.countdown === 0 && this.validPhone() && !this.sending)
          .onClick(() => this.onSendCode());
      }
      .width('100%')

      // 新密码
      TextInput({ placeholder: '新密码（至少 6 位）', text: this.newPassword })
        .type(InputType.Password)
        .height(48)
        .padding(AppSpacing.base)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.base)
        .onChange((v: string) => {
          this.newPassword = v;
          this.clearError();
        });

      // 确认新密码
      TextInput({ placeholder: '确认新密码', text: this.confirmPassword })
        .type(InputType.Password)
        .height(48)
        .padding(AppSpacing.base)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.base)
        .onChange((v: string) => {
          this.confirmPassword = v;
          this.clearError();
        });

      // 提交按钮
      Button('重置密码')
        .width('100%')
        .height(48)
        .fontSize(AppFontSize.md)
        .backgroundColor(AppColors.brand)
        .fontColor(AppColors.textInverse)
        .borderRadius(AppRadius.base)
        .enabled(
          this.validPhone() &&
          this.validCode() &&
          this.validPassword() &&
          this.passwordsMatch() &&
          !this.submitting
        )
        .onClick(() => this.onSubmit());

      if (this.errorMsg) {
        Text(this.errorMsg)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.danger)
          .width('100%')
      }

      Blank().layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding(AppSpacing.lg)
    .backgroundColor(AppColors.bgPrimary)
  }
}
