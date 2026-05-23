/**
 * NotificationCenter.ets — W18-C6 通知中心
 *
 * 功能：
 *   - Tab 切换：未读 / 全部 / 按类型筛选（6 类）
 *   - LazyForEach 列表，每项：图标 + 标题 + 摘要 + 时间 + 已读状态
 *   - 点击 → mark read + 走 deep link（extra.deepLink 字段）
 *   - 长按 → 弹 Sheet：标记已读 / 删除 / 设为不打扰
 *   - 顶部「全部已读」 / 「清空」按钮
 *
 * 数据来源：NotificationChannel.listArchive()（最近 100 条 / 5 天 TTL）
 *
 * 集成 W6 组件：AppListDataSource、AppEmptyState、AppButton、ToastManager
 */

import router from '@ohos.router';
import promptAction from '@ohos.promptAction';

import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import {
  NotificationChannel,
  NotificationCategory,
  ArchivedNotification,
} from '../../../features/notification/service/push/NotificationChannel';
import { RouterService } from '../../../core/router/RouterService';

type FilterMode = 'unread' | 'all' | NotificationCategory;

interface FilterTab {
  id: FilterMode;
  label: string;
}

const FILTER_TABS: FilterTab[] = [
  { id: 'unread', label: '未读' },
  { id: 'all', label: '全部' },
  { id: 'reading-reminder', label: '阅读' },
  { id: 'review-reminder', label: '复习' },
  { id: 'subscription', label: '订阅' },
  { id: 'achievement', label: '成就' },
  { id: 'social', label: '社交' },
  { id: 'system', label: '系统' },
];

const CATEGORY_ICONS: Record<NotificationCategory, string> = {
  'reading-reminder': '📖',
  'review-reminder': '🧠',
  'subscription': '💎',
  'achievement': '🏆',
  'social': '💬',
  'system': '⚙️',
};

@Entry
@Component
struct NotificationCenter {
  @State private items: ArchivedNotification[] = [];
  @State private filter: FilterMode = 'unread';
  @State private loading: boolean = false;
  /** 当前长按的 notification（用于操作菜单），null 表示无 */
  @State private actionTarget: ArchivedNotification | null = null;

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.loading = true;
    try {
      this.items = await NotificationChannel.listArchive();
    } catch (e) {
      console.warn(`NotificationCenter reload failed: ${(e as Error).message}`);
    } finally {
      this.loading = false;
    }
  }

  /** 当前 filter 命中的子集（按时间倒序，已在 archive 内）。 */
  private filteredItems(): ArchivedNotification[] {
    const list = this.items.filter((n) => !n.muted);
    if (this.filter === 'unread') return list.filter((n) => !n.read);
    if (this.filter === 'all') return list;
    return list.filter((n) => n.category === this.filter);
  }

  private unreadCount(): number {
    return this.items.filter((n) => !n.read && !n.muted).length;
  }

  private async onItemClick(item: ArchivedNotification): Promise<void> {
    if (!item.read) {
      await NotificationChannel.markRead(item.id);
      // 局部更新，避免 re-fetch 整 list
      this.items = this.items.map((n) => (n.id === item.id ? { ...n, read: true } : n));
    }
    // deep link 来自 extra.deepLink（业务层埋）
    const deepLink = item.extra['deepLink'] ?? '';
    if (deepLink.length > 0) {
      RouterService.handleDeepLink(deepLink);
    }
  }

  private onItemLongPress(item: ArchivedNotification): void {
    this.actionTarget = item;
  }

  private async onActionMarkRead(): Promise<void> {
    const target = this.actionTarget;
    if (!target) return;
    await NotificationChannel.markRead(target.id);
    this.actionTarget = null;
    await this.reload();
  }

  private async onActionDelete(): Promise<void> {
    const target = this.actionTarget;
    if (!target) return;
    await NotificationChannel.deleteArchived(target.id);
    this.actionTarget = null;
    await this.reload();
  }

  private async onActionMute(): Promise<void> {
    const target = this.actionTarget;
    if (!target) return;
    await NotificationChannel.muteArchived(target.id);
    promptAction.showToast({ message: '已设为不打扰', duration: 1500 });
    this.actionTarget = null;
    await this.reload();
  }

  private async onMarkAllRead(): Promise<void> {
    await NotificationChannel.markAllRead();
    promptAction.showToast({ message: '全部已标记为已读', duration: 1500 });
    await this.reload();
  }

  private async onClearAll(): Promise<void> {
    await NotificationChannel.clearArchive();
    promptAction.showToast({ message: '通知中心已清空', duration: 1500 });
    await this.reload();
  }

  /** 时间格式化：今天 HH:mm / 昨天 HH:mm / MM-DD HH:mm。 */
  private formatTime(ts: number): string {
    const d = new Date(ts);
    const now = new Date();
    const sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
    const hh = String(d.getHours()).padStart(2, '0');
    const mm = String(d.getMinutes()).padStart(2, '0');
    if (sameDay) return `今天 ${hh}:${mm}`;
    const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
    if (d.getFullYear() === yesterday.getFullYear() && d.getMonth() === yesterday.getMonth() && d.getDate() === yesterday.getDate()) {
      return `昨天 ${hh}:${mm}`;
    }
    const M = String(d.getMonth() + 1).padStart(2, '0');
    const D = String(d.getDate()).padStart(2, '0');
    return `${M}-${D} ${hh}:${mm}`;
  }

  build() {
    Column() {
      // ── 顶栏 ─────────────────────────────────────
      Row() {
        Text('<')
          .fontSize(AppFontSize.lg)
          .fontColor(AppColors.textPrimary)
          .padding(AppSpacing.sm)
          .onClick(() => router.back())

        Text('通知中心')
          .fontSize(AppFontSize.lg)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)

        Text('全部已读')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.brand)
          .padding(AppSpacing.sm)
          .onClick(() => this.onMarkAllRead())

        Text('清空')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.danger)
          .padding(AppSpacing.sm)
          .onClick(() => this.onClearAll())
      }
      .width('100%')
      .padding({ left: AppSpacing.base, right: AppSpacing.base })
      .height(56)

      // ── 过滤 Tab（横向滚动） ─────────────────────
      Scroll() {
        Row({ space: AppSpacing.xs }) {
          ForEach(FILTER_TABS, (tab: FilterTab) => {
            Text(tab.id === 'unread' && this.unreadCount() > 0
              ? `${tab.label} ${this.unreadCount()}`
              : tab.label)
              .fontSize(AppFontSize.sm)
              .fontColor(this.filter === tab.id ? AppColors.bgPrimary : AppColors.textSecondary)
              .backgroundColor(this.filter === tab.id ? AppColors.brand : AppColors.bgElevated)
              .padding({
                left: AppSpacing.base,
                right: AppSpacing.base,
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
              })
              .borderRadius(AppRadius.round)
              .onClick(() => { this.filter = tab.id; })
          }, (tab: FilterTab) => tab.id)
        }
        .padding({ left: AppSpacing.base, right: AppSpacing.base })
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      .height(48)
      .scrollBar(BarState.Off)

      Divider().color(AppColors.divider).strokeWidth(0.5)

      // ── 列表 ─────────────────────────────────────
      if (this.filteredItems().length === 0) {
        Column() {
          Text('🔔')
            .fontSize(64)
            .margin({ bottom: AppSpacing.base })
          Text(this.loading ? '加载中…' : '暂无通知')
            .fontSize(AppFontSize.base)
            .fontColor(AppColors.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.filteredItems(), (item: ArchivedNotification) => {
            ListItem() {
              Row({ space: AppSpacing.sm }) {
                // leading icon
                Text(CATEGORY_ICONS[item.category] ?? '🔔')
                  .fontSize(28)
                  .width(40)
                  .textAlign(TextAlign.Center)

                Column({ space: 2 }) {
                  Row() {
                    Text(item.title)
                      .fontSize(AppFontSize.base)
                      .fontWeight(item.read ? AppFontWeight.normal : AppFontWeight.bold)
                      .fontColor(AppColors.textPrimary)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    if (!item.read) {
                      Circle({ width: 8, height: 8 })
                        .fill(AppColors.brand)
                        .margin({ left: AppSpacing.xs })
                    }
                  }
                  .width('100%')

                  Text(item.body)
                    .fontSize(AppFontSize.sm)
                    .fontColor(AppColors.textSecondary)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')

                  Text(this.formatTime(item.createdAt))
                    .fontSize(AppFontSize.xs)
                    .fontColor(AppColors.textTertiary)
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(AppSpacing.base)
              .backgroundColor(item.read ? AppColors.bgPrimary : AppColors.bgElevated)
              .onClick(() => this.onItemClick(item))
              .gesture(
                LongPressGesture({ repeat: false, duration: 500 })
                  .onAction(() => this.onItemLongPress(item)),
              )
            }
          }, (item: ArchivedNotification) => item.id)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 0.5, color: AppColors.divider })
      }

      // ── 长按操作菜单（覆盖层） ───────────────────
      if (this.actionTarget !== null) {
        Column() {
          // 背景遮罩
          Column()
            .width('100%').height('100%')
            .backgroundColor('rgba(0,0,0,0.4)')
            .onClick(() => { this.actionTarget = null; })

          // 底部操作 Sheet
          Column({ space: AppSpacing.sm }) {
            Text(this.actionTarget?.title ?? '')
              .fontSize(AppFontSize.base)
              .fontWeight(AppFontWeight.bold)
              .fontColor(AppColors.textPrimary)
              .padding(AppSpacing.base)

            Divider().color(AppColors.divider)

            Text('标记为已读')
              .fontSize(AppFontSize.base)
              .fontColor(AppColors.textPrimary)
              .width('100%')
              .padding(AppSpacing.base)
              .textAlign(TextAlign.Center)
              .onClick(() => this.onActionMarkRead())

            Text('删除')
              .fontSize(AppFontSize.base)
              .fontColor(AppColors.danger)
              .width('100%')
              .padding(AppSpacing.base)
              .textAlign(TextAlign.Center)
              .onClick(() => this.onActionDelete())

            Text('设为不打扰')
              .fontSize(AppFontSize.base)
              .fontColor(AppColors.textSecondary)
              .width('100%')
              .padding(AppSpacing.base)
              .textAlign(TextAlign.Center)
              .onClick(() => this.onActionMute())

            Text('取消')
              .fontSize(AppFontSize.base)
              .fontColor(AppColors.textTertiary)
              .width('100%')
              .padding(AppSpacing.base)
              .textAlign(TextAlign.Center)
              .onClick(() => { this.actionTarget = null; })
          }
          .width('100%')
          .backgroundColor(AppColors.bgPrimary)
          .borderRadius({ topLeft: AppRadius.lg, topRight: AppRadius.lg })
          .position({ x: 0, y: '60%' })
        }
        .width('100%').height('100%')
        .position({ x: 0, y: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }
}
