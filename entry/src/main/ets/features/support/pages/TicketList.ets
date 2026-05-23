/**
 * TicketList.ets — W19-C2 工单列表
 *
 * 三个 Tab：进行中（open + pending） / 已解决（resolved） / 全部
 * 每项展示：类别图标 + 标题 + 状态条 + 最后回复时间
 * 下拉刷新；空状态走 AppEmptyState
 */

import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import { RoutePath, TicketDetailRouteParams } from '../../../core/router/RouteConstants';
import { AppCard } from '../../../ui/primitives/Card';
import { AppButton } from '../../../ui/primitives/Button';
import { AppEmptyState } from '../../../ui/primitives/EmptyState';
import { ToastManager } from '../../../ui/primitives/Toast';
import {
  SupportApi,
  Ticket,
  ListTicketsQuery,
  ticketCategoryIcon,
  ticketCategoryLabel,
  ticketStatusLabel,
  ticketStatusColor,
} from '../../../api/support/SupportApi';

type TabKind = 'open' | 'resolved' | 'all';
const TABS: TabKind[] = ['open', 'resolved', 'all'];
const TAB_LABELS: Record<TabKind, string> = {
  open: '进行中',
  resolved: '已解决',
  all: '全部',
};

@Component
export struct TicketListPage {
  @State currentTab: TabKind = 'open';
  @State tickets: Ticket[] = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State errMsg: string = '';

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errMsg = '';
    try {
      const query: ListTicketsQuery = { filter: this.currentTab, limit: 50 };
      const resp = await SupportApi.listTickets(query);
      this.tickets = resp.items;
    } catch (e) {
      this.errMsg = (e as Error).message ?? '加载失败';
      this.tickets = [];
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private async onRefresh(): Promise<void> {
    if (this.refreshing) return;
    this.refreshing = true;
    await this.load();
    ToastManager.success('已刷新');
  }

  private switchTab(t: TabKind): void {
    if (this.currentTab === t) return;
    this.currentTab = t;
    this.load();
  }

  private openTicket(t: Ticket): void {
    const param: TicketDetailRouteParams = { ticketId: t.id };
    RouterService.push(RoutePath.TICKET_DETAIL, param);
  }

  private formatTime(iso: string | null): string {
    if (!iso) return '';
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
        this.tabBar()
        if (this.loading && !this.refreshing) {
          this.loadingView()
        } else if (this.tickets.length === 0) {
          this.emptyView()
        } else {
          this.listView()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgPrimary)
    }
    .title('我的工单')
    .menus([{
      value: '新反馈',
      action: () => RouterService.push(RoutePath.FEEDBACK),
    }])
    .onBackPressed(() => { RouterService.back(); return true; })
  }

  @Builder
  tabBar() {
    Row() {
      ForEach(TABS, (t: TabKind) => {
        Column({ space: AppSpacing.xs }) {
          Text(TAB_LABELS[t])
            .fontSize(AppFontSize.md)
            .fontWeight(this.currentTab === t ? AppFontWeight.bold : AppFontWeight.regular)
            .fontColor(this.currentTab === t ? AppColors.brand : AppColors.textSecondary)
          // 下划线指示器
          Column()
            .width(24)
            .height(2)
            .backgroundColor(this.currentTab === t ? AppColors.brand : 'transparent')
            .borderRadius(1)
        }
        .layoutWeight(1)
        .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm })
        .alignItems(HorizontalAlign.Center)
        .onClick(() => this.switchTab(t))
      }, (t: TabKind) => t)
    }
    .width('100%')
    .backgroundColor(AppColors.bgElevated)
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
  emptyView() {
    Column() {
      AppEmptyState({
        variant: this.errMsg.length > 0 ? 'error' : 'no-data',
        title: this.errMsg.length > 0 ? '加载失败' : '暂无工单',
        description: this.errMsg.length > 0 ? this.errMsg : '在「反馈与帮助」中提交问题，我们会尽快处理',
        actionLabel: this.errMsg.length > 0 ? '重试' : '去反馈',
        onAction: () => {
          if (this.errMsg.length > 0) this.load();
          else RouterService.push(RoutePath.FEEDBACK);
        },
      })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  listView() {
    Refresh({ refreshing: $$this.refreshing }) {
      List({ space: AppSpacing.sm }) {
        ForEach(this.tickets, (t: Ticket) => {
          ListItem() {
            this.ticketRow(t)
          }
        }, (t: Ticket) => t.id)
      }
      .width('100%')
      .padding(AppSpacing.base)
    }
    .layoutWeight(1)
    .width('100%')
    .onRefreshing(() => this.onRefresh())
  }

  @Builder
  ticketRow(t: Ticket) {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Column({ space: AppSpacing.xs }) {
        Row({ space: AppSpacing.sm }) {
          Text(ticketCategoryIcon(t.category))
            .fontSize(AppFontSize.lg)
          Column({ space: 2 }) {
            Text(t.title)
              .fontSize(AppFontSize.md)
              .fontWeight(AppFontWeight.bold)
              .fontColor(AppColors.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(ticketCategoryLabel(t.category))
              .fontSize(AppFontSize.xs)
              .fontColor(AppColors.textTertiary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          // 状态徽章
          Text(ticketStatusLabel(t.status))
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textInverse)
            .padding({ left: AppSpacing.xs, right: AppSpacing.xs, top: 2, bottom: 2 })
            .borderRadius(AppRadius.sm)
            .backgroundColor(ticketStatusColor(t.status))
        }
        .width('100%')

        if (t.description.length > 0) {
          Text(t.description)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(20)
            .width('100%')
        }

        Row() {
          Text(`${t.messages.length} 条对话`)
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
            .layoutWeight(1)
          Text(this.formatTime(t.lastReplyAt ?? t.updatedAt))
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .onClick(() => this.openTicket(t))
  }
}
