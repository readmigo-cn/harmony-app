/**
 * SentryClient —— W18-C3 Sentry 适配（出海版本 / AGC 备份通道）。
 *
 * 现状：
 *   - 社区项目 `@sentry/harmony` 还在早期版本，官方未发布稳定 ArkTS SDK
 *   - 当前以 mock 实现：保留 captureException / captureMessage / addBreadcrumb 与官方一致的接口
 *   - Phase 4 切到 `import * as Sentry from '@sentry/harmony'`
 *
 * Org 信息：见 ~/.claude/projects/-Users-HONGBGU-Documents-readmigo-repos/memory/MEMORY.md
 *   - DSN 来自后端配置，不要硬编码
 *
 * 与 AGC 的关系：
 *   - CrashHandler 双轨分发；同一异常既走 AGC 又走 Sentry
 *   - Sentry 的优势在 release tracking + breadcrumb 时间线
 */

const TAG = 'SentryClient';

export type SentryLevel = 'fatal' | 'error' | 'warning' | 'info' | 'debug';

export interface SentryBreadcrumb {
  category: string;          // 例如 'navigation' / 'http' / 'ui.click'
  message: string;
  level?: SentryLevel;
  data?: Record<string, string | number | boolean>;
  timestamp?: number;        // ms
}

export interface SentryEvent {
  name: string;
  message: string;
  stack?: string;
  level: SentryLevel;
  tags: Record<string, string>;
  extra: Record<string, string>;
  breadcrumbs: SentryBreadcrumb[];
  timestamp: number;
  release?: string;
  environment?: string;
  user?: { id?: string; email?: string };
}

const BREADCRUMB_LIMIT = 100;

export class SentryClient {
  private static initialized: boolean = false;
  private static dsn: string = '';
  private static environment: string = 'production';
  private static release: string = '';
  private static breadcrumbs: SentryBreadcrumb[] = [];
  private static tags: Record<string, string> = {};
  private static user: { id?: string; email?: string } = {};

  /** 初始化：在 EntryAbility.onCreate 调用 */
  static init(dsn: string, environment: string = 'production', release?: string): void {
    if (SentryClient.initialized) return;
    SentryClient.dsn = dsn;
    SentryClient.environment = environment;
    if (release) SentryClient.release = release;
    SentryClient.initialized = true;
    console.info(`${TAG} init done, env=${environment}`);
  }

  static setUser(user: { id?: string; email?: string }): void {
    SentryClient.user = user;
  }

  static setTag(key: string, value: string): void {
    SentryClient.tags[key] = value;
  }

  /** 记一条面包屑（用户行为时间线，崩溃时一并上报） */
  static addBreadcrumb(crumb: SentryBreadcrumb): void {
    const merged: SentryBreadcrumb = {
      category: crumb.category,
      message: crumb.message,
      level: crumb.level ?? 'info',
      data: crumb.data,
      timestamp: crumb.timestamp ?? Date.now(),
    };
    SentryClient.breadcrumbs.push(merged);
    if (SentryClient.breadcrumbs.length > BREADCRUMB_LIMIT) {
      SentryClient.breadcrumbs.shift();
    }
  }

  /** 上报异常对象 */
  static captureException(error: Error, extra?: Record<string, string>): void {
    if (!SentryClient.initialized) {
      console.warn(`${TAG} captureException before init`);
      return;
    }
    const ev: SentryEvent = {
      name: error.name ?? 'Error',
      message: error.message ?? '',
      stack: error.stack ?? '',
      level: 'error',
      tags: SentryClient.cloneTags(),
      extra: extra ?? {},
      breadcrumbs: SentryClient.breadcrumbs.slice(),
      timestamp: Date.now(),
      release: SentryClient.release,
      environment: SentryClient.environment,
      user: SentryClient.user,
    };
    SentryClient.dispatch(ev);
  }

  /** 上报一条消息（非异常） */
  static captureMessage(message: string, level: SentryLevel = 'info', extra?: Record<string, string>): void {
    if (!SentryClient.initialized) return;
    const ev: SentryEvent = {
      name: 'Message',
      message,
      level,
      tags: SentryClient.cloneTags(),
      extra: extra ?? {},
      breadcrumbs: SentryClient.breadcrumbs.slice(),
      timestamp: Date.now(),
      release: SentryClient.release,
      environment: SentryClient.environment,
      user: SentryClient.user,
    };
    SentryClient.dispatch(ev);
  }

  // ---------------- internals ----------------

  private static cloneTags(): Record<string, string> {
    const out: Record<string, string> = {};
    Object.assign(out, SentryClient.tags);
    return out;
  }

  /**
   * Mock dispatch：仅打日志。
   * Phase 4：Sentry.captureEvent(ev) → POST {dsn-derived URL}/api/{projectId}/store/
   */
  private static dispatch(ev: SentryEvent): void {
    // TODO(Phase 4): 接入 @sentry/harmony 后改为 Sentry.captureEvent(ev)
    console.warn(`${TAG} [${ev.level}] ${ev.name}: ${ev.message} (breadcrumbs=${ev.breadcrumbs.length})`);
  }
}
