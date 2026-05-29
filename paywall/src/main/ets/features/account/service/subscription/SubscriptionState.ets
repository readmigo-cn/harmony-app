/**
 * SubscriptionState.ets — W17-C4 全局订阅状态单例
 *
 * 职责：
 *   - 启动时拉云端 GET /subscription/me + 本地缓存 fallback
 *   - 暴露 getCurrentPlan / isProActive / getEntitlements / hasFeature
 *   - 订阅状态变化通知（subscribeChange）
 *   - 持久化：PreferencesManager 'subscription' namespace
 *   - 后台 24h 定时刷新（非阻塞）
 *
 * 同步策略（云端 + 本地）：
 *   1) init() 立刻读本地缓存 → 内存（保证 UI 同步可用）
 *   2) 异步拉云端；成功覆盖缓存 + 通知 watcher
 *   3) 失败保留缓存（可能过期），下次 24h tick 重试
 *   4) 业务侧支付成功后立即 refresh()，不等 tick
 *
 * Entitlement 模型：
 *   后端目前只返回 isPro + plan，前端按 plan 计算 features 列表
 *   （PricingTable 是前端单一源），便于 UI 直接 hasFeature(key)。
 */

import { PreferencesManager, NamespacedPreferences } from '../../../../core/persistence/PreferencesManager';
import {
  SubscriptionApi,
  SubscriptionInfo,
  SubscriptionPlan,
  SubscriptionStatus,
} from '../../../../api/subscription/SubscriptionApi';
import { PricingTable, PlanMeta, FeatureRow } from './PricingTable';

const NS = 'subscription';
const KEY_CACHE = 'state_cache_v1';
const KEY_CACHED_AT = 'state_cached_at';
const REFRESH_INTERVAL_MS = 24 * 60 * 60 * 1000; // 24h

/** 内部缓存模型（与 SubscriptionInfo 同构 + 时间戳）。 */
interface CachedState {
  isPro: boolean;
  plan: SubscriptionPlan | null;
  status: SubscriptionStatus | null;
  startedAt: string | null;
  expiresAt: string | null;
  cachedAt: number;
}

/** 对外暴露的 entitlement。 */
export interface Entitlement {
  feature: string;
  source: 'free' | 'pro_monthly' | 'pro_yearly' | 'premium_monthly';
  expiresAt: string | null;
}

/** 状态变更监听签名。 */
export type SubscriptionWatcher = (state: SubscriptionState) => void;

const EMPTY_STATE: CachedState = {
  isPro: false,
  plan: null,
  status: null,
  startedAt: null,
  expiresAt: null,
  cachedAt: 0,
};

export class SubscriptionState {
  private static instance: SubscriptionState | null = null;

  private prefs: NamespacedPreferences = PreferencesManager.createNamespace(NS);
  private cache: CachedState = EMPTY_STATE;
  private watchers: Set<SubscriptionWatcher> = new Set<SubscriptionWatcher>();
  private timer: number | null = null;
  private inited: boolean = false;
  private refreshing: boolean = false;

  static getInstance(): SubscriptionState {
    if (!SubscriptionState.instance) {
      SubscriptionState.instance = new SubscriptionState();
    }
    return SubscriptionState.instance;
  }

  /** EntryAbility.onCreate 调一次，幂等。 */
  async init(): Promise<void> {
    if (this.inited) return;
    this.inited = true;

    // 1) 先读本地缓存（同步可用）
    const cached = await this.prefs.getObject<CachedState>(KEY_CACHE, null);
    if (cached) {
      this.cache = cached;
      this.notify();
    }

    // 2) 异步拉云端，不阻塞启动
    this.refresh().catch((_e: Error) => { /* swallow */ });

    // 3) 启动 24h 定时刷新
    this.startRefreshTimer();
  }

  /**
   * 强制拉云端刷新。
   * 业务侧支付成功 / 用户登录切换 / 退款成功后调用。
   */
  async refresh(): Promise<void> {
    if (this.refreshing) return;
    this.refreshing = true;
    try {
      const info: SubscriptionInfo = await SubscriptionApi.me();
      const next: CachedState = {
        isPro: info.isPro,
        plan: info.subscription ? info.subscription.plan : null,
        status: info.subscription ? info.subscription.status : null,
        startedAt: info.subscription ? info.subscription.startedAt : null,
        expiresAt: info.subscription ? info.subscription.expiresAt : null,
        cachedAt: Date.now(),
      };
      const changed = !this.equals(this.cache, next);
      this.cache = next;
      await this.persist();
      if (changed) this.notify();
    } finally {
      this.refreshing = false;
    }
  }

  // ─── 查询 API ────────────────────────────────

  /** 当前订阅 plan meta；未订阅返回 free meta。 */
  getCurrentPlan(): PlanMeta {
    if (this.cache.isPro && this.cache.plan) {
      const meta = PricingTable.getPlan(this.cache.plan);
      if (meta) return meta;
    }
    return PricingTable.getPlan('free')!;
  }

  /** 是否为 Pro / Premium 有效订阅。 */
  isProActive(): boolean {
    if (!this.cache.isPro) return false;
    if (this.cache.status !== 'active') return false;
    if (this.cache.expiresAt) {
      const exp = Date.parse(this.cache.expiresAt);
      if (!isNaN(exp) && exp < Date.now()) return false;
    }
    return true;
  }

  /** 当前生效的 entitlement 列表。 */
  getEntitlements(): Entitlement[] {
    const meta = this.getCurrentPlan();
    const rows: FeatureRow[] = PricingTable.featureRows();
    const out: Entitlement[] = [];
    for (let i = 0; i < rows.length; i++) {
      const r = rows[i];
      const has = SubscriptionState.featureForTier(r, meta.tier);
      if (has) {
        out.push({
          feature: r.key,
          source: meta.tier,
          expiresAt: this.cache.expiresAt,
        });
      }
    }
    return out;
  }

  /** 用户是否拥有指定功能。 */
  hasFeature(featureKey: string): boolean {
    const meta = this.getCurrentPlan();
    const rows = PricingTable.featureRows();
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].key === featureKey) {
        return SubscriptionState.featureForTier(rows[i], meta.tier);
      }
    }
    return false;
  }

  /** 到期时间（ISO 字符串），未订阅 / 永久则为 null。 */
  getExpiresAt(): string | null {
    return this.cache.expiresAt;
  }

  /** 后端订阅状态。 */
  getStatus(): SubscriptionStatus | null {
    return this.cache.status;
  }

  getStartedAt(): string | null {
    return this.cache.startedAt;
  }

  /** 缓存是否有效（24h 内）。 */
  isCacheFresh(): boolean {
    return Date.now() - this.cache.cachedAt < REFRESH_INTERVAL_MS;
  }

  // ─── Watch ───────────────────────────────────

  subscribeChange(cb: SubscriptionWatcher): () => void {
    this.watchers.add(cb);
    // 立刻回调一次当前状态，便于初始渲染
    try { cb(this); } catch (_e) { /* swallow */ }
    return () => { this.watchers.delete(cb); };
  }

  /** 注销订阅。退出登录 / 切换账号时调用。 */
  async clear(): Promise<void> {
    this.cache = EMPTY_STATE;
    await this.prefs.remove(KEY_CACHE);
    await this.prefs.remove(KEY_CACHED_AT);
    this.notify();
  }

  // ─── internals ───────────────────────────────

  private notify(): void {
    this.watchers.forEach((cb) => {
      try { cb(this); } catch (_e) { /* swallow */ }
    });
  }

  private async persist(): Promise<void> {
    await this.prefs.setObject<CachedState>(KEY_CACHE, this.cache);
    await this.prefs.setNumber(KEY_CACHED_AT, this.cache.cachedAt);
  }

  private equals(a: CachedState, b: CachedState): boolean {
    return a.isPro === b.isPro
      && a.plan === b.plan
      && a.status === b.status
      && a.startedAt === b.startedAt
      && a.expiresAt === b.expiresAt;
  }

  private startRefreshTimer(): void {
    if (this.timer !== null) return;
    this.timer = setInterval(() => {
      this.refresh().catch((_e: Error) => { /* swallow */ });
    }, REFRESH_INTERVAL_MS);
  }

  /** 套餐 tier 对功能的开通判定。 */
  private static featureForTier(row: FeatureRow, tier: string): boolean {
    switch (tier) {
      case 'pro_monthly':     return row.proMonthly;
      case 'pro_yearly':      return row.proYearly;
      case 'premium_monthly': return row.premiumMonthly;
      default:                return row.free;
    }
  }
}
