/**
 * Feedback.ets — W19-C1 反馈表单
 *
 * 流程：
 *   1) 用户选择类别 / 输入标题（≤50 字）/ 描述（≤500 字）
 *   2) 可选上传截图（最多 3 张，图片选择器占位）
 *   3) 自动附加 app/os/device/userId/route + 最近 30 行日志（可勾去）
 *   4) 提交 → SupportApi.submitTicket → 跳 TicketDetail(ticketId)
 *
 * 自动附加日志策略：
 *   - 来源：RouterService.getHistory() 最后 30 条 + AppStorage 'app_log_buffer'
 *     （后者由 W18 telemetry 写入，缺失时只送 route history）
 *   - 用户可关闭「附带最近日志」开关，关闭后 recentLogs 字段不发送
 *   - 默认开启，并在表单中以 expandable 列表预览前 5 条
 */

import promptAction from '@ohos.promptAction';
import deviceInfo from '@ohos.deviceInfo';
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import {
  RoutePath,
  FeedbackRouteParams,
  TicketDetailRouteParams,
} from '../../../core/router/RouteConstants';
import { UserStore } from '../../../store/UserStore';
import { AppButton } from '../../../ui/primitives/Button';
import { AppCard } from '../../../ui/primitives/Card';
import { AppTextArea, AppInput } from '../../../ui/primitives/Input';
import { ToastManager } from '../../../ui/primitives/Toast';
import {
  SupportApi,
  SubmitTicketPayload,
  TicketCategory,
  TicketContext,
  ticketCategoryLabel,
  ticketCategoryIcon,
} from '../../../api/support/SupportApi';

const APP_VERSION = '0.1.0';
const MAX_TITLE = 50;
const MAX_DESC = 500;
const MAX_SHOTS = 3;
const RECENT_LOG_LINES = 30;

const CATEGORIES: TicketCategory[] = [
  'bug', 'feature', 'content', 'payment', 'account', 'other',
];

@Component
export struct FeedbackPage {
  @State category: TicketCategory = 'bug';
  @State title: string = '';
  @State description: string = '';
  @State screenshots: string[] = [];
  @State attachLogs: boolean = true;
  @State submitting: boolean = false;
  @State errMsg: string = '';
  /** 触发页面，用于上下文 */
  @State fromRoute: string = '';

  aboutToAppear(): void {
    const p = RouterService.getParams<FeedbackRouteParams>(RoutePath.FEEDBACK);
    if (p?.category) {
      const c = p.category as TicketCategory;
      if (CATEGORIES.indexOf(c) >= 0) this.category = c;
    }
    this.fromRoute = p?.fromRoute ?? this.detectFromRoute();
  }

  private detectFromRoute(): string {
    const hist = RouterService.getHistory();
    // history 最后一条是当前 Feedback 自己，取倒数第二条
    if (hist.length >= 2) return hist[hist.length - 2].route;
    return '';
  }

  /** 收集最近 30 行 "日志"。无 telemetry 时退化为 route history。 */
  private collectRecentLogs(): string[] {
    const fromBuffer = AppStorage.Get<string[]>('app_log_buffer') ?? [];
    if (fromBuffer.length > 0) {
      return fromBuffer.slice(-RECENT_LOG_LINES);
    }
    const hist = RouterService.getHistory();
    return hist.slice(-RECENT_LOG_LINES).map((h) => {
      const t = new Date(h.at).toISOString();
      return `[${t}] route=${h.route}`;
    });
  }

  private buildContext(): TicketContext {
    const profile = UserStore.getProfile();
    const ctx: TicketContext = {
      appVersion: APP_VERSION,
      os: `HarmonyOS NEXT ${deviceInfo.osFullName ?? ''}`.trim(),
      deviceModel: `${deviceInfo.brand ?? ''} ${deviceInfo.productModel ?? ''}`.trim(),
      userId: profile?.id,
      currentRoute: this.fromRoute,
    };
    if (this.attachLogs) {
      ctx.recentLogs = this.collectRecentLogs();
    }
    return ctx;
  }

  private validate(): string {
    if (this.title.trim().length === 0) return '请填写标题';
    if (this.title.length > MAX_TITLE) return `标题不超过 ${MAX_TITLE} 字`;
    if (this.description.trim().length === 0) return '请描述详细问题';
    if (this.description.length > MAX_DESC) return `描述不超过 ${MAX_DESC} 字`;
    return '';
  }

  private async submit(): Promise<void> {
    const err = this.validate();
    if (err) {
      this.errMsg = err;
      ToastManager.error(err);
      return;
    }
    this.submitting = true;
    this.errMsg = '';
    try {
      const payload: SubmitTicketPayload = {
        category: this.category,
        title: this.title.trim(),
        description: this.description.trim(),
        screenshots: this.screenshots.length > 0 ? this.screenshots : undefined,
        context: this.buildContext(),
      };
      const ticket = await SupportApi.submitTicket(payload);
      ToastManager.success('反馈已提交');
      const param: TicketDetailRouteParams = { ticketId: ticket.id };
      RouterService.replace(RoutePath.TICKET_DETAIL, param);
    } catch (e) {
      this.errMsg = (e as Error).message ?? '提交失败';
      ToastManager.error('提交失败：' + this.errMsg);
    } finally {
      this.submitting = false;
    }
  }

  private async pickScreenshot(): Promise<void> {
    if (this.screenshots.length >= MAX_SHOTS) {
      promptAction.showToast({ message: `最多只能上传 ${MAX_SHOTS} 张` });
      return;
    }
    // 占位实现：W11+ 接入 @ohos.file.photoAccessHelper 后替换
    // 当前先 push 一个 placeholder URL 让流程跑通
    const ph = `local://screenshot/${Date.now()}.png`;
    this.screenshots = [...this.screenshots, ph];
    promptAction.showToast({ message: '已添加（占位，W11+ 接图片选择器）' });
  }

  private removeScreenshot(idx: number): void {
    const next = this.screenshots.slice();
    next.splice(idx, 1);
    this.screenshots = next;
  }

  // ─── UI ─────────────────────────────────────

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: AppSpacing.base }) {
          this.categorySection()
          this.titleSection()
          this.descSection()
          this.screenshotSection()
          this.contextSection()
          this.submitSection()
        }
        .width('100%')
        .padding(AppSpacing.base)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgPrimary)
    }
    .title('反馈与帮助')
    .onBackPressed(() => { RouterService.back(); return true; })
  }

  @Builder
  categorySection() {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Column({ space: AppSpacing.sm }) {
        Text('问题类别')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textSecondary)
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(CATEGORIES, (c: TicketCategory) => {
            Row({ space: 4 }) {
              Text(ticketCategoryIcon(c))
                .fontSize(AppFontSize.sm)
              Text(ticketCategoryLabel(c))
                .fontSize(AppFontSize.sm)
                .fontColor(this.category === c ? AppColors.textInverse : AppColors.textPrimary)
            }
            .padding({ left: AppSpacing.sm, right: AppSpacing.sm, top: AppSpacing.xs, bottom: AppSpacing.xs })
            .borderRadius(AppRadius.sm)
            .backgroundColor(this.category === c ? AppColors.brand : AppColors.bgSecondary)
            .margin({ right: AppSpacing.xs, bottom: AppSpacing.xs })
            .onClick(() => { this.category = c; })
          }, (c: TicketCategory) => c)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  titleSection() {
    AppCard({ variant: 'outlined', padding: 'md' }) {
      Column({ space: AppSpacing.xs }) {
        Row() {
          Text('标题')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
            .layoutWeight(1)
          Text(`${this.title.length}/${MAX_TITLE}`)
            .fontSize(AppFontSize.xs)
            .fontColor(this.title.length > MAX_TITLE
              ? AppColors.danger : AppColors.textTertiary)
        }
        .width('100%')
        AppInput({
          value: $title,
          placeholder: '一句话描述问题',
          maxLength: MAX_TITLE,
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  descSection() {
    AppCard({ variant: 'outlined', padding: 'md' }) {
      Column({ space: AppSpacing.xs }) {
        Row() {
          Text('详细描述')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
            .layoutWeight(1)
          Text(`${this.description.length}/${MAX_DESC}`)
            .fontSize(AppFontSize.xs)
            .fontColor(this.description.length > MAX_DESC
              ? AppColors.danger : AppColors.textTertiary)
        }
        .width('100%')
        AppTextArea({
          value: $description,
          placeholder: '请尽量复现步骤，并贴上看到的错误提示',
          maxLength: MAX_DESC,
          minRows: 5,
          maxRows: 10,
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  screenshotSection() {
    AppCard({ variant: 'outlined', padding: 'md' }) {
      Column({ space: AppSpacing.sm }) {
        Row() {
          Text(`上传截图（${this.screenshots.length}/${MAX_SHOTS}）`)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
            .layoutWeight(1)
          if (this.screenshots.length < MAX_SHOTS) {
            Text('+ 添加')
              .fontSize(AppFontSize.sm)
              .fontColor(AppColors.brand)
              .onClick(() => this.pickScreenshot())
          }
        }
        .width('100%')
        if (this.screenshots.length > 0) {
          Row({ space: AppSpacing.xs }) {
            ForEach(this.screenshots, (uri: string, idx?: number) => {
              Stack() {
                Column()
                  .width(64).height(64)
                  .backgroundColor(AppColors.bgSecondary)
                  .borderRadius(AppRadius.sm)
                Text('✕')
                  .fontSize(AppFontSize.xs)
                  .fontColor(AppColors.textInverse)
                  .padding(2)
                  .backgroundColor(AppColors.danger)
                  .borderRadius(AppRadius.round)
                  .position({ x: 50, y: 0 })
                  .onClick(() => this.removeScreenshot(idx ?? 0))
              }
            }, (uri: string) => uri)
          }
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  contextSection() {
    AppCard({ variant: 'filled', padding: 'md' }) {
      Column({ space: AppSpacing.xs }) {
        Row() {
          Text('附带设备与最近日志')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textPrimary)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.attachLogs })
            .selectedColor(AppColors.brand)
            .onChange((on: boolean) => { this.attachLogs = on; })
        }
        .width('100%')
        Text(`版本 ${APP_VERSION} · ${deviceInfo.brand ?? ''} ${deviceInfo.productModel ?? ''}`)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textSecondary)
        if (this.fromRoute.length > 0) {
          Text(`触发页面：${this.fromRoute}`)
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
        }
        if (this.attachLogs) {
          Text(`将随反馈一起发送最近 ${RECENT_LOG_LINES} 行日志，便于排查`)
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
        } else {
          Text('日志已关闭，仅发送以上设备信息')
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  submitSection() {
    Column({ space: AppSpacing.sm }) {
      if (this.errMsg.length > 0) {
        Text(this.errMsg)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.danger)
      }
      AppButton({
        label: this.submitting ? '提交中…' : '提交反馈',
        variant: 'primary',
        size: 'lg',
        disabled: this.submitting,
        onClick: () => this.submit(),
      })
      AppButton({
        label: '查看我的工单',
        variant: 'ghost',
        size: 'md',
        onClick: () => RouterService.push(RoutePath.TICKET_LIST),
      })
    }
    .width('100%')
  }
}
