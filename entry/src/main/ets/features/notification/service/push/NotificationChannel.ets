/**
 * NotificationChannel.ets — W18-C5 通知通道（6 类）
 *
 * 6 类通道独立配置 sound / vibration / led / importance，用户可单独开关。
 *
 *   reading-reminder   阅读提醒          低优先级 + 静音 + 不振动
 *   review-reminder    复习提醒          中优先级 + 默认提示音 + 振动
 *   subscription       续费 / 试用到期    高优先级 + 强提示音 + LED 红灯
 *   achievement        成就解锁          低优先级 + 短促铃声 + 不振动
 *   social             好友 / 书评互动    中优先级 + 默认音 + 短振动
 *   system             系统公告          高优先级 + 默认音 + 振动
 *
 * 设计要点：
 *   - 用户开关：写 SettingsStore.notifications + 单独 per-channel pref（pref key:
 *     `notif_channel_<category>`）。顶层关闭 → 所有 channel 一并禁用。
 *   - publish 调用 @ohos.notificationManager.publish；request id 用 hash
 *   - badge / 角标：activity-class 不在本机控制，由 HMS 服务端推
 *   - 与 HmsPushService.onMessage 对接：收到 push → 选择 channel → publish
 *   - 同时把 publish 出去的通知存到 NotificationCenter 本地存档（pref / DB）
 */

import notificationManager from '@ohos.notificationManager';
import { PreferencesManager } from '../../../../core/persistence/PreferencesManager';
import { SettingsStore } from '../../../../store/SettingsStore';
import { HmsPushService, PushMessage } from './HmsPushService';

const TAG = 'NotificationChannel';

/** 6 类通道枚举。与服务端 push payload.category 严格对齐。 */
export type NotificationCategory =
  | 'reading-reminder'
  | 'review-reminder'
  | 'subscription'
  | 'achievement'
  | 'social'
  | 'system';

/** 优先级（importance），与 HarmonyOS notificationManager 等级对齐。 */
export type Importance = 'low' | 'default' | 'high';

/** 通道配置。 */
export interface ChannelConfig {
  category: NotificationCategory;
  /** UI 展示名称（中文） */
  displayName: string;
  /** 用户可见说明，在「通知设置」页展示 */
  description: string;
  importance: Importance;
  /** 是否播放系统提示音 */
  sound: boolean;
  /** 是否振动 */
  vibration: boolean;
  /** 是否亮 LED 灯（HarmonyOS 部分机型支持） */
  led: boolean;
  /** 振动 pattern（ms 数组），仅 vibration=true 生效 */
  vibrationPattern?: number[];
}

/** publish 入参。 */
export interface PublishOptions {
  category: NotificationCategory;
  title: string;
  body: string;
  /** 透传给 deep link / 路由 */
  extra?: Record<string, string>;
  /** 自定义 notificationId（去重 + NotificationCenter 落档 key） */
  notificationId?: string;
}

/** 6 类通道配置（中文 displayName，便于在「通知设置」直接展示）。 */
const CHANNEL_CONFIGS: Record<NotificationCategory, ChannelConfig> = {
  'reading-reminder': {
    category: 'reading-reminder',
    displayName: '阅读提醒',
    description: '每日阅读时间到，温和提示',
    importance: 'low',
    sound: false,
    vibration: false,
    led: false,
  },
  'review-reminder': {
    category: 'review-reminder',
    displayName: '复习提醒',
    description: '生词到了复习时间',
    importance: 'default',
    sound: true,
    vibration: true,
    led: false,
    vibrationPattern: [0, 200],
  },
  subscription: {
    category: 'subscription',
    displayName: '订阅 / 续费',
    description: '试用到期、订阅续费等关键消息',
    importance: 'high',
    sound: true,
    vibration: true,
    led: true,
    vibrationPattern: [0, 300, 100, 300],
  },
  achievement: {
    category: 'achievement',
    displayName: '成就解锁',
    description: '阅读里程碑、连续学习记录',
    importance: 'low',
    sound: true,
    vibration: false,
  },
  social: {
    category: 'social',
    displayName: '好友 / 书评互动',
    description: '点赞、评论、好友请求',
    importance: 'default',
    sound: true,
    vibration: true,
    led: false,
    vibrationPattern: [0, 150],
  },
  system: {
    category: 'system',
    displayName: '系统公告',
    description: '版本更新、维护通知、重要安全提示',
    importance: 'high',
    sound: true,
    vibration: true,
    led: false,
  },
};

const PER_CHANNEL_PREF_PREFIX = 'notif_channel_';
const ARCHIVE_PREF_KEY = 'notif_archive';
const ARCHIVE_LIMIT = 100;
const ARCHIVE_TTL_MS = 5 * 24 * 60 * 60 * 1000; // 5 天

/** NotificationCenter 落档结构。 */
export interface ArchivedNotification {
  id: string;
  category: NotificationCategory;
  title: string;
  body: string;
  extra: Record<string, string>;
  /** 创建时间戳 */
  createdAt: number;
  read: boolean;
  /** 是否被用户长按设为不打扰（hidden 但仍保留记录） */
  muted: boolean;
}

class NotificationChannelImpl {
  private initialized: boolean = false;

  /** EntryAbility.onCreate 调一次。 */
  async init(): Promise<void> {
    if (this.initialized) return;
    this.initialized = true;
    try {
      // 把所有 channel 默认开关回灌 AppStorage（供 UI 同步读）
      const cats = Object.keys(CHANNEL_CONFIGS) as NotificationCategory[];
      for (let i = 0; i < cats.length; i++) {
        const cat = cats[i];
        const enabled = await PreferencesManager.getBoolean(`${PER_CHANNEL_PREF_PREFIX}${cat}`, true);
        AppStorage.SetOrCreate<boolean>(`${PER_CHANNEL_PREF_PREFIX}${cat}`, enabled);
      }

      // GC 过期归档
      await this.gcArchive();

      // 桥接 HmsPushService.onMessage → publish
      HmsPushService.onMessage((msg: PushMessage) => {
        this.handleIncomingPush(msg).catch((e: Error) => {
          console.warn(`${TAG} handleIncomingPush err: ${e.message}`);
        });
      });

      console.info(`${TAG} init done`);
    } catch (e) {
      console.warn(`${TAG} init failed: ${(e as Error).message}`);
    }
  }

  /** 列出 6 类通道（用于「通知设置」页渲染）。 */
  listChannels(): ChannelConfig[] {
    return Object.values(CHANNEL_CONFIGS);
  }

  /** 单独开关某类通道（用户在设置页操作）。 */
  async setChannelEnabled(category: NotificationCategory, enabled: boolean): Promise<void> {
    AppStorage.SetOrCreate<boolean>(`${PER_CHANNEL_PREF_PREFIX}${category}`, enabled);
    await PreferencesManager.setBoolean(`${PER_CHANNEL_PREF_PREFIX}${category}`, enabled);
  }

  isChannelEnabled(category: NotificationCategory): boolean {
    const flag = AppStorage.Get<boolean>(`${PER_CHANNEL_PREF_PREFIX}${category}`);
    return flag !== false; // undefined 默认 true
  }

  /** 主入口：发布一条通知到对应通道。 */
  async publish(opts: PublishOptions): Promise<boolean> {
    if (!this.shouldPublish(opts.category)) {
      console.info(`${TAG} publish skipped (channel disabled): ${opts.category}`);
      return false;
    }
    const cfg = CHANNEL_CONFIGS[opts.category];
    const id = opts.notificationId ?? `${opts.category}-${Date.now()}`;

    try {
      const request = this.buildRequest(id, cfg, opts);
      // TODO(Phase 5): 调用 notificationManager.requestEnableNotification 申请权限
      await notificationManager.publish(request);
      // 同步落档到 NotificationCenter
      await this.archive({
        id,
        category: opts.category,
        title: opts.title,
        body: opts.body,
        extra: opts.extra ?? {},
        createdAt: Date.now(),
        read: false,
        muted: false,
      });
      console.info(`${TAG} published id=${id} category=${opts.category}`);
      return true;
    } catch (e) {
      console.warn(`${TAG} publish failed: ${(e as Error).message}`);
      return false;
    }
  }

  /** 取消单条通知。 */
  async cancel(notificationId: string): Promise<void> {
    try {
      await notificationManager.cancel(this.hashIdToInt(notificationId));
    } catch (e) {
      console.warn(`${TAG} cancel failed: ${(e as Error).message}`);
    }
  }

  /** 取消整个分类下的所有通知。 */
  async cancelByCategory(category: NotificationCategory): Promise<void> {
    try {
      await notificationManager.cancelGroup(category);
    } catch (e) {
      console.warn(`${TAG} cancelByCategory ${category} failed: ${(e as Error).message}`);
    }
  }

  // ---------- archive (NotificationCenter) ----------

  async listArchive(): Promise<ArchivedNotification[]> {
    return await PreferencesManager.getArray<ArchivedNotification>(ARCHIVE_PREF_KEY, []);
  }

  async markRead(id: string): Promise<void> {
    const list = await this.listArchive();
    const next = list.map((n) => (n.id === id ? { ...n, read: true } : n));
    await PreferencesManager.setArray<ArchivedNotification>(ARCHIVE_PREF_KEY, next);
  }

  async markAllRead(): Promise<void> {
    const list = await this.listArchive();
    const next = list.map((n) => ({ ...n, read: true }));
    await PreferencesManager.setArray<ArchivedNotification>(ARCHIVE_PREF_KEY, next);
  }

  async deleteArchived(id: string): Promise<void> {
    const list = await this.listArchive();
    const next = list.filter((n) => n.id !== id);
    await PreferencesManager.setArray<ArchivedNotification>(ARCHIVE_PREF_KEY, next);
  }

  async muteArchived(id: string): Promise<void> {
    const list = await this.listArchive();
    const next = list.map((n) => (n.id === id ? { ...n, muted: true } : n));
    await PreferencesManager.setArray<ArchivedNotification>(ARCHIVE_PREF_KEY, next);
  }

  async clearArchive(): Promise<void> {
    await PreferencesManager.setArray<ArchivedNotification>(ARCHIVE_PREF_KEY, []);
  }

  // ---------- internals ----------

  private shouldPublish(category: NotificationCategory): boolean {
    // 顶层 dailyReminder 开关只控制 reading-reminder
    if (category === 'reading-reminder') {
      const top = SettingsStore.getNotifications();
      if (!top.dailyReminder) return false;
    }
    return this.isChannelEnabled(category);
  }

  private async handleIncomingPush(msg: PushMessage): Promise<void> {
    const category = (msg.category as NotificationCategory) ?? 'system';
    if (!CHANNEL_CONFIGS[category]) {
      console.warn(`${TAG} unknown category from push: ${msg.category}`);
      return;
    }
    await this.publish({
      category,
      title: msg.title ?? '米果智读',
      body: msg.body ?? '',
      extra: msg.data,
      notificationId: msg.messageId,
    });
  }

  private buildRequest(id: string, cfg: ChannelConfig, opts: PublishOptions): notificationManager.NotificationRequest {
    const slotType = this.toSlotType(cfg.importance);
    const request: notificationManager.NotificationRequest = {
      id: this.hashIdToInt(id),
      // group 用 category，便于 cancelGroup 聚类取消
      groupName: cfg.category,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: opts.title,
          text: opts.body,
        },
      },
      // slotType 决定系统通道默认行为；具体 sound/vibration 还要 host app 申明
      slotType,
      extraInfo: {
        category: cfg.category,
        notificationId: id,
        ...(opts.extra ?? {}),
      },
    } as notificationManager.NotificationRequest;
    return request;
  }

  private toSlotType(importance: Importance): notificationManager.SlotType {
    switch (importance) {
      case 'high':
        return notificationManager.SlotType.SERVICE_INFORMATION;
      case 'default':
        return notificationManager.SlotType.SOCIAL_COMMUNICATION;
      case 'low':
      default:
        return notificationManager.SlotType.CONTENT_INFORMATION;
    }
  }

  private hashIdToInt(id: string): number {
    let h = 0;
    for (let i = 0; i < id.length; i++) {
      h = ((h << 5) - h + id.charCodeAt(i)) | 0;
    }
    return Math.abs(h);
  }

  private async archive(item: ArchivedNotification): Promise<void> {
    const list = await this.listArchive();
    // 去重 (相同 id 替换)
    const filtered = list.filter((n) => n.id !== item.id);
    filtered.unshift(item);
    // 容量限制
    const trimmed = filtered.slice(0, ARCHIVE_LIMIT);
    await PreferencesManager.setArray<ArchivedNotification>(ARCHIVE_PREF_KEY, trimmed);
  }

  private async gcArchive(): Promise<void> {
    const now = Date.now();
    const list = await this.listArchive();
    const fresh = list.filter((n) => now - n.createdAt < ARCHIVE_TTL_MS);
    if (fresh.length !== list.length) {
      await PreferencesManager.setArray<ArchivedNotification>(ARCHIVE_PREF_KEY, fresh);
      console.info(`${TAG} gc removed ${list.length - fresh.length} expired notifications`);
    }
  }
}

/** 单例。 */
export const NotificationChannel = new NotificationChannelImpl();
