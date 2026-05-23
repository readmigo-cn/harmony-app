/**
 * MemoryGuard —— W20-C3 内存监控与自动清理。
 *
 * 责任：
 *   - 定期轮询进程内存，超阈值时分级清理
 *   - 阈值：WARN 150MB / CRITICAL 180MB（对应性能预算 < 200MB 峰值目标）
 *   - 清理策略（WARN 触发部分清理，CRITICAL 触发全量清理）：
 *       1) 释放排版引擎（typesetting）运行时缓存
 *       2) 释放 W10 CacheManager 中 dict / translations 类目
 *       3) 释放图片 LRU 缓存（LazyImage 单例）
 *       4) 触发 JS GC hint（globalThis.gc，需 V8 --expose-gc）
 *   - onMemoryLow 回调供上层页面（Reader）响应低内存事件
 *   - 与 EntryAbility.onMemoryLevel 协作：系统信号触发时直接调 handleSystemMemoryLevel()
 */

import { CacheManager } from '../cache/CacheManager';
import { PerformanceMonitor } from './PerformanceMonitor';
import { SentryClient } from '../monitoring/SentryClient';

// -------------------- 类型 --------------------

export type MemoryLevel = 'normal' | 'warn' | 'critical';

export type MemoryLowCallback = (level: MemoryLevel, rssKb: number) => void;

export interface MemoryGuardOptions {
  /** 轮询间隔（ms），默认 5000 */
  pollIntervalMs?: number;
  /** WARN 阈值（KB），默认 150MB = 153600KB */
  warnThresholdKb?: number;
  /** CRITICAL 阈值（KB），默认 180MB = 184320KB */
  criticalThresholdKb?: number;
}

const TAG = 'MemoryGuard';

const DEFAULT_WARN_KB = 150 * 1024;     // 150MB
const DEFAULT_CRITICAL_KB = 180 * 1024; // 180MB
const DEFAULT_POLL_MS = 5000;

// -------------------- 单例 --------------------

export class MemoryGuard {
  private static instance: MemoryGuard | null = null;

  static getInstance(): MemoryGuard {
    if (!MemoryGuard.instance) {
      MemoryGuard.instance = new MemoryGuard();
    }
    return MemoryGuard.instance;
  }

  private pollTimer: number = -1;
  private callbacks: MemoryLowCallback[] = [];
  private lastLevel: MemoryLevel = 'normal';
  private warnKb: number = DEFAULT_WARN_KB;
  private criticalKb: number = DEFAULT_CRITICAL_KB;
  private initialized: boolean = false;

  // ---- 生命周期 ----

  /**
   * 启动内存监控轮询。
   * 建议在 EntryAbility.onCreate CRITICAL 阶段之后、HIGH 阶段调用。
   */
  start(opts?: MemoryGuardOptions): void {
    if (this.initialized) return;
    this.warnKb = opts?.warnThresholdKb ?? DEFAULT_WARN_KB;
    this.criticalKb = opts?.criticalThresholdKb ?? DEFAULT_CRITICAL_KB;
    const interval = opts?.pollIntervalMs ?? DEFAULT_POLL_MS;

    this.pollTimer = setInterval(() => {
      this.checkMemory();
    }, interval) as unknown as number;

    this.initialized = true;
    console.info(`${TAG} started, warn=${this.warnKb}KB, critical=${this.criticalKb}KB`);
  }

  /** 停止轮询（onDestroy 时调用） */
  stop(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
    this.initialized = false;
  }

  // ---- 回调注册 ----

  /**
   * 注册低内存回调（如 Reader 页面监听，收到 critical 时提示用户保存进度）。
   * 多个回调按注册顺序调用。
   */
  onMemoryLow(callback: MemoryLowCallback): void {
    this.callbacks.push(callback);
  }

  /** 移除特定回调 */
  removeCallback(callback: MemoryLowCallback): void {
    const idx = this.callbacks.indexOf(callback);
    if (idx >= 0) this.callbacks.splice(idx, 1);
  }

  // ---- 系统内存事件 ----

  /**
   * EntryAbility.onMemoryLevel 收到系统信号时调用此方法。
   * level 对应 AbilityConstant.MemoryLevel：
   *   0 = MODERATE → warn 策略
   *   1 = LOW      → critical 策略
   *   2 = CRITICAL → critical 策略 + 强制 GC
   */
  handleSystemMemoryLevel(level: number): void {
    console.warn(`${TAG} system memory level: ${level}`);
    if (level >= 1) {
      this.executeCleanup('critical', 0);
    } else {
      this.executeCleanup('warn', 0);
    }
  }

  // ---- 手动触发 ----

  /** 立即执行一次内存清理（外部可按需调用）。 */
  forceCleanup(level: MemoryLevel = 'warn'): void {
    this.executeCleanup(level, 0);
  }

  // ---- 内部 ----

  private checkMemory(): void {
    const monitor = PerformanceMonitor.getInstance();
    const snap = monitor.captureMemory();
    const rssKb = snap.rssKb;

    if (rssKb === 0) return; // 不支持采样，跳过

    let newLevel: MemoryLevel = 'normal';
    if (rssKb >= this.criticalKb) {
      newLevel = 'critical';
    } else if (rssKb >= this.warnKb) {
      newLevel = 'warn';
    }

    if (newLevel !== 'normal' && newLevel !== this.lastLevel) {
      console.warn(`${TAG} memory level changed: ${this.lastLevel} → ${newLevel}, rss=${rssKb}KB`);
      this.executeCleanup(newLevel, rssKb);
    }

    // 恢复正常时重置
    if (newLevel === 'normal' && this.lastLevel !== 'normal') {
      console.info(`${TAG} memory recovered, rss=${rssKb}KB`);
      this.lastLevel = 'normal';
    }
  }

  private executeCleanup(level: MemoryLevel, rssKb: number): void {
    this.lastLevel = level;

    console.warn(`${TAG} executing cleanup [${level}], rss=${rssKb}KB`);

    // ----- 策略 1：释放 typesetting 运行时缓存 -----
    // typesetting 引擎通过 native NAPI bridge 管理，
    // 调用 clearLayoutCache() 清理 native 侧的排版 cache
    try {
      const ts = (globalThis as Record<string, unknown>)['__readmigo_typesetting__'] as
        { clearLayoutCache?: () => void } | undefined;
      if (ts?.clearLayoutCache) {
        ts.clearLayoutCache();
        console.info(`${TAG} typesetting layout cache cleared`);
      }
    } catch (err) {
      console.warn(`${TAG} typesetting cache clear failed: ${(err as Error).message}`);
    }

    // ----- 策略 2：释放 W10 CacheManager dict/translations（非 pinned） -----
    try {
      if (level === 'warn') {
        // WARN：仅清 translations（最大、命中率低）
        CacheManager.clear('translations');
        console.info(`${TAG} CacheManager translations cleared`);
      } else {
        // CRITICAL：清 dict + translations；audio 和 chapters 保留（用户数据）
        CacheManager.clear('translations');
        CacheManager.clear('dict');
        console.info(`${TAG} CacheManager dict + translations cleared`);
      }
    } catch (err) {
      console.warn(`${TAG} CacheManager clear failed: ${(err as Error).message}`);
    }

    // ----- 策略 3：释放图片 LRU 缓存（LazyImage 单例） -----
    try {
      const lazyImageCache = (globalThis as Record<string, unknown>)['__readmigo_image_cache__'] as
        { clear?: (count?: number) => void } | undefined;
      if (lazyImageCache?.clear) {
        if (level === 'critical') {
          lazyImageCache.clear(); // 全清
        } else {
          lazyImageCache.clear(25); // WARN：清一半
        }
        console.info(`${TAG} LazyImage cache cleared`);
      }
    } catch (err) {
      console.warn(`${TAG} LazyImage cache clear failed: ${(err as Error).message}`);
    }

    // ----- 策略 4：触发 GC hint（仅 CRITICAL） -----
    if (level === 'critical') {
      try {
        const gc = (globalThis as Record<string, unknown>)['gc'] as (() => void) | undefined;
        if (typeof gc === 'function') {
          gc();
          console.info(`${TAG} GC hint triggered`);
        }
      } catch (_e) { /* V8 --expose-gc 未开启时静默 */ }
    }

    // Sentry breadcrumb 归档
    SentryClient.addBreadcrumb({
      category: 'memory',
      message: `MemoryGuard cleanup [${level}] rss=${rssKb}KB`,
      level: level === 'critical' ? 'error' : 'warning',
      data: { level, rss_kb: rssKb },
    });

    // 通知回调
    for (const cb of this.callbacks) {
      try {
        cb(level, rssKb);
      } catch (err) {
        console.warn(`${TAG} callback error: ${(err as Error).message}`);
      }
    }
  }
}
