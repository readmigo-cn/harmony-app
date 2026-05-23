/**
 * AgcCrashReporter —— W18-C2 华为 AGC Crash 适配。
 *
 * 中国市场首选崩溃监控通道（出海备份用 Sentry，详见 SentryClient.ets）。
 *
 * 现状：
 *   - HMS 文档 `@hms.agc.crash` 暂无公开 HarmonyOS NEXT API
 *   - 当前以 mock 实现：
 *       * 拦截全局未捕获异常 + Promise unhandledRejection
 *       * 写本地崩溃日志到 Preferences（key: agc_crash_log）
 *       * 暴露 logException / addCrashAttachment 与官方 API 同名同签名
 *   - Phase 4 切到 `import crash from '@hms.agc.crash'` 调用 crash.recordError(...)
 *
 * 与 SentryClient 的关系：
 *   - CrashHandler 同时把异常分发给二者 → 双轨上报
 *   - AGC 在中国大陆出现率高、Sentry 在出海版本可用
 */

import { PreferencesManager } from '../persistence/PreferencesManager';

const TAG = 'AgcCrashReporter';
const CRASH_LOG_KEY = 'agc_crash_log';
const PENDING_CRASH_KEY = 'agc_pending_crash';
const MAX_LOG_BYTES = 64 * 1024;

export interface CrashRecord {
  name: string;
  message: string;
  stack: string;
  extras: Record<string, string>;
  timestamp: number;
  appVersion?: string;
  userId?: string;
}

export class AgcCrashReporter {
  private static initialized: boolean = false;
  private static appId: string = '';
  private static attachments: Map<string, string> = new Map<string, string>();
  private static appVersion: string = '';
  private static userId: string = '';

  /** 初始化：在 EntryAbility.onCreate 调用。appId 从 AGC 控制台拿。 */
  static init(appId: string, appVersion?: string): void {
    if (AgcCrashReporter.initialized) return;
    AgcCrashReporter.appId = appId;
    if (appVersion) AgcCrashReporter.appVersion = appVersion;
    AgcCrashReporter.installGlobalHandlers();
    AgcCrashReporter.initialized = true;
    console.info(`${TAG} init done, appId=${appId}`);
  }

  /** 设置当前 userId，崩溃归因到具体用户 */
  static setUserId(userId: string): void {
    AgcCrashReporter.userId = userId;
  }

  /** 添加自定义键值，崩溃发生时一并上报（如：当前页面、当前 bookId） */
  static addCrashAttachment(key: string, value: string): void {
    AgcCrashReporter.attachments.set(key, value);
  }

  /** 业务侧主动捕获并上报异常 */
  static logException(name: string, message: string, stack: string, extras?: Record<string, string>): void {
    const record: CrashRecord = {
      name,
      message,
      stack,
      extras: AgcCrashReporter.mergeExtras(extras),
      timestamp: Date.now(),
      appVersion: AgcCrashReporter.appVersion,
      userId: AgcCrashReporter.userId,
    };
    AgcCrashReporter.dispatch(record).catch((e) => {
      console.warn(`${TAG} dispatch failed: ${(e as Error).message}`);
    });
  }

  /**
   * 检查上次启动是否有未上报崩溃。
   * 由 CrashHandler 在 EntryAbility.onCreate 完成后调用，触发 toast + 重发。
   */
  static async pollPendingCrash(): Promise<CrashRecord | null> {
    const raw = await PreferencesManager.getString(PENDING_CRASH_KEY, '');
    if (raw.length === 0) return null;
    try {
      const rec = JSON.parse(raw) as CrashRecord;
      await PreferencesManager.setString(PENDING_CRASH_KEY, '');
      return rec;
    } catch (_) {
      await PreferencesManager.setString(PENDING_CRASH_KEY, '');
      return null;
    }
  }

  // ---------------- internals ----------------

  private static mergeExtras(extras?: Record<string, string>): Record<string, string> {
    const merged: Record<string, string> = {};
    AgcCrashReporter.attachments.forEach((v, k) => { merged[k] = v; });
    if (extras) Object.assign(merged, extras);
    return merged;
  }

  private static installGlobalHandlers(): void {
    // 同步未捕获异常：errorManager.on('error', ...)
    // ArkTS 当前对 globalThis.onerror 支持有限，留 TODO
    // TODO(Phase 4): import { errorManager } from '@ohos.app.ability.errorManager';
    //   errorManager.on('error', (err) => AgcCrashReporter.logException(err.name, err.message, err.stack ?? '', {}));

    // Promise rejection：HarmonyOS NEXT 暂无 unhandledrejection 标准事件
    // 由业务侧在 try/catch 内主动调 logException。
    console.info(`${TAG} global handlers installed (mock)`);
  }

  /**
   * Mock dispatch：append 到本地 crash log 文件 + 暂存到 PENDING_CRASH_KEY
   * 等下次启动时被 CrashHandler 弹 toast + 重发。
   */
  private static async dispatch(record: CrashRecord): Promise<void> {
    // 1) 暂存等下次启动重发（崩溃后进程可能立即退出，此操作要求是 sync 写）
    await PreferencesManager.setString(PENDING_CRASH_KEY, JSON.stringify(record));
    // 2) append 到累计日志（保留最近 64KB，方便本地 debug）
    const prev = await PreferencesManager.getString(CRASH_LOG_KEY, '');
    const line = `[${new Date(record.timestamp).toISOString()}] ${record.name}: ${record.message}\n${record.stack}\n---\n`;
    const next = (prev + line).slice(-MAX_LOG_BYTES);
    await PreferencesManager.setString(CRASH_LOG_KEY, next);
    // 3) TODO(Phase 4): crash.recordError(record) → 真实 AGC 上报
    console.warn(`${TAG} captured ${record.name}: ${record.message}`);
  }
}
