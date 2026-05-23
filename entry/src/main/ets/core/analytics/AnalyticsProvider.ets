/**
 * AnalyticsProvider —— W18-C1 埋点抽象接口。
 *
 * 设计目标：
 *   - 把"事件采集"从具体 SDK（神策 / Amplitude / Firebase）解耦
 *   - 业务侧调用 `Analytics.track(...)` 即可；切换厂商只换 provider 实现
 *   - 支持多 provider 并存（双轨上报、灰度对比）
 *
 * 当前 Phase 4 默认实现：SensorsAnalytics（神策），符合中国市场合规要求。
 *
 * 字段约定：
 *   - eventName：snake_case，固定枚举（见 SensorsAnalytics 内置 18 个核心事件）
 *   - properties：扁平对象，value 限制 string | number | boolean | null
 *   - userId：登录后服务端返回的 uuid；登出后 reset() 清掉
 *   - traits：用户画像字段（CEFR、订阅状态、注册日期等）
 *
 * 使用流程：
 *   1) EntryAbility.onCreate 调 Analytics.register(new SensorsAnalytics(...))
 *   2) Login 成功后 Analytics.identify(userId, { english_level, plan })
 *   3) 业务侧 Analytics.track('reading_started', { book_id, chapter_count })
 *   4) Logout 时 Analytics.reset()
 */

export type AnalyticsProperty = string | number | boolean | null;
export type AnalyticsProperties = Record<string, AnalyticsProperty>;

export interface AnalyticsProvider {
  /** provider 唯一名称，用于日志 / 调试 */
  readonly name: string;

  /** 上报一个业务事件。失败不抛出，由 provider 内部缓存重试。 */
  track(eventName: string, properties?: AnalyticsProperties): void;

  /** 关联匿名 anonymousId 到登录态 userId；首次登录时调用 */
  identify(userId: string, traits?: AnalyticsProperties): void;

  /** 设置单个用户级属性（profile_set 语义） */
  setUserProperty(key: string, value: AnalyticsProperty): void;

  /** 旧 anonymousId → 新 userId 的映射，避免设备首次登录 funnel 断裂 */
  alias(newId: string, oldId: string): void;

  /** 登出清理：清掉 userId、user properties、未上报队列里的 PII */
  reset(): void;

  /** 强制把缓存事件 flush 到服务端；onBackground / 退出前调用 */
  flush(): Promise<void>;
}

/**
 * Analytics —— 静态门面类。注册后业务侧统一通过这里调用。
 * 多 provider 注册时，所有方法广播到全部 provider（双轨）。
 */
export class Analytics {
  private static providers: AnalyticsProvider[] = [];

  /** 注册 provider；可注册多个实现双轨上报 */
  static register(provider: AnalyticsProvider): void {
    Analytics.providers.push(provider);
  }

  /** 清空所有 provider，仅测试 / 单元测试场景使用 */
  static unregisterAll(): void {
    Analytics.providers = [];
  }

  static track(eventName: string, properties?: AnalyticsProperties): void {
    for (const p of Analytics.providers) {
      try {
        p.track(eventName, properties);
      } catch (err) {
        console.warn(`[Analytics] ${p.name}.track failed: ${(err as Error).message}`);
      }
    }
  }

  static identify(userId: string, traits?: AnalyticsProperties): void {
    for (const p of Analytics.providers) {
      try { p.identify(userId, traits); } catch (_) {}
    }
  }

  static setUserProperty(key: string, value: AnalyticsProperty): void {
    for (const p of Analytics.providers) {
      try { p.setUserProperty(key, value); } catch (_) {}
    }
  }

  static alias(newId: string, oldId: string): void {
    for (const p of Analytics.providers) {
      try { p.alias(newId, oldId); } catch (_) {}
    }
  }

  static reset(): void {
    for (const p of Analytics.providers) {
      try { p.reset(); } catch (_) {}
    }
  }

  static async flush(): Promise<void> {
    await Promise.all(Analytics.providers.map((p) => p.flush().catch(() => {})));
  }
}
