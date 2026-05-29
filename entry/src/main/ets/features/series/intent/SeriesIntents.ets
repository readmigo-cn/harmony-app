// L3 Feature - Series - Intent
import type { Intent } from '../../../core/intent/Intent';

export type LoadSeriesListIntent = Intent<'series.loadList', Record<string, never>>;
export type OpenSeriesDetailIntent = Intent<'series.openDetail', { seriesId: string }>;
export type LoadSeriesReadingProgressIntent = Intent<'series.loadReadingProgress', { seriesId: string }>;

export type SeriesIntent =
  | LoadSeriesListIntent
  | OpenSeriesDetailIntent
  | LoadSeriesReadingProgressIntent;

export type SeriesIntentKind = SeriesIntent['kind'];

export const SERIES_INTENT_KINDS: SeriesIntentKind[] = [
  'series.loadList',
  'series.openDetail',
  'series.loadReadingProgress',
];

function makeKey(kind: string, extra: string): string {
  return `${kind}:${extra}:${Date.now()}`;
}

export function makeLoadSeriesListIntent(): LoadSeriesListIntent {
  return {
    kind: 'series.loadList',
    payload: {},
    idempotencyKey: makeKey('series.loadList', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeOpenSeriesDetailIntent(seriesId: string): OpenSeriesDetailIntent {
  return {
    kind: 'series.openDetail',
    payload: { seriesId },
    idempotencyKey: makeKey('series.openDetail', seriesId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadSeriesReadingProgressIntent(seriesId: string): LoadSeriesReadingProgressIntent {
  return {
    kind: 'series.loadReadingProgress',
    payload: { seriesId },
    idempotencyKey: makeKey('series.loadReadingProgress', seriesId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}
