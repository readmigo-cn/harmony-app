/**
 * AgcCrashReporter — W6 华为 AGC Crash 适配（真实 SDK + 本地文件降级）。
 *
 * SDK 策略：
 *   - 优先 import @kit.CrashKit（HarmonyOS NEXT）
 *   - 降级尝试 @hms.agconnect-crash
 *   - 均不可用时写本地 Preferences 文件
 *
 * 与 SentryClient 的关系：
 *   - CrashHandler 同时把异常分发给二者 → 双轨上报
 */

import { PreferencesManager } from '../persistence/PreferencesManager';

// Try real AGC Crash SDK
let crashSdk: {
  setUserId: (userId: string) => void;
  recordError: (name: string, message: string, stack: string) => void;
  setCustomKey: (key: string, value: string) => void;
  enableCrashCollection: (enable: boolean) => void;
} | null = null;

try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  crashSdk = require('@kit.CrashKit') as typeof crashSdk;
} catch (_e1) {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    crashSdk = require('@hms.agconnect-crash') as typeof crashSdk;
  } catch (_e2) {
    console.warn('AgcCrashReporter: AGC Crash SDK not available, using local file fallback');
  }
}

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
    if (crashSdk) {
      try {
        crashSdk.enableCrashCollection(true);
        console.info(`${TAG} real SDK init done, appId=${appId}`);
      } catch (e) {
        console.warn(`${TAG} SDK enableCrashCollection failed: ${(e as Error).message}`);
      }
    }
    AgcCrashReporter.installGlobalHandlers();
    AgcCrashReporter.initialized = true;
    console.info(`${TAG} init done, appId=${appId}, sdkMode=${crashSdk !== null}`);
  }

  /** 设置当前 userId，崩溃归因到具体用户 */
  static setUserId(userId: string): void {
    AgcCrashReporter.userId = userId;
    if (crashSdk) {
      try {
        crashSdk.setUserId(userId);
      } catch (_) {}
    }
  }

  /** 添加自定义键值，崩溃发生时一并上报（如：当前页面、当前 bookId） */
  static addCrashAttachment(key: string, value: string): void {
    AgcCrashReporter.attachments.set(key, value);
    if (crashSdk) {
      try {
        crashSdk.setCustomKey(key, value);
      } catch (_) {}
    }
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

  private static async dispatch(record: CrashRecord): Promise<void> {
    // 1) Real SDK upload (if available)
    if (crashSdk) {
      try {
        crashSdk.recordError(record.name, record.message, record.stack);
      } catch (e) {
        console.warn(`${TAG} SDK recordError failed: ${(e as Error).message}`);
      }
    }

    // 2) Local fallback: stage for restart re-send
    await PreferencesManager.setString(PENDING_CRASH_KEY, JSON.stringify(record));

    // 3) Append to local rolling log (retain last 64KB for on-device debug)
    const prev = await PreferencesManager.getString(CRASH_LOG_KEY, '');
    const line = `[${new Date(record.timestamp).toISOString()}] ${record.name}: ${record.message}\n${record.stack}\n---\n`;
    const next = (prev + line).slice(-MAX_LOG_BYTES);
    await PreferencesManager.setString(CRASH_LOG_KEY, next);
    console.warn(`${TAG} captured ${record.name}: ${record.message}`);
  }
}
