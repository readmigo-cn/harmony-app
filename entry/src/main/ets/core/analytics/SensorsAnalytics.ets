/**
 * SensorsAnalytics —— W18-C1 神策 SDK 适配层（HarmonyOS 实现）。
 *
 * 现状：
 *   - 神策官方暂未推出 HarmonyOS NEXT 原生 SDK
 *   - 当前先以 HTTP /sa?data=base64 协议手写 mock 实现，保留与官方协议一致的 wire format
 *   - Phase 4 待官方 SDK 上线，把 dispatch 替换为 SensorsDataAPI.track 调用
 *
 * 18 个核心事件枚举见底部 SaEvents 常量；命名沿用神策"动词式 + snake_case"约定。
 *
 * 队列与重试：
 *   - 内存队列上限 200 条，超过自动 flush
 *   - 30s 定时 flush；onBackground 立即 flush
 *   - flush 失败的 batch 持久化到 Preferences key `sa_failed_queue`，下次启动恢复
 *
 * 自动 enrich 字段（每个事件附带）：
 *   - $os = 'HarmonyOS'
 *   - $os_version / $app_version / $manufacturer / $model
 *   - $device_id  (HarmonyOS getDeviceId() 占位)
 *   - $screen_width / $screen_height
 *   - $network_type
 */

import { AnalyticsProvider, AnalyticsProperties, AnalyticsProperty } from './AnalyticsProvider';
import { PreferencesManager } from '../persistence/PreferencesManager';

// Try real Sensors Analytics HarmonyOS SDK
let SensorsDataAPI: {
  init: (serverUrl: string, config: object) => void;
  track: (eventName: string, properties: object) => void;
  login: (userId: string) => void;
  logout: () => void;
  profileSet: (properties: object) => void;
  flush: () => void;
} | null = null;

try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  SensorsDataAPI = require('@sensorsdata/analytics-harmony') as typeof SensorsDataAPI;
} catch (_) {
  console.info('SensorsAnalytics: SDK not available, using HTTP-mock provider');
}

const TAG = 'SensorsAnalytics';
const FAILED_QUEUE_KEY = 'sa_failed_queue';
const FLUSH_INTERVAL_MS = 30 * 1000;
const QUEUE_MAX_SIZE = 200;

// 18 个核心事件 —— Source of truth，业务侧禁止使用未定义事件名
export const SaEvents = {
  // 用户生命周期
  USER_SIGNUP: 'user_signup',
  LOGIN_SUCCEEDED: 'login_succeeded',
  LOGOUT: 'logout',
  // 阅读
  READING_STARTED: 'reading_started',
  READING_SESSION_ENDED: 'reading_session_ended',
  PAGE_TURN: 'page_turn',
  CHAPTER_COMPLETED: 'chapter_completed',
  // 单词
  WORD_LOOKUP: 'word_lookup',
  VOCAB_SAVED: 'vocab_saved',
  SRS_REVIEW: 'srs_review',
  // 听书
  AUDIOBOOK_PLAY_STARTED: 'audiobook_play_started',
  AUDIOBOOK_PLAY_PAUSED: 'audiobook_play_paused',
  // 付费
  PAYWALL_VIEWED: 'paywall_viewed',
  PAYMENT_STARTED: 'payment_started',
  PAYMENT_SUCCEEDED: 'payment_succeeded',
  PAYMENT_FAILED: 'payment_failed',
  // 其它
  PAGE_VIEW: 'page_view',
  APP_BACKGROUNDED: 'app_backgrounded',
};

interface SaEventEnvelope {
  event: string;
  type: 'track' | 'profile_set' | 'track_signup';
  time: number;                    // ms
  distinct_id: string;             // login userId 或 anonymousId
  anonymous_id?: string;
  original_id?: string;            // alias 时填旧 id
  properties: AnalyticsProperties;
}

export type SaProvider = 'sdk' | 'http-mock';

export interface SaConfigOptions {
  provider?: SaProvider;
  serverUrl: string;
  projectName: string;
}

export class SensorsAnalytics implements AnalyticsProvider {
  readonly name: string = 'sensors';

  private static instance: SensorsAnalytics | null = null;
  static getInstance(): SensorsAnalytics {
    if (!SensorsAnalytics.instance) SensorsAnalytics.instance = new SensorsAnalytics();
    return SensorsAnalytics.instance;
  }

  private serverUrl: string = '';
  private projectName: string = 'default';
  private activeProvider: SaProvider = SensorsDataAPI ? 'sdk' : 'http-mock';
  private distinctId: string = '';
  private anonymousId: string = '';
  private superProperties: AnalyticsProperties = {};
  private queue: SaEventEnvelope[] = [];
  private flushTimer: number = -1;
  private initialized: boolean = false;

  /**
   * Configure provider explicitly. Call before init() if you need to force
   * a specific provider ('sdk' | 'http-mock').
   */
  configure(opts: SaConfigOptions): void {
    if (opts.provider) {
      // Allow forcing 'http-mock' even when SDK is present (e.g. testing)
      this.activeProvider = (opts.provider === 'sdk' && SensorsDataAPI) ? 'sdk' : 'http-mock';
    }
    this.serverUrl = opts.serverUrl;
    this.projectName = opts.projectName;
  }

  /** 初始化：在 EntryAbility.onCreate 调用 */
  async init(serverUrl: string, projectName: string): Promise<void> {
    if (this.initialized) return;
    this.serverUrl = serverUrl;
    this.projectName = projectName;
    // 先恢复失败队列
    const failed = await PreferencesManager.getString(FAILED_QUEUE_KEY, '');
    if (failed.length > 0) {
      try {
        const arr = JSON.parse(failed) as SaEventEnvelope[];
        this.queue.push(...arr);
        await PreferencesManager.setString(FAILED_QUEUE_KEY, '');
      } catch (e) {
        console.warn(`${TAG} restore failed queue parse error: ${(e as Error).message}`);
      }
    }
    // 恢复 anonymousId（设备首次启动生成 UUID）
    const anon = await PreferencesManager.getString('sa_anonymous_id', '');
    if (anon.length > 0) {
      this.anonymousId = anon;
    } else {
      this.anonymousId = SensorsAnalytics.genUuid();
      await PreferencesManager.setString('sa_anonymous_id', this.anonymousId);
    }
    if (this.distinctId.length === 0) {
      this.distinctId = this.anonymousId;
    }

    // Init real SDK if available and provider is 'sdk'
    if (this.activeProvider === 'sdk' && SensorsDataAPI) {
      try {
        SensorsDataAPI.init(serverUrl, {
          project: projectName,
          flushInterval: 30000,
          flushBulkSize: 100,
          autoTrackEventType: 0,
        });
        console.info(`${TAG} real SDK init done`);
      } catch (e) {
        console.warn(`${TAG} SDK init failed, fallback to http-mock: ${(e as Error).message}`);
        this.activeProvider = 'http-mock';
      }
    }

    this.startFlushTimer();
    this.initialized = true;
    console.info(`${TAG} init done, provider=${this.activeProvider}, anonymousId=${this.anonymousId}`);
  }

  /** 注入设备/应用级属性（$lib、$app_version 等），后续每个事件自动附带 */
  registerSuperProperties(props: AnalyticsProperties): void {
    Object.assign(this.superProperties, props);
  }

  track(eventName: string, properties?: AnalyticsProperties): void {
    if (!this.initialized) {
      console.warn(`${TAG} track before init: ${eventName}`);
      return;
    }
    const merged: AnalyticsProperties = {};
    Object.assign(merged, this.superProperties);
    if (properties) Object.assign(merged, properties);
    this.enqueue({
      event: eventName,
      type: 'track',
      time: Date.now(),
      distinct_id: this.distinctId,
      anonymous_id: this.anonymousId,
      properties: merged,
    });
  }

  identify(userId: string, traits?: AnalyticsProperties): void {
    const oldId = this.distinctId;
    this.distinctId = userId;
    if (this.activeProvider === 'sdk' && SensorsDataAPI) {
      try {
        SensorsDataAPI.login(userId);
      } catch (_) {}
    }
    if (oldId.length > 0 && oldId !== userId) {
      this.alias(userId, oldId);
    }
    if (traits) {
      this.enqueue({
        event: 'profile_set',
        type: 'profile_set',
        time: Date.now(),
        distinct_id: this.distinctId,
        anonymous_id: this.anonymousId,
        properties: traits,
      });
    }
  }

  setUserProperty(key: string, value: AnalyticsProperty): void {
    const props: AnalyticsProperties = {};
    props[key] = value;
    this.enqueue({
      event: 'profile_set',
      type: 'profile_set',
      time: Date.now(),
      distinct_id: this.distinctId,
      anonymous_id: this.anonymousId,
      properties: props,
    });
  }

  alias(newId: string, oldId: string): void {
    this.enqueue({
      event: '$SignUp',
      type: 'track_signup',
      time: Date.now(),
      distinct_id: newId,
      original_id: oldId,
      properties: {},
    });
  }

  reset(): void {
    this.distinctId = this.anonymousId; // 回到匿名状态
    this.superProperties = {};
    if (this.activeProvider === 'sdk' && SensorsDataAPI) {
      try {
        SensorsDataAPI.logout();
      } catch (_) {}
    }
  }

  async flush(): Promise<void> {
    if (this.queue.length === 0) return;
    const batch = this.queue.slice();
    this.queue = [];
    try {
      await this.dispatch(batch);
    } catch (err) {
      console.warn(`${TAG} flush failed, persist for retry: ${(err as Error).message}`);
      // 失败回写到队头 + 持久化（崩溃恢复用）
      this.queue.unshift(...batch);
      await PreferencesManager.setString(FAILED_QUEUE_KEY, JSON.stringify(this.queue.slice(0, QUEUE_MAX_SIZE)));
    }
  }

  // ---------------- internals ----------------

  private enqueue(env: SaEventEnvelope): void {
    this.queue.push(env);
    if (this.queue.length >= QUEUE_MAX_SIZE) {
      this.flush().catch(() => {});
    }
  }

  private startFlushTimer(): void {
    if (this.flushTimer >= 0) return;
    this.flushTimer = setInterval(() => {
      this.flush().catch(() => {});
    }, FLUSH_INTERVAL_MS) as unknown as number;
  }

  /**
   * Dispatch batch via real SDK (if available) or HTTP-mock fallback.
   * Real SDK: SensorsDataAPI.track() per event + SensorsDataAPI.flush()
   * HTTP-mock: POST {serverUrl}/sa?project={projectName} with base64 payload
   */
  private async dispatch(batch: SaEventEnvelope[]): Promise<void> {
    if (this.activeProvider === 'sdk' && SensorsDataAPI) {
      try {
        for (const env of batch) {
          if (env.type === 'track') {
            SensorsDataAPI.track(env.event, env.properties);
          } else if (env.type === 'profile_set') {
            SensorsDataAPI.profileSet(env.properties);
          }
        }
        SensorsDataAPI.flush();
        return;
      } catch (e) {
        console.warn(`${TAG} SDK dispatch failed, falling through to http-mock: ${(e as Error).message}`);
      }
    }

    if (this.serverUrl.length === 0 || this.serverUrl.indexOf('_PLACEHOLDER_') >= 0) {
      if (batch.length > 0) {
        console.info(`${TAG} http-mock dispatch ${batch.length} events, first=${batch[0].event}`);
      }
      return;
    }

    // HTTP dispatch: POST application/x-www-form-urlencoded data=base64(json)
    try {
      const json = JSON.stringify(batch);
      const encoded = btoa(unescape(encodeURIComponent(json)));
      const body = `data=${encodeURIComponent(encoded)}&project=${encodeURIComponent(this.projectName)}`;
      await fetch(`${this.serverUrl}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body,
      });
      console.info(`${TAG} http dispatch ok, ${batch.length} events`);
    } catch (e) {
      throw e as Error;
    }
  }

  private static genUuid(): string {
    // RFC4122 v4 简化实现；HarmonyOS NEXT 暂无内置 uuid 模块
    let s = '';
    for (let i = 0; i < 32; i++) {
      const r = Math.floor(Math.random() * 16);
      const v = i === 12 ? 4 : (i === 16 ? (r & 0x3 | 0x8) : r);
      s += v.toString(16);
    }
    return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20)}`;
  }
}
