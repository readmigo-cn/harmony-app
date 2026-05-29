/**
 * HmsPushService.ets — W6 HMS Push Kit 适配层（真实 SDK + mock 降级）
 *
 * 责任：
 *   1) init()           启动期初始化 push SDK，订阅默认 topic
 *   2) getToken()       拿到本机 device push token（HMS 侧异步生成，需缓存）
 *   3) reportToken()    上报到后端，绑定 userId（用于精准下发）
 *   4) subscribeTopic / unsubscribeTopic  按业务主题分组（new-book, system 等）
 *   5) onMessage()      接收前台推送，回调给 NotificationChannel 渲染
 *
 * SDK 策略：
 *   - 优先 import @kit.PushKit（HarmonyOS NEXT Stage Mode）
 *   - 若 SDK 缺失，降级到 mock（token = mock-hms-token-<ts>）
 *   - manifest 需声明 ohos.permission.NOTIFICATION_CONTROLLER
 *   - AGC Console 需配置 Push Service id + secret
 */

import { PreferencesManager } from '../../../../core/persistence/PreferencesManager';
import { ApiConfig } from '../../../../api/client/ApiConfig';

// Try real HMS Push Kit (HarmonyOS NEXT @kit.PushKit)
let PushKit: {
  init: () => Promise<void>;
  getToken: (params?: object) => Promise<string>;
  subscribe: (topic: string) => Promise<void>;
  unsubscribe: (topic: string) => Promise<void>;
  on: (event: string, cb: (msg: object) => void) => void;
} | null = null;

try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  PushKit = require('@kit.PushKit') as typeof PushKit;
} catch (_e1) {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    PushKit = require('@hms.push') as typeof PushKit;
  } catch (_e2) {
    console.warn('HmsPushService @kit.PushKit/@hms.push not available, using mock');
  }
}

const TAG = 'HmsPushService';

const KEY_TOKEN = 'push_token';
const KEY_TOKEN_REPORTED_USER = 'push_token_reported_user';
const REPORT_TIMEOUT_MS = 8000;

/** push 收到的消息结构（与 HMS Message 字段对齐）。 */
export interface PushMessage {
  /** 业务方下发的 messageId，用于去重 */
  messageId: string;
  /** 通知类型：与 NotificationChannel.NotificationCategory 对齐 */
  category: string;
  /** 标题（可选，纯透传消息可缺省） */
  title?: string;
  /** 正文 */
  body?: string;
  /** 自定义透传字段（业务路由 / deep link 用） */
  data: Record<string, string>;
  /** 服务端时间戳（ms） */
  timestamp: number;
}

export type PushMessageCallback = (msg: PushMessage) => void;

class HmsPushServiceImpl {
  private initialized: boolean = false;
  private cachedToken: string = '';
  private listeners: Set<PushMessageCallback> = new Set<PushMessageCallback>();
  /** 已订阅 topic 集合（避免重复 subscribe）。 */
  private subscribedTopics: Set<string> = new Set<string>();
  /** Mock 模式下的虚假 token，便于本地调试。 */
  private static readonly MOCK_TOKEN_PREFIX = 'mock-hms-token-';

  /** EntryAbility.onCreate 调一次。 */
  async init(): Promise<void> {
    if (this.initialized) return;
    this.initialized = true;
    try {
      // 还原缓存 token
      const cached = await PreferencesManager.getString(KEY_TOKEN, '');
      if (cached.length > 0) {
        this.cachedToken = cached;
      }

      if (PushKit) {
        await PushKit.init();
        PushKit.on('messageReceived', (raw: object) => {
          const msg = this.toPushMessage(raw);
          if (msg) this.dispatch(msg);
        });
        const token = await PushKit.getToken({ scope: 'HCM' });
        await this.persistToken(token);
      } else {
        this.startMockTokenIfNeeded();
      }

      // 默认订阅系统公告 topic（所有用户都收）
      await this.subscribeTopic('system-broadcast');
      console.info(`${TAG} init done, token=${this.cachedToken.slice(0, 24)}...`);
    } catch (e) {
      console.warn(`${TAG} init failed: ${(e as Error).message}`);
    }
  }

  /** 获取设备 push token；首次调用可能等待 SDK 异步生成。 */
  async getToken(): Promise<string> {
    if (this.cachedToken.length > 0) return this.cachedToken;
    if (PushKit) {
      try {
        const token = await PushKit.getToken({ scope: 'HCM' });
        await this.persistToken(token);
      } catch (e) {
        console.warn(`${TAG} getToken real failed: ${(e as Error).message}`);
        this.startMockTokenIfNeeded();
      }
    } else {
      this.startMockTokenIfNeeded();
    }
    return this.cachedToken;
  }

  /**
   * 上报 token 到后端绑定 userId。
   * 同一 user + 同一 token 不重复上报；token 变化或换账号必须重报。
   */
  async reportToken(userId: string): Promise<boolean> {
    if (!userId) return false;
    const token = await this.getToken();
    if (!token) return false;

    const lastReported = await PreferencesManager.getString(KEY_TOKEN_REPORTED_USER, '');
    const fingerprint = `${userId}:${token}`;
    if (lastReported === fingerprint) {
      console.info(`${TAG} reportToken skipped (already reported)`);
      return true;
    }

    try {
      // Use fetch directly to avoid circular dependency: HttpClient -> UserStore -> HmsPushService
      const url = `${ApiConfig.baseUrl}/push/devices`;
      const ok = await this.postReport(url, { userId, token, platform: 'harmony' });
      if (ok) {
        await PreferencesManager.setString(KEY_TOKEN_REPORTED_USER, fingerprint);
      }
      return ok;
    } catch (e) {
      console.warn(`${TAG} reportToken failed: ${(e as Error).message}`);
      return false;
    }
  }

  /** 订阅业务 topic（如 new-book / promo / system-broadcast）。 */
  async subscribeTopic(topic: string): Promise<void> {
    if (this.subscribedTopics.has(topic)) return;
    try {
      if (PushKit) {
        await PushKit.subscribe(topic);
      }
      this.subscribedTopics.add(topic);
      console.info(`${TAG} subscribed topic=${topic}`);
    } catch (e) {
      console.warn(`${TAG} subscribe ${topic} failed: ${(e as Error).message}`);
    }
  }

  async unsubscribeTopic(topic: string): Promise<void> {
    if (!this.subscribedTopics.has(topic)) return;
    try {
      if (PushKit) {
        await PushKit.unsubscribe(topic);
      }
      this.subscribedTopics.delete(topic);
      console.info(`${TAG} unsubscribed topic=${topic}`);
    } catch (e) {
      console.warn(`${TAG} unsubscribe ${topic} failed: ${(e as Error).message}`);
    }
  }

  /** 注册 push 消息回调；返回 unsubscribe 函数。 */
  onMessage(cb: PushMessageCallback): () => void {
    this.listeners.add(cb);
    return () => this.listeners.delete(cb);
  }

  /** 当前已订阅 topic（debug 用）。 */
  getSubscribedTopics(): string[] {
    return Array.from(this.subscribedTopics);
  }

  /** Phase 3 调试用：手动触发一条假消息走完整通道链路。 */
  async simulateIncoming(msg: PushMessage): Promise<void> {
    this.dispatch(msg);
  }

  // ---------- internals ----------

  private dispatch(msg: PushMessage): void {
    this.listeners.forEach((cb) => {
      try {
        cb(msg);
      } catch (e) {
        console.warn(`${TAG} listener threw: ${(e as Error).message}`);
      }
    });
  }

  private async persistToken(token: string): Promise<void> {
    this.cachedToken = token;
    await PreferencesManager.setString(KEY_TOKEN, token);
  }

  private startMockTokenIfNeeded(): void {
    if (this.cachedToken.length > 0) return;
    const token = `${HmsPushServiceImpl.MOCK_TOKEN_PREFIX}${Date.now().toString(36)}`;
    this.cachedToken = token;
    PreferencesManager.setString(KEY_TOKEN, token).catch(() => {});
  }

  /** Normalize raw HMS push message object to PushMessage. */
  private toPushMessage(raw: object): PushMessage | null {
    try {
      const r = raw as Record<string, unknown>;
      return {
        messageId: (r['messageId'] as string) ?? `auto-${Date.now()}`,
        category: (r['category'] as string) ?? 'system',
        title: r['title'] as string | undefined,
        body: r['body'] as string | undefined,
        data: (r['data'] as Record<string, string>) ?? {},
        timestamp: (r['timestamp'] as number) ?? Date.now(),
      };
    } catch (_) {
      return null;
    }
  }

  /** POST push token to backend. Uses native fetch to avoid HttpClient circular dep. */
  private async postReport(url: string, payload: object): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      const timer = setTimeout(() => resolve(false), REPORT_TIMEOUT_MS);
      try {
        fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        })
          .then((res) => {
            clearTimeout(timer);
            resolve(res.ok);
          })
          .catch((e: Error) => {
            clearTimeout(timer);
            console.warn(`${TAG} postReport fetch error: ${e.message}`);
            resolve(false);
          });
      } catch (e) {
        clearTimeout(timer);
        console.warn(`${TAG} postReport error: ${(e as Error).message}`);
        resolve(false);
      }
    });
  }
}

/** 单例。 */
export const HmsPushService = new HmsPushServiceImpl();
