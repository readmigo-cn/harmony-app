/**
 * TicketDetail.ets — W19-C2 工单详情
 *
 * 区块：
 *   1) 顶部状态条（类别图标 + 标题 + 状态徽章）
 *   2) 时间线对话（用户消息靠右，客服 / 系统消息靠左）
 *   3) 底部输入框（追问，仅未关闭时可用）
 *   4) 关闭工单按钮（仅未关闭 + 用户能关闭时显示）
 *   5) 满意度评分弹窗（关闭瞬间自动弹出，1-5 星 + 可选评论）
 */

import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import { RoutePath, TicketDetailRouteParams } from '../../../core/router/RouteConstants';
import { AppButton } from '../../../ui/primitives/Button';
import { AppCard } from '../../../ui/primitives/Card';
import { AppEmptyState } from '../../../ui/primitives/EmptyState';
import { ToastManager } from '../../../ui/primitives/Toast';
import {
  SupportApi,
  Ticket,
  TicketMessage,
  TicketSenderRole,
  ticketCategoryIcon,
  ticketCategoryLabel,
  ticketStatusLabel,
  ticketStatusColor,
} from '../../../api/support/SupportApi';

@Component
export struct TicketDetailPage {
  @State ticketId: string = '';
  @State ticket: Ticket | null = null;
  @State loading: boolean = true;
  @State errMsg: string = '';
  @State sending: boolean = false;
  @State replyText: string = '';
  @State showRating: boolean = false;
  @State pendingRating: number = 0;
  @State ratingComment: string = '';

  private ratingDialog: CustomDialogController | null = null;

  aboutToAppear(): void {
    const p = RouterService.getParams<TicketDetailRouteParams>(RoutePath.TICKET_DETAIL);
    if (!p?.ticketId) {
      this.errMsg = '缺少工单 ID';
      this.loading = false;
      return;
    }
    this.ticketId = p.ticketId;
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errMsg = '';
    try {
      this.ticket = await SupportApi.getTicket(this.ticketId);
    } catch (e) {
      this.errMsg = (e as Error).message ?? '加载失败';
      this.ticket = null;
    } finally {
      this.loading = false;
    }
  }

  private async sendReply(): Promise<void> {
    const content = this.replyText.trim();
    if (content.length === 0) return;
    if (!this.ticket || this.isClosed()) return;
    this.sending = true;
    try {
      const msg = await SupportApi.replyTicket(this.ticket.id, { content });
      // 本地拼到时间线，避免再拉一次
      if (this.ticket) {
        const next: Ticket = {
          id: this.ticket.id,
          userId: this.ticket.userId,
          category: this.ticket.category,
          title: this.ticket.title,
          description: this.ticket.description,
          screenshots: this.ticket.screenshots,
          context: this.ticket.context,
          status: 'open',
          rating: this.ticket.rating,
          messages: [...this.ticket.messages, msg],
          createdAt: this.ticket.createdAt,
          updatedAt: msg.createdAt,
          lastReplyAt: msg.createdAt,
        };
        this.ticket = next;
      }
      this.replyText = '';
      ToastManager.success('已发送');
    } catch (e) {
      ToastManager.error('发送失败：' + ((e as Error).message ?? ''));
    } finally {
      this.sending = false;
    }
  }

  private isClosed(): boolean {
    if (!this.ticket) return true;
    return this.ticket.status === 'closed';
  }

  private canCloseTicket(): boolean {
    if (!this.ticket) return false;
    return this.ticket.status !== 'closed';
  }

  private confirmClose(): void {
    AlertDialog.show({
      title: '关闭工单？',
      message: '关闭后将无法继续追问，可在「全部」中查看历史。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '确认关闭',
        fontColor: AppColors.danger,
        action: () => { this.doClose(); },
      },
    });
  }

  private async doClose(): Promise<void> {
    if (!this.ticket) return;
    try {
      const updated = await SupportApi.closeTicket(this.ticket.id);
      this.ticket = updated;
      ToastManager.success('工单已关闭');
      // 关闭后弹出评分
      this.openRatingDialog();
    } catch (e) {
      ToastManager.error('关闭失败：' + ((e as Error).message ?? ''));
    }
  }

  private openRatingDialog(): void {
    if (!this.ticket || this.ticket.rating !== null) return;
    this.pendingRating = 5;
    this.ratingComment = '';
    this.showRating = true;
  }

  private async submitRating(): Promise<void> {
    if (!this.ticket || this.pendingRating < 1) return;
    try {
      const updated = await SupportApi.rateTicket(this.ticket.id, {
        rating: this.pendingRating,
        comment: this.ratingComment.trim() || undefined,
      });
      this.ticket = updated;
      this.showRating = false;
      ToastManager.success('感谢你的反馈');
    } catch (e) {
      ToastManager.error('评分失败：' + ((e as Error).message ?? ''));
    }
  }

  private formatTime(iso: string): string {
    const d = new Date(iso);
    const yy = d.getFullYear();
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const hh = String(d.getHours()).padStart(2, '0');
    const mi = String(d.getMinutes()).padStart(2, '0');
    return `${yy}-${mm}-${dd} ${hh}:${mi}`;
  }

  // ─── UI ─────────────────────────────────────

  build() {
    NavDestination() {
      Column() {
        if (this.loading) {
          this.loadingView()
        } else if (!this.ticket) {
          this.errorView()
        } else {
          this.statusBar()
          this.timeline()
          this.bottomBar()
        }
        // 评分浮层
        if (this.showRating) {
          this.ratingOverlay()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgPrimary)
    }
    .title(this.ticket?.title ?? '工单详情')
    .onBackPressed(() => { RouterService.back(); return true; })
  }

  @Builder
  loadingView() {
    Column() {
      LoadingProgress().width(40).height(40).color(AppColors.brand)
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  errorView() {
    Column() {
      AppEmptyState({
        variant: 'error',
        title: '工单加载失败',
        description: this.errMsg,
        actionLabel: '重试',
        onAction: () => this.load(),
      })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  statusBar() {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Row({ space: AppSpacing.sm }) {
        Text(ticketCategoryIcon(this.ticket!.category))
          .fontSize(AppFontSize.lg)
        Column({ space: 2 }) {
          Text(this.ticket!.title)
            .fontSize(AppFontSize.md)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${ticketCategoryLabel(this.ticket!.category)} · ${this.formatTime(this.ticket!.createdAt)}`)
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(ticketStatusLabel(this.ticket!.status))
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textInverse)
          .padding({ left: AppSpacing.xs, right: AppSpacing.xs, top: 2, bottom: 2 })
          .borderRadius(AppRadius.sm)
          .backgroundColor(ticketStatusColor(this.ticket!.status))
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.base)
  }

  @Builder
  timeline() {
    Scroll() {
      Column({ space: AppSpacing.sm }) {
        // 用户首条 = description
        this.bubble('user', this.ticket!.description, this.ticket!.createdAt)
        // 后续消息
        ForEach(this.ticket!.messages, (m: TicketMessage) => {
          this.bubble(m.sender, m.content, m.createdAt)
        }, (m: TicketMessage) => m.id)
        if (this.canCloseTicket() && this.ticket!.rating === null) {
          AppButton({
            label: '关闭并评分',
            variant: 'ghost',
            size: 'sm',
            onClick: () => this.confirmClose(),
          })
        }
        if (this.ticket!.rating !== null) {
          Text(`你给本次服务的评分：${this.starText(this.ticket!.rating!)}`)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
            .padding(AppSpacing.sm)
        }
      }
      .width('100%')
      .padding(AppSpacing.base)
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  bubble(sender: TicketSenderRole, content: string, time: string) {
    Row() {
      if (sender === 'user') {
        Blank().layoutWeight(1)
        Column({ space: 2 }) {
          Text(content)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textInverse)
            .padding(AppSpacing.sm)
            .backgroundColor(AppColors.brand)
            .borderRadius(AppRadius.md)
          Text(this.formatTime(time))
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
        }
        .alignItems(HorizontalAlign.End)
        .constraintSize({ maxWidth: '78%' })
      } else {
        Column({ space: 2 }) {
          Text(sender === 'agent' ? '客服' : '系统')
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
          Text(content)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textPrimary)
            .padding(AppSpacing.sm)
            .backgroundColor(AppColors.bgElevated)
            .borderRadius(AppRadius.md)
          Text(this.formatTime(time))
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: '78%' })
        Blank().layoutWeight(1)
      }
    }
    .width('100%')
  }

  @Builder
  bottomBar() {
    if (this.isClosed()) {
      Row() {
        Text('工单已关闭，无法继续追问')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textTertiary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        if (this.ticket!.rating === null) {
          Text('评分')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.brand)
            .onClick(() => this.openRatingDialog())
        }
      }
      .width('100%')
      .padding(AppSpacing.base)
      .backgroundColor(AppColors.bgElevated)
    } else {
      Row({ space: AppSpacing.sm }) {
        TextInput({ text: this.replyText, placeholder: '继续追问…' })
          .layoutWeight(1)
          .height(40)
          .fontSize(AppFontSize.sm)
          .backgroundColor(AppColors.bgSecondary)
          .borderRadius(AppRadius.sm)
          .onChange((v: string) => { this.replyText = v; })
        AppButton({
          label: this.sending ? '发送中' : '发送',
          variant: 'primary',
          size: 'sm',
          disabled: this.sending || this.replyText.trim().length === 0,
          onClick: () => this.sendReply(),
        })
      }
      .width('100%')
      .padding(AppSpacing.base)
      .backgroundColor(AppColors.bgElevated)
    }
  }

  // ─── 评分浮层（自带遮罩） ───
  @Builder
  ratingOverlay() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => { this.showRating = false; })

      // 卡片
      AppCard({ variant: 'elevated', padding: 'md' }) {
        Column({ space: AppSpacing.base }) {
          Text('给本次服务打个分吧')
            .fontSize(AppFontSize.md)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textPrimary)
          Row({ space: AppSpacing.sm }) {
            ForEach([1, 2, 3, 4, 5], (n: number) => {
              Text(n <= this.pendingRating ? '★' : '☆')
                .fontSize(32)
                .fontColor(n <= this.pendingRating ? '#FFB300' : AppColors.textTertiary)
                .onClick(() => { this.pendingRating = n; })
            }, (n: number) => `${n}`)
          }
          TextArea({ text: this.ratingComment, placeholder: '说说你的体验（可选）' })
            .width('100%')
            .height(80)
            .fontSize(AppFontSize.sm)
            .backgroundColor(AppColors.bgSecondary)
            .borderRadius(AppRadius.sm)
            .onChange((v: string) => { this.ratingComment = v; })
          Row({ space: AppSpacing.sm }) {
            AppButton({
              label: '稍后再说',
              variant: 'ghost',
              size: 'md',
              onClick: () => { this.showRating = false; },
            })
            AppButton({
              label: '提交评分',
              variant: 'primary',
              size: 'md',
              disabled: this.pendingRating < 1,
              onClick: () => this.submitRating(),
            })
          }
        }
        .alignItems(HorizontalAlign.Center)
        .width('100%')
      }
      .width('86%')
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  private starText(n: number): string {
    let s = '';
    for (let i = 0; i < n; i++) s += '★';
    return s;
  }
}
