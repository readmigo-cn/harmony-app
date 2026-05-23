import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import { RoutePath } from '../../../core/router/RouteConstants';
import { UserStore } from '../../../store/UserStore';
import { AuthApi, LoginResult } from '../../../api/auth/AuthApi';
import { ApiError } from '../../../api/client/HttpClient';
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
// W18-C1：Login 入口曝光埋点
import { Analytics } from '../../../core/analytics/AnalyticsProvider';
import { SaEvents } from '../../../core/analytics/SensorsAnalytics';

/**
 * Login —— 登录页（W4-C1）。
 *
 * Tabs: 短信 / 华为账号 / 微信 / 密码
 * 中国手机号校验：1[3-9]\d{9}
 * SMS 码 6 位 + 60s 倒计时
 * 华为/微信 一键登录在 Phase 4 接入 HMS Account Kit / 微信开放平台 SDK；
 * 当前为 Mock：500ms 延迟后用 'mock-' + 随机串 调用后端的 huaweiLogin / wechatLogin。
 *
 * 登录成功后：
 * - 写 UserStore.setToken
 * - 缓存最后一次 phone 到 AppStorage('last_login_phone')
 * - replace 路由到 Main（首页）
 */

type LoginTab = 'sms' | 'huawei' | 'wechat' | 'password';

const PHONE_REGEX = new RegExp('^1[3-9]\\d{9}$');
const LAST_PHONE_KEY = 'last_login_phone';

@Component
export struct Login {
  @State tab: LoginTab = 'sms';
  @State phone: string = '';
  @State code: string = '';
  @State email: string = '';
  @State password: string = '';
  @State countryCode: string = '+86';
  @State sending: boolean = false;
  @State submitting: boolean = false;
  @State countdown: number = 0;
  @State errorMsg: string = '';
  @State agreed: boolean = false;
  private timer: number = -1;

  aboutToAppear(): void {
    const last = AppStorage.Get<string>(LAST_PHONE_KEY);
    if (last && PHONE_REGEX.test(last)) {
      this.phone = last;
    }
    Analytics.track(SaEvents.PAGE_VIEW, { page: 'login' });
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  // ---------- helpers ----------

  private validPhone(): boolean {
    return PHONE_REGEX.test(this.phone);
  }

  private validCode(): boolean {
    return this.code.length === 6;
  }

  private validPassword(): boolean {
    return this.password.length >= 6;
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

  private setError(msg: string): void {
    this.errorMsg = msg;
  }

  private clearError(): void {
    if (this.errorMsg) {
      this.errorMsg = '';
    }
  }

  private async handleSuccess(res: LoginResult): Promise<void> {
    UserStore.setToken(res.token, res.refreshToken);
    AppStorage.SetOrCreate<string>(LAST_PHONE_KEY, this.phone);
    if (res.userId) {
      UserStore.setProfile({
        id: res.userId,
        phone: this.phone || undefined,
        nickname: res.nickname ?? '',
        avatarUrl: res.avatarUrl,
      });
    }
    promptAction.showToast({ message: '登录成功' });
    RouterService.replace(RoutePath.MAIN);
  }

  private handleApiError(err: Object, fallback: string): void {
    const e = err as ApiError;
    const msg = e?.message ?? fallback;
    this.setError(msg);
    promptAction.showToast({ message: msg });
  }

  // ---------- actions ----------

  private async onSendCode(): Promise<void> {
    this.clearError();
    if (!this.validPhone()) {
      this.setError('请输入正确的手机号');
      return;
    }
    if (this.sending || this.countdown > 0) return;
    if (!this.agreed) {
      this.setError('请先勾选同意《用户协议》和《隐私政策》');
      return;
    }
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

  private async onSubmitSms(): Promise<void> {
    this.clearError();
    if (!this.validPhone()) {
      this.setError('请输入正确的手机号');
      return;
    }
    if (!this.validCode()) {
      this.setError('请输入 6 位验证码');
      return;
    }
    if (!this.agreed) {
      this.setError('请先勾选同意《用户协议》和《隐私政策》');
      return;
    }
    if (this.submitting) return;
    this.submitting = true;
    try {
      const res = await AuthApi.loginByCode(this.phone, this.code);
      await this.handleSuccess(res);
    } catch (err) {
      this.handleApiError(err as Object, '登录失败');
    } finally {
      this.submitting = false;
    }
  }

  private async onSubmitPassword(): Promise<void> {
    this.clearError();
    const idLooksPhone = PHONE_REGEX.test(this.email);
    const idLooksEmail = this.email.indexOf('@') > 0;
    if (!idLooksPhone && !idLooksEmail) {
      this.setError('请输入手机号或邮箱');
      return;
    }
    if (!this.validPassword()) {
      this.setError('密码至少 6 位');
      return;
    }
    if (!this.agreed) {
      this.setError('请先勾选同意《用户协议》和《隐私政策》');
      return;
    }
    if (this.submitting) return;
    this.submitting = true;
    try {
      const res = await AuthApi.loginByPassword(this.email, this.password);
      await this.handleSuccess(res);
    } catch (err) {
      this.handleApiError(err as Object, '登录失败');
    } finally {
      this.submitting = false;
    }
  }

  private async onHuaweiLogin(): Promise<void> {
    this.clearError();
    if (!this.agreed) {
      this.setError('请先勾选同意《用户协议》和《隐私政策》');
      return;
    }
    if (this.submitting) return;
    this.submitting = true;
    try {
      // Mock：Phase 4 替换为 HMS Account Kit getAuthorizationCode()
      await new Promise<void>((resolve) => setTimeout(() => resolve(), 500));
      const mockAuthCode = 'mock-hw-' + Math.random().toString(36).slice(2, 10);
      const res = await AuthApi.huaweiLogin(mockAuthCode);
      await this.handleSuccess(res);
    } catch (err) {
      this.handleApiError(err as Object, '华为账号登录失败');
    } finally {
      this.submitting = false;
    }
  }

  private async onWechatLogin(): Promise<void> {
    this.clearError();
    if (!this.agreed) {
      this.setError('请先勾选同意《用户协议》和《隐私政策》');
      return;
    }
    if (this.submitting) return;
    this.submitting = true;
    try {
      // Mock：Phase 4 替换为微信开放平台 sendAuth
      await new Promise<void>((resolve) => setTimeout(() => resolve(), 500));
      const mockAuthCode = 'mock-wx-' + Math.random().toString(36).slice(2, 10);
      const res = await AuthApi.wechatLogin(mockAuthCode);
      await this.handleSuccess(res);
    } catch (err) {
      this.handleApiError(err as Object, '微信登录失败');
    } finally {
      this.submitting = false;
    }
  }

  private onForgotPassword(): void {
    // 未登录态：直接用 router.pushUrl 跳转重置密码独立页
    // 把当前输入的手机号（密码 tab 的 email 字段可能也是手机号）带过去，节省重复输入
    const prefill = PHONE_REGEX.test(this.phone)
      ? this.phone
      : (PHONE_REGEX.test(this.email) ? this.email : '');
    router.pushUrl({
      url: RoutePath.PASSWORD_RESET_URL,
      params: { phone: prefill },
    }).catch((_e: Error) => {
      // 若 main_pages.json 未注册会抛错；此处吞掉避免崩溃
      promptAction.showToast({ message: '页面未注册' });
    });
  }

  private onOpenTerms(kind: 'user' | 'privacy'): void {
    const title = kind === 'user' ? '《用户协议》' : '《隐私政策》';
    promptAction.showToast({ message: `${title}（占位 WebView 待补）` });
  }

  // ---------- builders ----------

  @Builder
  TabBar() {
    Row() {
      ForEach(['sms', 'huawei', 'wechat', 'password'] as LoginTab[], (k: LoginTab) => {
        Text(this.tabLabel(k))
          .fontSize(AppFontSize.sm)
          .fontWeight(this.tab === k ? AppFontWeight.bold : AppFontWeight.regular)
          .fontColor(this.tab === k ? AppColors.brand : AppColors.textSecondary)
          .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm, left: AppSpacing.md, right: AppSpacing.md })
          .border({ width: { bottom: this.tab === k ? 2 : 0 }, color: AppColors.brand })
          .onClick(() => {
            this.tab = k;
            this.clearError();
          });
      }, (k: LoginTab) => k);
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceAround)
  }

  private tabLabel(t: LoginTab): string {
    switch (t) {
      case 'sms': return '短信登录';
      case 'huawei': return '华为账号';
      case 'wechat': return '微信登录';
      case 'password': return '密码登录';
    }
  }

  @Builder
  PhoneRow() {
    Row({ space: AppSpacing.sm }) {
      // 区号选择器（默认 +86，仅占位）
      Text(this.countryCode)
        .fontSize(AppFontSize.md)
        .fontColor(AppColors.textPrimary)
        .padding({ left: AppSpacing.base, right: AppSpacing.base })
        .height(48)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.base)
        .onClick(() => promptAction.showToast({ message: '仅支持中国大陆 +86' }));

      TextInput({ placeholder: $r('app.string.login_phone_placeholder'), text: this.phone })
        .type(InputType.PhoneNumber)
        .maxLength(11)
        .height(48)
        .layoutWeight(1)
        .padding(AppSpacing.base)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.base)
        .onChange((v: string) => {
          this.phone = v;
          this.clearError();
        });
    }
    .width('100%')
  }

  @Builder
  SmsTab() {
    Column({ space: AppSpacing.md }) {
      this.PhoneRow();

      Row({ space: AppSpacing.sm }) {
        TextInput({ placeholder: $r('app.string.login_code_placeholder'), text: this.code })
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

      Button($r('app.string.login_submit'))
        .width('100%')
        .height(48)
        .fontSize(AppFontSize.md)
        .backgroundColor(AppColors.brand)
        .borderRadius(AppRadius.base)
        .enabled(this.validPhone() && this.validCode() && !this.submitting)
        .onClick(() => this.onSubmitSms());
    }
  }

  @Builder
  PasswordTab() {
    Column({ space: AppSpacing.md }) {
      TextInput({ placeholder: '手机号或邮箱', text: this.email })
        .type(InputType.Email)
        .height(48)
        .padding(AppSpacing.base)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.base)
        .onChange((v: string) => {
          this.email = v;
          this.clearError();
        });

      TextInput({ placeholder: '密码（至少 6 位）', text: this.password })
        .type(InputType.Password)
        .height(48)
        .padding(AppSpacing.base)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.base)
        .onChange((v: string) => {
          this.password = v;
          this.clearError();
        });

      Button($r('app.string.login_submit'))
        .width('100%')
        .height(48)
        .fontSize(AppFontSize.md)
        .backgroundColor(AppColors.brand)
        .borderRadius(AppRadius.base)
        .enabled(!this.submitting)
        .onClick(() => this.onSubmitPassword());

      Text('忘记密码？')
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.brand)
        .alignSelf(ItemAlign.End)
        .onClick(() => this.onForgotPassword());
    }
  }

  @Builder
  HuaweiTab() {
    Column({ space: AppSpacing.md }) {
      Text('使用华为账号一键登录')
        .fontSize(AppFontSize.base)
        .fontColor(AppColors.textSecondary)
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ top: AppSpacing.lg, bottom: AppSpacing.lg })

      Button($r('app.string.login_huawei'))
        .width('100%')
        .height(48)
        .fontSize(AppFontSize.md)
        .backgroundColor(AppColors.brand)
        .borderRadius(AppRadius.base)
        .enabled(!this.submitting)
        .onClick(() => this.onHuaweiLogin());
    }
  }

  @Builder
  WechatTab() {
    Column({ space: AppSpacing.md }) {
      Text('使用微信一键登录')
        .fontSize(AppFontSize.base)
        .fontColor(AppColors.textSecondary)
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ top: AppSpacing.lg, bottom: AppSpacing.lg })

      Button($r('app.string.login_wechat'))
        .width('100%')
        .height(48)
        .fontSize(AppFontSize.md)
        .backgroundColor('#07C160')
        .fontColor(AppColors.textInverse)
        .borderRadius(AppRadius.base)
        .enabled(!this.submitting)
        .onClick(() => this.onWechatLogin());
    }
  }

  @Builder
  TermsRow() {
    Row({ space: AppSpacing.xs }) {
      Toggle({ type: ToggleType.Checkbox, isOn: this.agreed })
        .width(20)
        .height(20)
        .selectedColor(AppColors.brand)
        .onChange((on: boolean) => { this.agreed = on; });

      Text() {
        Span($r('app.string.login_terms_prefix'))
          .fontColor(AppColors.textSecondary)
        Span($r('app.string.login_terms_user'))
          .fontColor(AppColors.brand)
          .onClick(() => this.onOpenTerms('user'))
        Span(' 与 ')
          .fontColor(AppColors.textSecondary)
        Span($r('app.string.login_terms_privacy'))
          .fontColor(AppColors.brand)
          .onClick(() => this.onOpenTerms('privacy'))
      }
      .fontSize(AppFontSize.xs)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  build() {
    NavDestination() {
      Column({ space: AppSpacing.lg }) {
        Text($r('app.string.app_name'))
          .fontSize(AppFontSize.title)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
          .margin({ top: AppSpacing.xxl })

        Text($r('app.string.login_title'))
          .fontSize(AppFontSize.lg)
          .fontColor(AppColors.textSecondary)

        this.TabBar();

        if (this.tab === 'sms') {
          this.SmsTab();
        } else if (this.tab === 'huawei') {
          this.HuaweiTab();
        } else if (this.tab === 'wechat') {
          this.WechatTab();
        } else {
          this.PasswordTab();
        }

        if (this.errorMsg) {
          Text(this.errorMsg)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.danger)
            .width('100%')
        }

        Blank().layoutWeight(1)

        this.TermsRow();
      }
      .width('100%')
      .height('100%')
      .padding(AppSpacing.lg)
      .backgroundColor(AppColors.bgPrimary)
    }
    .hideTitleBar(true)
  }
}
