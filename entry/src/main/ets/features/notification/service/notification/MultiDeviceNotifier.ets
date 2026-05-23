/**
 * MultiDeviceNotifier.ets — W13-C4 多端通知协调器
 *
 * 问题：用户同时持有手机 + 平板，同一条阅读提醒会两端各响一次。
 *
 * 思路：
 *   1) 每条通知带唯一 notificationId，由「最早进入前台」的设备主动 publish + broadcast
 *   2) 其余设备接到 broadcast 后，如果发现自己最近 30s 内有用户活动，则同样 publish；
 *      否则忽略（让最活跃设备承担展示责任）
 *   3) 30s 是经验阈值：太短跨端漂移误判活跃；太长用户已切设备又收不到
 *
 * 通信通道：
 *   @ohos.commonEventManager 自定义事件 'cn.readmigo.notification.broadcast'
 *   data：{ notificationId, type, payload, sourceDeviceId, timestamp }
 *
 * 实际发通知：
 *   @ohos.notificationManager.publish(notificationRequest)
 *
 * 通知类型（与 NotificationTemplates 对齐）：
 *   reading-reminder / review / subscription-renew / trial-expiring /
 *   handoff-available / new-book
 *
 * 用户开关：
 *   每类通知单独开关；读 SettingsStore.notifications 顶层开关 + per-type 标记
 *   per-type 标记走 PreferencesManager['notif_enabled_<type>']，默认 true
 */

import notificationManager from '@ohos.notificationManager';
import commonEventManager from '@ohos.commonEventManager';
import { PreferencesManager } from '../../../../core/persistence/PreferencesManager';
import { SettingsStore } from '../../../../store/SettingsStore';
import { NotificationTemplates, NotificationContent } from './NotificationTemplates';

const TAG = 'MultiDeviceNotifier';

/** 通知类型枚举。 */
export type NotificationType =
  | 'reading-reminder'
  | 'review'
  | 'subscription-renew'
  | 'trial-expiring'
  | 'handoff-available'
  | 'new-book';

/** schedule payload。 */
export interface SchedulePayload {
  /** 模板渲染需要的变量 */
  vars?: Record<string, string | number>;
  /** 业务数据透传，点击通知后路由要用 */
  data?: Record<string, string | number | boolean>;
  /** 自定义 notificationId（同 type 同 id 视为同一条，跨端去重的依据）。
      不传则用 type+timestamp 生成。 */
  notificationId?: string;
}

const BROADCAST_EVENT = 'cn.readmigo.notification.broadcast';
const ACTIVE_WINDOW_MS = 30_000; // 30s 活跃窗口
const PER_TYPE_PREF_PREFIX = 'notif_enabled_';
const SHOWN_IDS_PREF_KEY = 'notif_shown_ids';
/** 跨端 publish 短期记忆的 max 长度，避免无限增长。 */
const SHOWN_IDS_LIMIT = 64;

class MultiDeviceNotifierImpl {
  private initialized: boolean = false;
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;
  /** 本机最近一次进入前台的时间戳，用于活跃判定。 */
  private lastActiveAt: number = 0;
  /** 已展示过的 notificationId 集合（去重）。 */
  private shownIds: Set<string> = new Set<string>();

  /** EntryAbility.onCreate 调一次。 */
  async init(): Promise<void> {
    if (this.initialized) return;
    this.initialized = true;
    this.lastActiveAt = Date.now();

    // 还原已展示 id（避免重启后重复弹）
    const cached = await PreferencesManager.getArray<string>(SHOWN_IDS_PREF_KEY, []);
    cached.forEach((id) => this.shownIds.add(id));

    // 订阅跨端广播
    try {
      const info: commonEventManager.CommonEventSubscribeInfo = { events: [BROADCAST_EVENT] };
      this.subscriber = await commonEventManager.createSubscriber(info);
      commonEventManager.subscribe(this.subscriber, (err, data) => {
        if (err) {
          console.warn(`${TAG} subscribe callback error: ${err.message}`);
          return;
        }
        this.onBroadcast(data).catch((e: Error) => {
          console.warn(`${TAG} onBroadcast error: ${e.message}`);
        });
      });
      console.info(`${TAG} commonEvent subscriber bound`);
    } catch (e) {
      console.warn(`${TAG} subscribe failed: ${(e as Error).message}`);
    }
  }

  /** Ability.onForeground 调一次，刷新活跃窗口起点。 */
  markActive(): void {
    this.lastActiveAt = Date.now();
  }

  /**
   * 注册某类通知：本机决定要不要 publish + 广播。
   *
   * 跨端去重逻辑：
   *   1) 检查 shownIds，如果已有同 id 直接返回
   *   2) 当前活跃 → publish 本机 + 广播给其它设备让其忽略
   *   3) 当前不活跃 → 不 publish，等接收端广播；若 ACTIVE_WINDOW 内没收到广播
   *      则降级为本机 publish（兜底，避免漏通知）
   */
  async schedule(type: NotificationType, payload: SchedulePayload = {}): Promise<void> {
    if (!this.isTypeEnabled(type)) {
      console.info(`${TAG} schedule skipped (type disabled): ${type}`);
      return;
    }
    const id = payload.notificationId ?? `${type}-${Date.now()}`;
    if (this.shownIds.has(id)) {
      console.info(`${TAG} schedule skipped (already shown): ${id}`);
      return;
    }

    const content = this.renderContent(type, payload.vars ?? {});
    const isActive = this.isActiveNow();

    // 广播给其它设备：data 携带 id + payload
    this.broadcast({
      notificationId: id,
      type,
      content,
      data: payload.data ?? {},
      sourceActive: isActive,
      timestamp: Date.now(),
    }).catch((e: Error) => console.warn(`${TAG} broadcast failed: ${e.message}`));

    if (isActive) {
      // 活跃设备 → 立即展示
      await this.publishLocal(id, type, content, payload.data);
    } else {
      // 非活跃 → 给 ACTIVE_WINDOW 让别的设备先 publish；若期间未收到广播标记则兜底自己 publish
      setTimeout(() => {
        if (!this.shownIds.has(id)) {
          this.publishLocal(id, type, content, payload.data).catch(() => {});
        }
      }, ACTIVE_WINDOW_MS);
    }
  }

  /** 撤销某类（或全部）通知。 */
  async cancelAll(type?: NotificationType): Promise<void> {
    try {
      if (type) {
        // 实际系统 API：notificationManager.cancelByGroup / cancel(byId)
        // 占位：清空对应 type 在 shownIds 中的记录，让后续相同 id 重新展示
        const filtered = Array.from(this.shownIds).filter((x) => !x.startsWith(`${type}-`));
        this.shownIds = new Set<string>(filtered);
      } else {
        await notificationManager.cancelAll();
        this.shownIds.clear();
      }
      await this.persistShownIds();
    } catch (e) {
      console.warn(`${TAG} cancelAll failed: ${(e as Error).message}`);
    }
  }

  // ---------- internals ----------

  private isActiveNow(): boolean {
    return Date.now() - this.lastActiveAt < ACTIVE_WINDOW_MS;
  }

  /** 检查用户开关。顶层 dailyReminder 关闭时 reading-reminder 一并禁用。 */
  private isTypeEnabled(type: NotificationType): boolean {
    if (type === 'reading-reminder') {
      const top = SettingsStore.getNotifications();
      if (!top.dailyReminder) return false;
    }
    // per-type pref 默认 true；这里同步读 AppStorage 占位（preferences 是 async）
    const flag = AppStorage.Get<boolean>(`${PER_TYPE_PREF_PREFIX}${type}`);
    if (flag === false) return false;
    return true;
  }

  private renderContent(type: NotificationType, vars: Record<string, string | number>): NotificationContent {
    switch (type) {
      case 'reading-reminder':
        return NotificationTemplates.pickReadingReminder(NotificationTemplates.inferSlot(), vars);
      case 'review':
        return NotificationTemplates.pickReviewReminder(vars);
      case 'subscription-renew':
        return NotificationTemplates.subscriptionRenew();
      case 'trial-expiring':
        return NotificationTemplates.trialExpiring(Number(vars.days ?? 0));
      case 'handoff-available':
        return NotificationTemplates.handoffAvailable(
          String(vars.device ?? '其它设备'),
          String(vars.book ?? ''),
          Number(vars.page ?? 0),
        );
      case 'new-book':
        return NotificationTemplates.newBookReleased(
          String(vars.book ?? ''),
          String(vars.author ?? ''),
        );
      default:
        return { title: '米果智读', body: '' };
    }
  }

  private async publishLocal(
    id: string,
    type: NotificationType,
    content: NotificationContent,
    extra?: Record<string, string | number | boolean>,
  ): Promise<void> {
    if (this.shownIds.has(id)) return;
    try {
      const request: notificationManager.NotificationRequest = {
        id: this.hashIdToInt(id),
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: content.title,
            text: content.body,
          },
        },
        // wantAgent 接入业务路由：占位，由 caller 接入 wantAgent.getWantAgent
        // wantAgent: undefined,
        extraInfo: { type, notificationId: id, ...(extra ?? {}) },
      } as notificationManager.NotificationRequest;
      await notificationManager.publish(request);
      this.shownIds.add(id);
      await this.persistShownIds();
      console.info(`${TAG} published local id=${id} type=${type}`);
    } catch (e) {
      console.warn(`${TAG} publish failed: ${(e as Error).message}`);
    }
  }

  private async broadcast(data: {
    notificationId: string;
    type: NotificationType;
    content: NotificationContent;
    data: Record<string, string | number | boolean>;
    sourceActive: boolean;
    timestamp: number;
  }): Promise<void> {
    const event: commonEventManager.CommonEventPublishData = {
      data: JSON.stringify(data),
    };
    await commonEventManager.publish(BROADCAST_EVENT, event);
  }

  private async onBroadcast(raw: commonEventManager.CommonEventData): Promise<void> {
    if (!raw || !raw.data) return;
    let parsed: {
      notificationId: string;
      type: NotificationType;
      content: NotificationContent;
      data?: Record<string, string | number | boolean>;
      sourceActive: boolean;
    };
    try {
      parsed = JSON.parse(raw.data);
    } catch (_e) {
      return;
    }

    if (this.shownIds.has(parsed.notificationId)) {
      // 已经展示过；只是同步 shownIds（顺便阻断兜底 timer）
      return;
    }

    if (parsed.sourceActive && this.isActiveNow()) {
      // 双方都活跃 → 「最先广播」者已经展示，本机也展示一份保证可见性？
      // 设计选择：只让最早活跃的发，避免双端响铃；本机记录 shownIds 阻断兜底
      this.shownIds.add(parsed.notificationId);
      await this.persistShownIds();
      console.info(`${TAG} skip broadcast (peer active, both): ${parsed.notificationId}`);
      return;
    }

    if (!this.isActiveNow()) {
      // 本机不活跃 → 不展示，记录 id 阻断兜底 publish
      this.shownIds.add(parsed.notificationId);
      await this.persistShownIds();
      return;
    }

    // 对端不活跃 + 本机活跃 → 本机接管展示
    await this.publishLocal(parsed.notificationId, parsed.type, parsed.content, parsed.data);
  }

  private hashIdToInt(id: string): number {
    // notificationManager.NotificationRequest.id 要求 number
    let h = 0;
    for (let i = 0; i < id.length; i++) {
      h = ((h << 5) - h + id.charCodeAt(i)) | 0;
    }
    return Math.abs(h);
  }

  private async persistShownIds(): Promise<void> {
    const ids = Array.from(this.shownIds).slice(-SHOWN_IDS_LIMIT);
    this.shownIds = new Set<string>(ids);
    await PreferencesManager.setArray<string>(SHOWN_IDS_PREF_KEY, ids);
  }
}

/** 单例 */
export const MultiDeviceNotifier = new MultiDeviceNotifierImpl();
