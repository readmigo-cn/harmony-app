/**
 * RemoteConfig.ets — W18-C7 远程配置 + A/B 实验
 *
 * 集成点：
 *   - 华为 AGC Remote Config（Phase 5 接入 @hms.agconnect-remoteconfig）
 *   - 当前 Phase 3 走 Mock：默认值 + 本地缓存 + 24h TTL
 *
 * 接口：
 *   getString / getBool / getNumber / getJson  统一 default 兜底
 *   getExperimentBucket(name)                  返回 'control' / 'A' / 'B' / ...
 *   refresh(force?)                            主动拉取（init 时自动调）
 *
 * A/B 桶分配算法（确定性）：
 *   bucket = HASH(userId + experimentName) mod 100
 *   experimentName 维度独立，不同实验互不影响
 *   每个实验声明 buckets: [{ name, weight }]，weight 总和 = 100
 *   - 未登录 → 用 deviceId fallback；同一设备同实验始终落同一桶
 *   - 实验定义在 EXPERIMENT_DEFS，新增实验只动这里
 *
 * 缓存策略：
 *   - 拉取成功后写 Preferences，时间戳走 KEY_FETCHED_AT
 *   - 24h 内复用本地；force=true 跳过 TTL
 *   - 网络失败时退回上次缓存；都没有则用 EXPERIMENT_DEFS 默认值
 */

import { PreferencesManager } from '../persistence/PreferencesManager';
import { UserStore } from '../../store/UserStore';

const TAG = 'RemoteConfig';

const KEY_VALUES = 'remote_config_values';
const KEY_FETCHED_AT = 'remote_config_fetched_at';
const KEY_DEVICE_ID = 'remote_config_device_id';
const TTL_MS = 24 * 60 * 60 * 1000;

/** 实验桶定义。 */
export interface ExperimentBucket {
  name: string;
  /** 0–100 权重，所有桶之和必须 = 100 */
  weight: number;
}

/** 实验定义。 */
export interface ExperimentDef {
  name: string;
  buckets: ExperimentBucket[];
  /** 未命中实验时返回的默认桶（一般是 control） */
  defaultBucket: string;
  /** 是否启用，关掉则始终返回 defaultBucket */
  enabled: boolean;
}

/** 内置示例实验：与产品文档对齐，A/B 比例 50/50 或 33/33/34。 */
const EXPERIMENT_DEFS: Record<string, ExperimentDef> = {
  /** Paywall 布局：cards (默认) vs list 形式 */
  paywall_layout: {
    name: 'paywall_layout',
    buckets: [
      { name: 'control', weight: 50 }, // cards
      { name: 'A', weight: 50 },        // list
    ],
    defaultBucket: 'control',
    enabled: true,
  },
  /** 阅读器默认主题：日间 vs 夜间 */
  reader_default_theme: {
    name: 'reader_default_theme',
    buckets: [
      { name: 'control', weight: 70 }, // day
      { name: 'A', weight: 30 },        // night（针对夜读用户的默认体验）
    ],
    defaultBucket: 'control',
    enabled: true,
  },
  /** Onboarding 步数：3 步 vs 5 步 */
  onboarding_steps: {
    name: 'onboarding_steps',
    buckets: [
      { name: 'control', weight: 50 }, // 3 步
      { name: 'A', weight: 50 },        // 5 步
    ],
    defaultBucket: 'control',
    enabled: true,
  },
};

/** 出厂默认值，AGC 拉取失败时兜底。 */
const DEFAULT_VALUES: Record<string, string> = {
  // 通用 feature flag
  enable_audiobook_chapter_marker: 'true',
  enable_distributed_clipboard: 'true',
  // 文案 / 数值
  paywall_trial_days: '7',
  paywall_discount_text: '限时五折',
  // JSON 也以字符串存
  homepage_banners: '[]',
};

/** 缓存的远程值（运行时反序列化）。 */
type CachedValues = Record<string, string>;

class RemoteConfigImpl {
  private initialized: boolean = false;
  private values: CachedValues = {};
  /** 启动会调一次 init() → refresh()，期间所有 getter 仍返回 default。 */
  private refreshing: boolean = false;

  /** EntryAbility.onCreate 调一次。 */
  async init(): Promise<void> {
    if (this.initialized) return;
    this.initialized = true;
    try {
      // 还原本地缓存
      const cached = await PreferencesManager.getObject<CachedValues>(KEY_VALUES, {});
      this.values = cached ?? {};
      // 拉新（异步、不阻塞 onCreate）
      this.refresh(false).catch((e: Error) => {
        console.warn(`${TAG} initial refresh failed: ${e.message}`);
      });
      console.info(`${TAG} init done, cached ${Object.keys(this.values).length} keys`);
    } catch (e) {
      console.warn(`${TAG} init failed: ${(e as Error).message}`);
    }
  }

  /** 拉取远程配置；force=true 跳过 24h TTL。 */
  async refresh(force: boolean = false): Promise<void> {
    if (this.refreshing) return;
    this.refreshing = true;
    try {
      const fetchedAt = await PreferencesManager.getNumber(KEY_FETCHED_AT, 0);
      if (!force && fetchedAt > 0 && Date.now() - fetchedAt < TTL_MS) {
        console.info(`${TAG} refresh skipped (cache hit, age=${Date.now() - fetchedAt}ms)`);
        return;
      }
      // TODO(Phase 5): 调用 @hms.agconnect-remoteconfig
      //   await agc.fetch();
      //   await agc.applyLastFetched();
      //   const all = await agc.getMergedAll();
      const fetched = await this.mockFetch();
      this.values = { ...DEFAULT_VALUES, ...fetched };
      await PreferencesManager.setObject<CachedValues>(KEY_VALUES, this.values);
      await PreferencesManager.setNumber(KEY_FETCHED_AT, Date.now());
      console.info(`${TAG} refresh ok, ${Object.keys(this.values).length} keys`);
    } catch (e) {
      console.warn(`${TAG} refresh failed: ${(e as Error).message}`);
    } finally {
      this.refreshing = false;
    }
  }

  // ---------- typed getters ----------

  getString(key: string, def: string): string {
    const v = this.values[key];
    return typeof v === 'string' && v.length > 0 ? v : (DEFAULT_VALUES[key] ?? def);
  }

  getBool(key: string, def: boolean): boolean {
    const v = this.values[key] ?? DEFAULT_VALUES[key];
    if (v === 'true') return true;
    if (v === 'false') return false;
    return def;
  }

  getNumber(key: string, def: number): number {
    const v = this.values[key] ?? DEFAULT_VALUES[key];
    if (v === undefined) return def;
    const n = parseFloat(v);
    return Number.isFinite(n) ? n : def;
  }

  getJson<T>(key: string, def: T): T {
    const v = this.values[key] ?? DEFAULT_VALUES[key];
    if (!v) return def;
    try {
      return JSON.parse(v) as T;
    } catch (_e) {
      return def;
    }
  }

  // ---------- A/B 实验 ----------

  /**
   * 返回当前用户在某实验中的桶名。
   * 同一 user + 同一实验始终返回相同结果（确定性 hash）。
   */
  getExperimentBucket(experimentName: string): string {
    const def = EXPERIMENT_DEFS[experimentName];
    if (!def) {
      console.warn(`${TAG} unknown experiment: ${experimentName}`);
      return 'control';
    }
    if (!def.enabled) return def.defaultBucket;

    const subjectId = this.getSubjectId();
    const hash = this.hash32(`${subjectId}:${experimentName}`);
    const slot = hash % 100;

    let acc = 0;
    for (let i = 0; i < def.buckets.length; i++) {
      const b = def.buckets[i];
      acc += b.weight;
      if (slot < acc) return b.name;
    }
    return def.defaultBucket;
  }

  /** 列出所有内置实验定义（debug 页可视化用）。 */
  listExperiments(): ExperimentDef[] {
    return Object.values(EXPERIMENT_DEFS);
  }

  /** 当前 subjectId（user 优先，未登录 fallback deviceId）。 */
  getSubjectId(): string {
    if (UserStore.isLoggedIn()) {
      const profile = UserStore.getProfile();
      if (profile && profile.id) return `u:${profile.id}`;
    }
    return `d:${this.ensureDeviceId()}`;
  }

  // ---------- internals ----------

  /** 设备指纹：首次启动随机生成，存 Preferences；不变直至卸载。 */
  private cachedDeviceId: string = '';
  private ensureDeviceId(): string {
    if (this.cachedDeviceId.length > 0) return this.cachedDeviceId;
    // 直接读 AppStorage（Preferences 是 async，这里要同步路径）
    const cached = AppStorage.Get<string>(KEY_DEVICE_ID) ?? '';
    if (cached.length > 0) {
      this.cachedDeviceId = cached;
      return cached;
    }
    const id = `dev-${Date.now().toString(36)}-${Math.floor(Math.random() * 0xffffff).toString(36)}`;
    this.cachedDeviceId = id;
    AppStorage.SetOrCreate<string>(KEY_DEVICE_ID, id);
    PreferencesManager.setString(KEY_DEVICE_ID, id).catch(() => {});
    return id;
  }

  /** djb2 hash → 32-bit 无符号。 */
  private hash32(s: string): number {
    let h = 5381;
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) + h + s.charCodeAt(i)) | 0;
    }
    return Math.abs(h);
  }

  /** Mock：模拟 AGC 返回 - 在 default 之外注入几个实验值。 */
  private async mockFetch(): Promise<Record<string, string>> {
    return new Promise<Record<string, string>>((resolve) => {
      setTimeout(() => {
        resolve({
          paywall_trial_days: '7',
          paywall_discount_text: '新用户首月五折',
          homepage_banners: JSON.stringify([
            { id: 'b1', title: '新书上架', img: '' },
          ]),
        });
      }, 100);
    });
  }
}

/** 单例。 */
export const RemoteConfig = new RemoteConfigImpl();
