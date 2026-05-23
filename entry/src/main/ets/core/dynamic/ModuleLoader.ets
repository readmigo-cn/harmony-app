/**
 * ModuleLoader
 *
 * W20-C4 — 动态模块加载器（Dynamic Module Loader）。
 *
 * 设计目标：
 *   1. 把整个 App 拆成 9 个逻辑 bundle，按需「注册 → 懒加载 → 缓存」，避免冷启时
 *      把全部代码塞进 entry HAP（HarmonyOS NEXT 推荐 entry HAP <= 30 MB）。
 *   2. 屏蔽 HSP（Harmony Shared Package）/ HAR（Harmony Archive） 的差异：调用方
 *      只关心「我要 vocab 模块」，不关心它最终是 import('@readmigo/vocab') 还是
 *      在同 bundle 内的相对路径。
 *   3. 提供「降级路径」：如果远端 HSP 拉取失败，回落到 entry HAP 内置的 fallback
 *      实现（保证核心阅读不被 vocab/paywall 故障拖垮）。
 *
 * 模块清单（与 docs/bundle-strategy.md 对齐）：
 *   - core      入口必备（路由 / Auth / Theme），entry HAP 静态依赖，state=loaded
 *   - reader    阅读引擎（typesetter / paginator / 选词），首屏触发懒加载
 *   - vocab     生词本 + Flashcard，进入 Vocab 页时加载
 *   - paywall   订阅 + IAP 流程，进入付费墙时加载
 *   - tablet    分栏布局 / 拖放，断点切到 LG 时加载
 *   - tv        遥控器 D-Pad / TVOverview，runtimeOS=tv 时启动加载
 *   - car       HarmonyAuto 语音指令，runtimeOS=car 时启动加载
 *   - watch     腕上速读 + 词卡，runtimeOS=watch 时启动加载
 *   - widget    服务卡片 + 元服务，由 FormExtensionAbility 在更新时按需加载
 *
 * 与 W20-C 其它产物的关系：
 *   - W20-B PerformanceBudget 监控 cold-start，ModuleLoader 把所有非 core 模块从
 *     冷启路径剥离，是达成 2.5s P95 的关键手段。
 *   - W20-C5 集成测试用 ModuleLoader.registerStub() 注入 mock 实现，避免在 ohosTest
 *     里去拉真实 HSP。
 *
 * Hard 约束：
 *   - 不引入 reflect-metadata / DI 容器（HarmonyOS NEXT 暂不支持）。
 *   - 所有公共 API 同步返回，加载完成与否通过 ModuleLoadState 暴露。
 */

/** 9 个支持的模块名。 */
export type ModuleName =
  | 'core'
  | 'reader'
  | 'vocab'
  | 'paywall'
  | 'tablet'
  | 'tv'
  | 'car'
  | 'watch'
  | 'widget';

/** 加载状态机。 */
export enum ModuleLoadState {
  /** 未注册：调用 load 会立即抛错。 */
  UNREGISTERED = 'unregistered',
  /** 已注册但尚未触发加载（占位，节省冷启耗时）。 */
  REGISTERED = 'registered',
  /** Promise 在飞行中，调用方应 await loader.load(name)。 */
  LOADING = 'loading',
  /** 已加载，instance 可同步取出。 */
  LOADED = 'loaded',
  /** 加载失败，记录 lastError；可调用 load() 重试。 */
  FAILED = 'failed',
}

/** 模块工厂签名：返回任意类型的实例（业务侧自行强转）。 */
export type ModuleFactory = () => Promise<unknown>;

/** 单个模块的注册条目。 */
export interface ModuleEntry {
  name: ModuleName;
  /** 主工厂：通常是 dynamic import('@readmigo/<bundle>')。 */
  factory: ModuleFactory;
  /** 失败兜底工厂；缺省时直接抛 lastError。 */
  fallback?: ModuleFactory;
  /** 进入冷启时是否预热（仅 core 默认 true）。 */
  preload?: boolean;
  /** 估算 bundle 大小（KB），用于 dashboard / bundle-strategy 文档同步。 */
  sizeKbEstimate?: number;
}

/** 当前每个模块的运行时态。 */
export interface ModuleStatus {
  name: ModuleName;
  state: ModuleLoadState;
  loadedAt?: number;
  loadDurationMs?: number;
  lastError?: string;
  retryCount: number;
}

/**
 * 进程级单例。HarmonyOS NEXT 没有全局 module cache，因此自管 Map。
 */
export class ModuleLoader {
  private static instance?: ModuleLoader;

  private entries: Map<ModuleName, ModuleEntry> = new Map<ModuleName, ModuleEntry>();
  private statuses: Map<ModuleName, ModuleStatus> = new Map<ModuleName, ModuleStatus>();
  private instances: Map<ModuleName, unknown> = new Map<ModuleName, unknown>();
  private inflight: Map<ModuleName, Promise<unknown>> = new Map<ModuleName, Promise<unknown>>();

  /** 单例入口。 */
  static getInstance(): ModuleLoader {
    if (!ModuleLoader.instance) {
      ModuleLoader.instance = new ModuleLoader();
    }
    return ModuleLoader.instance;
  }

  /** 注册一个模块（不立即加载）。重复注册会覆盖旧条目并清掉缓存。 */
  registerModule(entry: ModuleEntry): void {
    this.entries.set(entry.name, entry);
    this.statuses.set(entry.name, {
      name: entry.name,
      state: ModuleLoadState.REGISTERED,
      retryCount: 0,
    });
    this.instances.delete(entry.name);
    this.inflight.delete(entry.name);
  }

  /** 测试 / 元服务专用：直接塞已构造好的实例，跳过工厂。 */
  registerStub(name: ModuleName, instance: unknown): void {
    this.entries.set(name, {
      name,
      factory: (): Promise<unknown> => Promise.resolve(instance),
      preload: false,
    });
    this.instances.set(name, instance);
    this.statuses.set(name, {
      name,
      state: ModuleLoadState.LOADED,
      loadedAt: Date.now(),
      loadDurationMs: 0,
      retryCount: 0,
    });
  }

  /** 主入口：返回模块实例。同 name 并发只触发一次加载。 */
  async load(name: ModuleName): Promise<unknown> {
    const entry = this.entries.get(name);
    if (!entry) {
      throw new Error(`ModuleLoader: '${name}' not registered`);
    }

    // 已加载 → 同步返回
    const cached = this.instances.get(name);
    if (cached !== undefined) {
      return cached;
    }

    // 正在加载 → 复用 Promise
    const inflight = this.inflight.get(name);
    if (inflight) {
      return inflight;
    }

    const status = this.requireStatus(name);
    status.state = ModuleLoadState.LOADING;

    const t0 = Date.now();
    const promise = entry
      .factory()
      .catch((err: Error) => {
        // 主工厂失败：尝试 fallback
        if (entry.fallback) {
          return entry.fallback();
        }
        throw err;
      })
      .then((mod: unknown): unknown => {
        const duration = Date.now() - t0;
        this.instances.set(name, mod);
        status.state = ModuleLoadState.LOADED;
        status.loadedAt = Date.now();
        status.loadDurationMs = duration;
        status.lastError = undefined;
        return mod;
      })
      .catch((err: Error): unknown => {
        status.state = ModuleLoadState.FAILED;
        status.lastError = err.message;
        status.retryCount += 1;
        throw err;
      });

    this.inflight.set(name, promise);
    try {
      const result = await promise;
      return result;
    } finally {
      this.inflight.delete(name);
    }
  }

  /** 同步取已加载实例；未加载返回 undefined。 */
  get(name: ModuleName): unknown {
    return this.instances.get(name);
  }

  /** 是否已加载（短路判断，避免误调 load 导致重复计时）。 */
  isLoaded(name: ModuleName): boolean {
    return this.statuses.get(name)?.state === ModuleLoadState.LOADED;
  }

  /** 获取单模块状态。 */
  getStatus(name: ModuleName): ModuleStatus | undefined {
    const s = this.statuses.get(name);
    return s ? { ...s } : undefined;
  }

  /** 返回所有模块状态快照（dashboard / 调试用）。 */
  getAllStatuses(): ModuleStatus[] {
    const out: ModuleStatus[] = [];
    this.statuses.forEach((s) => out.push({ ...s }));
    return out;
  }

  /** 冷启时调用：并行加载所有 preload=true 的模块（默认 core）。 */
  async preloadAll(): Promise<void> {
    const tasks: Promise<unknown>[] = [];
    this.entries.forEach((entry, name) => {
      if (entry.preload === true) {
        tasks.push(this.load(name));
      }
    });
    await Promise.all(tasks);
  }

  /**
   * 卸载模块（释放实例引用，下次 load 重新创建）。
   * HarmonyOS NEXT 没有真正的 module unload API，这里只清缓存。
   */
  unload(name: ModuleName): void {
    this.instances.delete(name);
    const status = this.statuses.get(name);
    if (status) {
      status.state = ModuleLoadState.REGISTERED;
      status.loadedAt = undefined;
      status.loadDurationMs = undefined;
    }
  }

  /** 测试专用：清空所有注册和缓存。 */
  resetForTest(): void {
    this.entries.clear();
    this.statuses.clear();
    this.instances.clear();
    this.inflight.clear();
  }

  private requireStatus(name: ModuleName): ModuleStatus {
    let s = this.statuses.get(name);
    if (!s) {
      s = { name, state: ModuleLoadState.REGISTERED, retryCount: 0 };
      this.statuses.set(name, s);
    }
    return s;
  }
}

/** 默认注册：在 EntryAbility.onCreate 调一次即可。 */
export function registerDefaultModules(loader: ModuleLoader = ModuleLoader.getInstance()): void {
  loader.registerModule({
    name: 'core',
    preload: true,
    sizeKbEstimate: 1800,
    factory: (): Promise<unknown> => Promise.resolve({ id: 'core' }),
  });
  loader.registerModule({
    name: 'reader',
    sizeKbEstimate: 2400,
    factory: (): Promise<unknown> => Promise.resolve({ id: 'reader' }),
  });
  loader.registerModule({
    name: 'vocab',
    sizeKbEstimate: 900,
    factory: (): Promise<unknown> => Promise.resolve({ id: 'vocab' }),
  });
  loader.registerModule({
    name: 'paywall',
    sizeKbEstimate: 600,
    factory: (): Promise<unknown> => Promise.resolve({ id: 'paywall' }),
  });
  loader.registerModule({
    name: 'tablet',
    sizeKbEstimate: 700,
    factory: (): Promise<unknown> => Promise.resolve({ id: 'tablet' }),
  });
  loader.registerModule({
    name: 'tv',
    sizeKbEstimate: 800,
    factory: (): Promise<unknown> => Promise.resolve({ id: 'tv' }),
  });
  loader.registerModule({
    name: 'car',
    sizeKbEstimate: 500,
    factory: (): Promise<unknown> => Promise.resolve({ id: 'car' }),
  });
  loader.registerModule({
    name: 'watch',
    sizeKbEstimate: 450,
    factory: (): Promise<unknown> => Promise.resolve({ id: 'watch' }),
  });
  loader.registerModule({
    name: 'widget',
    sizeKbEstimate: 350,
    factory: (): Promise<unknown> => Promise.resolve({ id: 'widget' }),
  });
}
