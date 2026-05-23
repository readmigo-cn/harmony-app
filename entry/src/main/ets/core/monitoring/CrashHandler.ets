/**
 * CrashHandler —— W18-C2 + C3 崩溃统一入口。
 *
 * 责任：
 *   1) 双轨上报：所有 capture 同时分发到 AGC + Sentry
 *   2) global error boundary：拦截 errorManager 全局异常 + 业务侧未 catch 的 Promise rejection
 *   3) 崩溃恢复 UI：上次启动如有 pending crash，弹 toast 提示「已重新启动，崩溃报告已发送」
 *   4) 与 Analytics 联动：每次 capture 同时打 'crash_captured' 事件，便于 PostHog/神策 看趋势
 *
 * 使用：
 *   - EntryAbility.onCreate 调 CrashHandler.init()
 *   - 业务侧主动捕获：CrashHandler.capture(error, { page: 'reader', book_id: 'xxx' })
 */

import { AgcCrashReporter, CrashRecord } from './AgcCrashReporter';
import { SentryClient } from './SentryClient';
import { Analytics } from '../analytics/AnalyticsProvider';
import { SaEvents } from '../analytics/SensorsAnalytics';
import promptAction from '@ohos.promptAction';
import errorManager from '@ohos.app.ability.errorManager';

const TAG = 'CrashHandler';

export interface CrashContext {
  page?: string;
  bookId?: string;
  feature?: string;
  [k: string]: string | undefined;
}

export class CrashHandler {
  private static initialized: boolean = false;
  private static observerId: number = -1;

  /** 在 EntryAbility.onCreate 调，先于业务初始化 */
  static init(): void {
    if (CrashHandler.initialized) return;
    CrashHandler.installGlobalHandler();
    CrashHandler.initialized = true;
    console.info(`${TAG} init done`);
  }

  /** 启动后调一次：检测上次启动是否崩溃，如果是 → toast + 重发到云端 */
  static async checkPendingCrashOnLaunch(): Promise<void> {
    try {
      const pending = await AgcCrashReporter.pollPendingCrash();
      if (!pending) return;
      // 1) 友好提示：避免吓到用户，只 toast 一次
      try {
        promptAction.showToast({ message: '上次崩溃已自动上报，感谢反馈', duration: 2500 });
      } catch (_) {}
      // 2) 重发到 Sentry（AGC 已经在崩溃时本地落了一份，Sentry 这次补发）
      const err = new Error(pending.message);
      err.name = pending.name;
      err.stack = pending.stack;
      SentryClient.captureException(err, pending.extras);
      // 3) 打一条业务事件
      Analytics.track('crash_recovered', {
        crash_name: pending.name,
        crash_message: pending.message.slice(0, 200),
      });
    } catch (e) {
      console.warn(`${TAG} checkPendingCrash failed: ${(e as Error).message}`);
    }
  }

  /** 业务侧主动捕获并双轨上报 */
  static capture(error: Error, context?: CrashContext): void {
    const extras: Record<string, string> = {};
    if (context) {
      Object.keys(context).forEach((k) => {
        const v = context[k];
        if (typeof v === 'string') extras[k] = v;
      });
    }
    // 1) AGC
    AgcCrashReporter.logException(
      error.name ?? 'Error',
      error.message ?? '',
      error.stack ?? '',
      extras,
    );
    // 2) Sentry
    SentryClient.captureException(error, extras);
    // 3) Analytics 趋势事件
    Analytics.track('crash_captured', {
      crash_name: error.name ?? 'Error',
      crash_message: (error.message ?? '').slice(0, 200),
      page: context?.page ?? null,
    });
  }

  /** 记面包屑（自动 forward 到 Sentry）；导航 / 网络请求 / 关键 UI 操作处调用 */
  static breadcrumb(category: string, message: string, data?: Record<string, string | number | boolean>): void {
    SentryClient.addBreadcrumb({ category, message, data });
  }

  // ---------------- internals ----------------

  private static installGlobalHandler(): void {
    // HarmonyOS errorManager.on('error') 拦截 ArkTS 未捕获异常
    try {
      const observer: errorManager.ErrorObserver = {
        onUnhandledException: (errMsg: string) => {
          // errMsg 是单 string，无 stack。构造一个 Error 透传
          const err = new Error(errMsg);
          err.name = 'UnhandledException';
          CrashHandler.capture(err, { source: 'errorManager' });
        },
      };
      CrashHandler.observerId = errorManager.on('error', observer);
      console.info(`${TAG} errorManager observer registered, id=${CrashHandler.observerId}`);
    } catch (e) {
      // 部分 SDK 版本签名不兼容，降级到只走业务主动捕获
      console.warn(`${TAG} errorManager.on failed: ${(e as Error).message}`);
    }
  }
}
