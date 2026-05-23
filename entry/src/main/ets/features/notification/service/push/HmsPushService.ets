/**
 * HmsPushService.ets — W18-C4 HMS Push Kit 适配层
 *
 * 责任：
 *   1) init()           启动期初始化 push SDK，订阅默认 topic
 *   2) getToken()       拿到本机 device push token（HMS 侧异步生成，需缓存）
 *   3) reportToken()    上报到后端，绑定 userId（用于精准下发）
 *   4) subscribeTopic / unsubscribeTopic  按业务主题分组（new-book, system 等）
 *   5) onMessage()      接收前台推送，回调给 NotificationChannel 渲染
 *
 * 当前阶段：Phase 3 占位 + Mock。
 * Phase 5 接入：
 *   - import push from '@hms.push'  （华为 Push Kit Stage Mode）
 *   - manifest 增加 ohos.permission.NOTIFICATION_CONTROLLER
 *   - AGC Console 配置 service id + secret
 *
 * 设计要点：
 *   - 单例，避免多实例订阅同一 topic 造成回调倍增
 *   - token 在内存缓存 + Preferences 持久化（HMS 服务异常时仍可读）
 *   - reportToken 失败不阻塞 init，由后台重试队列处理
 *   - onMessage 多订阅者支持（NotificationChannel + analytics 各订一份）
 */

import { PreferencesManager } from '../../../../core/persistence/PreferencesManager';
import { ApiConfig } from '../../../../api/client/ApiConfig';

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

      // TODO(Phase 5): import push from '@hms.push';
      //   await push.init();
      //   push.on('messageReceived', (raw) => this.dispatch(this.toPushMessage(raw)));
      //   const token = await push.getToken();
      //   await this.persistToken(token);
      this.startMockTokenIfNeeded();

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
    // TODO(Phase 5): const token = await push.getToken({ scope: 'HCM' });
    this.startMockTokenIfNeeded();
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
      // TODO(Phase 5): 真实 endpoint 走 HttpClient.post('/push/devices', ...)
      // 这里直接 fetch 模拟，避免循环依赖 HttpClient（HttpClient 反向依赖 UserStore）
      const url = `${ApiConfig.baseUrl}/push/devices`;
      const ok = await this.mockReport(url, { userId, token, platform: 'harmony' });
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
      // TODO(Phase 5): await push.subscribe(topic);
      this.subscribedTopics.add(topic);
      console.info(`${TAG} subscribed topic=${topic}`);
    } catch (e) {
      console.warn(`${TAG} subscribe ${topic} failed: ${(e as Error).message}`);
    }
  }

  async unsubscribeTopic(topic: string): Promise<void> {
    if (!this.subscribedTopics.has(topic)) return;
    try {
      // TODO(Phase 5): await push.unsubscribe(topic);
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

  private startMockTokenIfNeeded(): void {
    if (this.cachedToken.length > 0) return;
    const token = `${HmsPushServiceImpl.MOCK_TOKEN_PREFIX}${Date.now().toString(36)}`;
    this.cachedToken = token;
    PreferencesManager.setString(KEY_TOKEN, token).catch(() => {});
  }

  /** Mock 上报：模拟网络延迟 + 90% 成功率，便于演示重试链路。 */
  private async mockReport(url: string, payload: object): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      setTimeout(() => {
        // 90% 成功
        const ok = Math.random() < 0.9;
        console.info(`${TAG} mockReport url=${url} payload=${JSON.stringify(payload)} ok=${ok}`);
        resolve(ok);
      }, Math.min(REPORT_TIMEOUT_MS, 200));
    });
  }
}

/** 单例。 */
export const HmsPushService = new HmsPushServiceImpl();
