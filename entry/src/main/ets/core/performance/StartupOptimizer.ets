/**
 * StartupOptimizer —— W20-C3 异步启动任务框架。
 *
 * 责任：
 *   - 按优先级调度 EntryAbility.onCreate 中的所有初始化任务
 *   - 减少冷启动关键路径耗时，目标：首屏 < 500ms，冷启动 < 2s
 *
 * 优先级定义：
 *   CRITICAL  — 首屏渲染前必须完成（同步阻塞关键路径）
 *   HIGH      — 首屏渲染后立即调度（微任务队列）
 *   NORMAL    — 空闲时调度（setTimeout 100ms）
 *   LOW       — 延迟调度（setTimeout 1000ms）
 *
 * 关键路径分析（根据 EntryAbility.ets 代码审计）：
 *   CRITICAL：PreferencesManager.init → DatabaseManager.init → Stores rehydrate → ThemeService
 *   HIGH：FontRegistry / SensorsAnalytics / CrashReporter / Sentry
 *   NORMAL：RemoteConfig / HmsPushService / NotificationChannel / SyncEngine
 *   LOW：CrashHandler.checkPendingCrashOnLaunch / SensorsAnalytics queue replay / AGC flush
 *
 * 用法：
 *   const optimizer = StartupOptimizer.getInstance();
 *   optimizer.registerTask('prefs_init', TaskPriority.CRITICAL, () => PreferencesManager.init(ctx));
 *   await optimizer.run();
 */

import { PerformanceMonitor } from './PerformanceMonitor';

// -------------------- 优先级 --------------------

export enum TaskPriority {
  CRITICAL = 0, // 首屏前，同步等待
  HIGH = 1,     // 首屏后立即，微任务
  NORMAL = 2,   // 空闲期，100ms 延迟
  LOW = 3,      // 懒加载，1000ms 延迟
}

const PRIORITY_DELAY: Record<TaskPriority, number> = {
  [TaskPriority.CRITICAL]: 0,
  [TaskPriority.HIGH]: 0,    // Promise.resolve() 微任务
  [TaskPriority.NORMAL]: 100,
  [TaskPriority.LOW]: 1000,
};

// -------------------- 任务类型 --------------------

export interface StartupTask {
  name: string;
  priority: TaskPriority;
  fn: () => Promise<void> | void;
  /** 任务超时（ms）；超时后打 warn 日志，不阻塞后续任务 */
  timeoutMs?: number;
}

interface TaskResult {
  name: string;
  priority: TaskPriority;
  durationMs: number;
  error?: string;
}

const TAG = 'StartupOptimizer';

/** CRITICAL 任务超时上限（ms）。超出则 warn，整体启动不阻塞 */
const CRITICAL_TIMEOUT_MS = 1500;

// -------------------- 单例 --------------------

export class StartupOptimizer {
  private static instance: StartupOptimizer | null = null;

  static getInstance(): StartupOptimizer {
    if (!StartupOptimizer.instance) {
      StartupOptimizer.instance = new StartupOptimizer();
    }
    return StartupOptimizer.instance;
  }

  private tasks: StartupTask[] = [];
  private results: TaskResult[] = [];
  private hasRun: boolean = false;

  // ---- 注册 ----

  /**
   * 注册一个启动任务。
   * @param name      任务标识（同名会覆盖）
   * @param priority  TaskPriority.CRITICAL / HIGH / NORMAL / LOW
   * @param fn        异步初始化函数
   * @param timeoutMs 单任务超时（可选）
   */
  registerTask(
    name: string,
    priority: TaskPriority,
    fn: () => Promise<void> | void,
    timeoutMs?: number,
  ): void {
    // 同名覆盖
    const idx = this.tasks.findIndex(t => t.name === name);
    const task: StartupTask = {
      name,
      priority,
      fn,
      timeoutMs: timeoutMs ?? (priority === TaskPriority.CRITICAL ? CRITICAL_TIMEOUT_MS : undefined),
    };
    if (idx >= 0) {
      this.tasks[idx] = task;
    } else {
      this.tasks.push(task);
    }
  }

  // ---- 执行 ----

  /**
   * 按优先级调度所有已注册任务。
   * CRITICAL 任务串行等待完成后 run() 才返回（阻塞首屏前）。
   * HIGH / NORMAL / LOW 任务异步调度，不阻塞 run() 返回。
   */
  async run(): Promise<void> {
    if (this.hasRun) {
      console.warn(`${TAG} run() 被重复调用，跳过`);
      return;
    }
    this.hasRun = true;
    const monitor = PerformanceMonitor.getInstance();
    monitor.markStart('startup_optimizer_total');

    // 按优先级分桶
    const byPriority: Map<TaskPriority, StartupTask[]> = new Map([
      [TaskPriority.CRITICAL, []],
      [TaskPriority.HIGH, []],
      [TaskPriority.NORMAL, []],
      [TaskPriority.LOW, []],
    ]);
    for (const t of this.tasks) {
      byPriority.get(t.priority)!.push(t);
    }

    // CRITICAL：串行等待（顺序敏感：Prefs → DB → Stores → Theme）
    const criticalTasks = byPriority.get(TaskPriority.CRITICAL)!;
    for (const task of criticalTasks) {
      await this.runTask(task);
    }

    monitor.markEnd('first_frame'); // CRITICAL 完成即标记 first_frame 计算基准

    // HIGH：立即异步触发（不等待）
    const highTasks = byPriority.get(TaskPriority.HIGH)!;
    Promise.resolve().then(async () => {
      for (const task of highTasks) {
        await this.runTask(task);
      }
    }).catch((err: Error) => {
      console.warn(`${TAG} HIGH batch error: ${err.message}`);
    });

    // NORMAL：100ms 后
    const normalTasks = byPriority.get(TaskPriority.NORMAL)!;
    setTimeout(() => {
      (async () => {
        for (const task of normalTasks) {
          await this.runTask(task);
        }
      })().catch((err: Error) => {
        console.warn(`${TAG} NORMAL batch error: ${err.message}`);
      });
    }, PRIORITY_DELAY[TaskPriority.NORMAL]);

    // LOW：1000ms 后
    const lowTasks = byPriority.get(TaskPriority.LOW)!;
    setTimeout(() => {
      (async () => {
        for (const task of lowTasks) {
          await this.runTask(task);
        }
        // 所有任务完成后打印摘要
        this.printSummary();
      })().catch((err: Error) => {
        console.warn(`${TAG} LOW batch error: ${err.message}`);
      });
    }, PRIORITY_DELAY[TaskPriority.LOW]);

    monitor.markEnd('startup_optimizer_total');
  }

  // ---- 查询 ----

  /** 获取所有任务执行结果（调试用） */
  getResults(): TaskResult[] {
    return this.results.slice();
  }

  // ---- 内部 ----

  private async runTask(task: StartupTask): Promise<void> {
    const start = Date.now();
    try {
      if (task.timeoutMs !== undefined) {
        await this.withTimeout(task.fn(), task.timeoutMs, task.name);
      } else {
        await Promise.resolve(task.fn());
      }
      const duration = Date.now() - start;
      this.results.push({ name: task.name, priority: task.priority, durationMs: duration });
      console.info(`${TAG} [${TaskPriority[task.priority]}] ${task.name} done ${duration}ms`);
    } catch (err) {
      const duration = Date.now() - start;
      const msg = (err as Error).message;
      this.results.push({ name: task.name, priority: task.priority, durationMs: duration, error: msg });
      // 任务失败不崩溃启动，只打 warn
      console.warn(`${TAG} [${TaskPriority[task.priority]}] ${task.name} failed after ${duration}ms: ${msg}`);
    }
  }

  private withTimeout(
    fn: Promise<void> | void,
    ms: number,
    name: string,
  ): Promise<void> {
    if (!(fn instanceof Promise)) return Promise.resolve();
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        console.warn(`${TAG} task timeout: ${name} > ${ms}ms`);
        resolve(); // 超时不 reject，继续后续任务
      }, ms);
      fn.then(() => { clearTimeout(timer); resolve(); })
        .catch((err: Error) => { clearTimeout(timer); reject(err); });
    });
  }

  private printSummary(): void {
    const total = this.results.reduce((s, r) => s + r.durationMs, 0);
    const failed = this.results.filter(r => r.error !== undefined);
    console.info(
      `${TAG} startup complete: ${this.results.length} tasks, total=${total}ms, failed=${failed.length}`,
    );
    if (failed.length > 0) {
      for (const r of failed) {
        console.warn(`${TAG}  FAILED: ${r.name} — ${r.error}`);
      }
    }
  }
}
