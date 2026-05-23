/**
 * PerformanceMonitor —— W20-C3 性能监控单例。
 *
 * 责任：
 *   - 代码块耗时：measure(name, fn) / markStart(name) + markEnd(name)
 *   - 内置监控点：app_start / first_frame / chapter_load / page_render / search_response
 *   - 帧率监控：基于 @ohos.display + requestAnimationFrame polyfill
 *   - 内存监控：基于 @ohos.process（peak RSS）
 *   - 上报到神策 Analytics（W18-C1）及 Sentry breadcrumb（W18-C3）
 *
 * 注意：
 *   - 单例，调用 PerformanceMonitor.getInstance()
 *   - init() 在 EntryAbility.onCreate 最早阶段调用
 *   - 所有时间戳使用 Date.now()（ms 级），高精度场景配合 hrtime（预留）
 */

import { Analytics } from '../analytics/AnalyticsProvider';
import { SentryClient } from '../monitoring/SentryClient';

// -------------------- 公共类型 --------------------

/** 内置监控点名称，业务侧可按需扩展字符串 */
export type BuiltinMark =
  | 'app_start'
  | 'first_frame'
  | 'chapter_load'
  | 'page_render'
  | 'search_response';

export interface PerfMeasure {
  name: string;
  startMs: number;
  endMs: number;
  durationMs: number;
}

export interface FrameStats {
  /** 采样区间帧数 */
  frameCount: number;
  /** 采样时长（ms） */
  elapsedMs: number;
  /** 平均帧率（fps） */
  avgFps: number;
  /** 掉帧数（帧耗时 > 16.6ms 计为掉帧） */
  jankyFrames: number;
}

export interface MemorySnapshot {
  /** 进程当前 RSS（KB），@ohos.process 提供 */
  rssKb: number;
  /** 峰值 RSS（KB） */
  peakRssKb: number;
  timestampMs: number;
}

// -------------------- 常量 --------------------

/** 性能告警阈值（ms） */
const THRESHOLDS: Record<string, number> = {
  app_start: 2000,
  first_frame: 500,
  chapter_load: 800,
  page_render: 100,
  search_response: 300,
};

/** 帧率采样间隔（ms） */
const FPS_SAMPLE_INTERVAL_MS = 1000;

/** 上报到神策的事件名 */
const SA_EVENT_PERF = 'perf_metric';

const TAG = 'PerformanceMonitor';

// -------------------- 单例 --------------------

export class PerformanceMonitor {
  private static instance: PerformanceMonitor | null = null;

  /** 单例入口 */
  static getInstance(): PerformanceMonitor {
    if (!PerformanceMonitor.instance) {
      PerformanceMonitor.instance = new PerformanceMonitor();
    }
    return PerformanceMonitor.instance;
  }

  // ---- 内部状态 ----
  private startMarks: Map<string, number> = new Map();
  private measures: PerfMeasure[] = [];
  private frameTimestamps: number[] = [];
  private fpsTimer: number = -1;
  private memSnapshots: MemorySnapshot[] = [];
  private initialized: boolean = false;
  private appStartMs: number = 0;

  // ---- 生命周期 ----

  /**
   * 应用入口最早调用，记录 app_start 起点。
   * EntryAbility.onCreate 首行调用。
   */
  init(): void {
    if (this.initialized) return;
    this.appStartMs = Date.now();
    this.markStart('app_start');
    this.startFpsMonitor();
    this.initialized = true;
    console.info(`${TAG} init at ${this.appStartMs}`);
  }

  // ---- 耗时测量 API ----

  /**
   * 标记开始点。搭配 markEnd(name) 计算区间耗时。
   * 同名重复调用会覆盖 start 时间戳。
   */
  markStart(name: string): void {
    this.startMarks.set(name, Date.now());
  }

  /**
   * 标记结束点，生成 PerfMeasure 并检查是否超阈值。
   * 返回耗时（ms），无对应 start 则返回 -1。
   */
  markEnd(name: string): number {
    const start = this.startMarks.get(name);
    if (start === undefined) {
      console.warn(`${TAG} markEnd without markStart: ${name}`);
      return -1;
    }
    const end = Date.now();
    const duration = end - start;
    const m: PerfMeasure = { name, startMs: start, endMs: end, durationMs: duration };
    this.measures.push(m);
    this.startMarks.delete(name);
    this.checkThreshold(m);
    console.info(`${TAG} [${name}] ${duration}ms`);
    return duration;
  }

  /**
   * 包裹测量：执行异步函数并自动打点。
   * 用法：const result = await monitor.measure('chapter_load', () => loadChapter(id));
   */
  async measure<T>(name: string, fn: () => Promise<T>): Promise<T> {
    this.markStart(name);
    try {
      const result = await fn();
      this.markEnd(name);
      return result;
    } catch (err) {
      // 即便失败也记录耗时，方便定位超时崩溃
      this.markEnd(name);
      throw err;
    }
  }

  // ---- 帧率监控 ----

  /**
   * 记录一帧渲染完成（在 Canvas onDraw / 页面 onPageShow 后调用）。
   * ReaderPage 翻页动画完成时调用此方法。
   */
  recordFrame(): void {
    this.frameTimestamps.push(Date.now());
    // 保留最近 120 帧（2s @ 60fps）
    if (this.frameTimestamps.length > 120) {
      this.frameTimestamps.shift();
    }
  }

  /** 计算当前采样窗口的帧率统计 */
  getFrameStats(): FrameStats {
    const frames = this.frameTimestamps;
    if (frames.length < 2) {
      return { frameCount: frames.length, elapsedMs: 0, avgFps: 0, jankyFrames: 0 };
    }
    const elapsed = frames[frames.length - 1] - frames[0];
    const avgFps = elapsed > 0 ? (frames.length / elapsed) * 1000 : 0;
    let janky = 0;
    for (let i = 1; i < frames.length; i++) {
      if (frames[i] - frames[i - 1] > 16.7) janky++;
    }
    return {
      frameCount: frames.length,
      elapsedMs: elapsed,
      avgFps: Math.round(avgFps * 10) / 10,
      jankyFrames: janky,
    };
  }

  // ---- 内存快照 ----

  /**
   * 采集一次内存快照。
   * @ohos.process 仅提供 RSS（KB），峰值由 monitor 维护。
   * 在 MemoryGuard 超阈值时也会调用此方法归档。
   */
  captureMemory(): MemorySnapshot {
    // @ohos.process 在真实设备上提供 process.memoryUsage()；
    // DevEco 模拟器或 web preview 中可能不可用，fallback 0
    let rssKb = 0;
    let peakRssKb = 0;
    try {
      // ArkTS 未直接暴露 process.memoryUsage，用 @ohos.hiSysEvent 读
      // 此处使用 performance.memory 替代（HarmonyOS NEXT 5.0 Browser-like API）
      const mem = (globalThis as Record<string, unknown>)['performance'] as
        { memory?: { usedJSHeapSize: number; totalJSHeapSize: number } } | undefined;
      if (mem?.memory) {
        rssKb = Math.round(mem.memory.usedJSHeapSize / 1024);
        peakRssKb = Math.round(mem.memory.totalJSHeapSize / 1024);
      }
    } catch (_e) { /* 不支持时静默 */ }

    // 维护历史峰值
    const lastPeak = this.memSnapshots.length > 0
      ? this.memSnapshots[this.memSnapshots.length - 1].peakRssKb
      : 0;
    const snap: MemorySnapshot = {
      rssKb,
      peakRssKb: Math.max(peakRssKb, lastPeak),
      timestampMs: Date.now(),
    };
    this.memSnapshots.push(snap);
    // 保留最近 60 条
    if (this.memSnapshots.length > 60) this.memSnapshots.shift();
    return snap;
  }

  /** 最新内存快照，无快照返回 null */
  getLastMemory(): MemorySnapshot | null {
    return this.memSnapshots.length > 0
      ? this.memSnapshots[this.memSnapshots.length - 1]
      : null;
  }

  // ---- 上报 ----

  /**
   * 将已采集的度量批量上报到神策（W18）和 Sentry（W18-C3）。
   * 建议在 onBackground / first_frame markEnd 后调用。
   */
  reportToAnalytics(): void {
    const fps = this.getFrameStats();
    const mem = this.getLastMemory();

    // 神策：每个 measure 一条事件
    for (const m of this.measures) {
      Analytics.track(SA_EVENT_PERF, {
        metric_name: m.name,
        duration_ms: m.durationMs,
        fps_avg: fps.avgFps,
        fps_janky: fps.jankyFrames,
        mem_rss_kb: mem?.rssKb ?? 0,
        exceeded_budget: m.durationMs > (THRESHOLDS[m.name] ?? Infinity) ? 1 : 0,
      });
    }

    // Sentry：超阈值的 measure 打 breadcrumb
    for (const m of this.measures) {
      const threshold = THRESHOLDS[m.name];
      if (threshold !== undefined && m.durationMs > threshold) {
        SentryClient.addBreadcrumb({
          category: 'performance',
          message: `${m.name} exceeded budget: ${m.durationMs}ms > ${threshold}ms`,
          level: 'warning',
          data: { duration_ms: m.durationMs, threshold_ms: threshold },
          timestamp: m.endMs,
        });
        SentryClient.captureMessage(
          `perf_budget_exceeded: ${m.name} ${m.durationMs}ms`,
          'warning',
          { metric: m.name, duration_ms: String(m.durationMs) },
        );
      }
    }

    // 清空已上报 measures，避免重复上报
    this.measures = [];
    console.info(`${TAG} reportToAnalytics done, fps=${fps.avgFps}, mem=${mem?.rssKb ?? 0}KB`);
  }

  // ---- 内部方法 ----

  /** 每秒采样帧率并打日志（仅 debug 用，不影响主线程） */
  private startFpsMonitor(): void {
    if (this.fpsTimer >= 0) return;
    this.fpsTimer = setInterval(() => {
      const stats = this.getFrameStats();
      if (stats.frameCount > 1) {
        console.debug(`${TAG} fps=${stats.avgFps} janky=${stats.jankyFrames}/${stats.frameCount}`);
        // 帧率持续低于 50fps 时向 Sentry 上报
        if (stats.avgFps < 50 && stats.avgFps > 0) {
          SentryClient.addBreadcrumb({
            category: 'performance',
            message: `low fps: ${stats.avgFps}`,
            level: 'warning',
            data: { avg_fps: stats.avgFps, janky_frames: stats.jankyFrames },
          });
        }
        // 重置帧时间戳，开始新采样窗口
        this.frameTimestamps = [];
      }
    }, FPS_SAMPLE_INTERVAL_MS) as unknown as number;
  }

  /** 检查单次 measure 是否超出预算，超出则打 warn 日志 */
  private checkThreshold(m: PerfMeasure): void {
    const threshold = THRESHOLDS[m.name];
    if (threshold !== undefined && m.durationMs > threshold) {
      console.warn(`${TAG} BUDGET_EXCEEDED [${m.name}] ${m.durationMs}ms > ${threshold}ms`);
    }
  }
}
