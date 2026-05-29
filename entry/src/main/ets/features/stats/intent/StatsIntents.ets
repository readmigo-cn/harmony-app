// L3 Feature - Stats - Intent
import type { Intent } from '../../../core/intent/Intent';
import type { DailyRange } from '../service/StatsService';

export type LoadOverviewIntent = Intent<'stats.loadOverview', Record<string, never>>;
export type LoadDailyIntent = Intent<'stats.loadDaily', { range: DailyRange }>;
export type LoadTrendIntent = Intent<'stats.loadTrend', Record<string, never>>;
export type LoadProgressIntent = Intent<'stats.loadProgress', Record<string, never>>;
export type LoadInsightsIntent = Intent<'stats.loadInsights', Record<string, never>>;
export type OpenBookDetailIntent = Intent<'stats.openBookDetail', { bookId: string }>;

export type StatsIntent =
  | LoadOverviewIntent
  | LoadDailyIntent
  | LoadTrendIntent
  | LoadProgressIntent
  | LoadInsightsIntent
  | OpenBookDetailIntent;

export type StatsIntentKind = StatsIntent['kind'];

export const STATS_INTENT_KINDS: StatsIntentKind[] = [
  'stats.loadOverview',
  'stats.loadDaily',
  'stats.loadTrend',
  'stats.loadProgress',
  'stats.loadInsights',
  'stats.openBookDetail',
];

function makeKey(kind: string, extra: string): string {
  return `${kind}:${extra}:${Date.now()}`;
}

export function makeLoadOverviewIntent(): LoadOverviewIntent {
  return {
    kind: 'stats.loadOverview',
    payload: {},
    idempotencyKey: makeKey('stats.loadOverview', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadDailyIntent(range: DailyRange): LoadDailyIntent {
  return {
    kind: 'stats.loadDaily',
    payload: { range },
    idempotencyKey: makeKey('stats.loadDaily', range),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadTrendIntent(): LoadTrendIntent {
  return {
    kind: 'stats.loadTrend',
    payload: {},
    idempotencyKey: makeKey('stats.loadTrend', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadProgressIntent(): LoadProgressIntent {
  return {
    kind: 'stats.loadProgress',
    payload: {},
    idempotencyKey: makeKey('stats.loadProgress', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadInsightsIntent(): LoadInsightsIntent {
  return {
    kind: 'stats.loadInsights',
    payload: {},
    idempotencyKey: makeKey('stats.loadInsights', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeOpenBookDetailIntent(bookId: string): OpenBookDetailIntent {
  return {
    kind: 'stats.openBookDetail',
    payload: { bookId },
    idempotencyKey: makeKey('stats.openBookDetail', bookId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}
