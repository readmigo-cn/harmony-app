/**
 * CnConfig — CN-compliance runtime constants (W6).
 *
 * Values are sourced from BuildProfile at compile time or overridden by
 * RemoteConfig at runtime. Any value still containing '_PLACEHOLDER_' is
 * detected by check-release-readiness.sh as missing and will fail the gate.
 *
 * Usage:
 *   import { CnConfig } from '../../core/config/CnConfig';
 *   AgcCrashReporter.init(CnConfig.AGC_APP_ID);
 */

/** Sensors Analytics data-import endpoint (CN data-residency node). */
export const SA_SERVER_URL: string =
  typeof (globalThis as Record<string, unknown>)['BUILD_SA_SERVER_URL'] === 'string'
    ? (globalThis as Record<string, unknown>)['BUILD_SA_SERVER_URL'] as string
    : '_PLACEHOLDER_SA_SERVER_URL_';

/** Sensors Analytics project name registered in the SA console. */
export const SA_PROJECT_NAME: string =
  typeof (globalThis as Record<string, unknown>)['BUILD_SA_PROJECT_NAME'] === 'string'
    ? (globalThis as Record<string, unknown>)['BUILD_SA_PROJECT_NAME'] as string
    : 'readmigo_harmony';

/** AGC App ID from AppGallery Connect console (numeric string). */
export const AGC_APP_ID: string =
  typeof (globalThis as Record<string, unknown>)['BUILD_AGC_APP_ID'] === 'string'
    ? (globalThis as Record<string, unknown>)['BUILD_AGC_APP_ID'] as string
    : '_PLACEHOLDER_AGC_APP_ID_';

/**
 * Sentry DSN. Not used in the CN-primary build but kept for the dual-rail
 * crash reporter so the same binary can run in any region.
 */
export const SENTRY_DSN: string =
  typeof (globalThis as Record<string, unknown>)['BUILD_SENTRY_DSN'] === 'string'
    ? (globalThis as Record<string, unknown>)['BUILD_SENTRY_DSN'] as string
    : 'https://_PLACEHOLDER_@sentry.io/_PLACEHOLDER_';

/** Sentry release environment ('production' | 'staging'). */
export const SENTRY_ENV: string =
  typeof (globalThis as Record<string, unknown>)['BUILD_SENTRY_ENV'] === 'string'
    ? (globalThis as Record<string, unknown>)['BUILD_SENTRY_ENV'] as string
    : 'production';

/**
 * WeChat AppID registered in the WeChat Open Platform.
 * Required for WeChat OAuth on HarmonyOS.
 */
export const WECHAT_APP_ID: string =
  typeof (globalThis as Record<string, unknown>)['BUILD_WECHAT_APP_ID'] === 'string'
    ? (globalThis as Record<string, unknown>)['BUILD_WECHAT_APP_ID'] as string
    : '_PLACEHOLDER_WECHAT_APP_ID_';
