// L3 Feature - AnnualReport - Intent
//
// Annual-report intent types are defined module-locally — they are NOT added to
// the AnyIntent union in core/intent/Intent.ets (that is W1's domain).
// The IntentBus accepts any Intent<K, P>, so these work without being in
// the union.

import type { Intent } from '../../../core/intent/Intent';

// ── Annual-report intent types ──────────────────────────────────────

export type AnnualReportLoadIntent = Intent<'annualReport.load', { year: number }>;
export type AnnualReportLoadStatusIntent = Intent<'annualReport.loadStatus', { year: number }>;
export type AnnualReportRegenerateIntent = Intent<'annualReport.regenerate', { year: number }>;
export type AnnualReportShareIntent = Intent<'annualReport.share', { year: number }>;
export type AnnualReportLoadHistoryIntent = Intent<'annualReport.loadHistory', Record<string, never>>;

export type AnnualReportIntent =
  | AnnualReportLoadIntent
  | AnnualReportLoadStatusIntent
  | AnnualReportRegenerateIntent
  | AnnualReportShareIntent
  | AnnualReportLoadHistoryIntent;

export type AnnualReportIntentKind = AnnualReportIntent['kind'];

export const ANNUAL_REPORT_INTENT_KINDS: AnnualReportIntentKind[] = [
  'annualReport.load',
  'annualReport.loadStatus',
  'annualReport.regenerate',
  'annualReport.share',
  'annualReport.loadHistory',
];

function makeKey(kind: string, extra: string): string {
  return `${kind}:${extra}:${Date.now()}`;
}

export function makeAnnualReportLoadIntent(year: number): AnnualReportLoadIntent {
  return {
    kind: 'annualReport.load',
    payload: { year },
    idempotencyKey: makeKey('annualReport.load', String(year)),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeAnnualReportLoadStatusIntent(year: number): AnnualReportLoadStatusIntent {
  return {
    kind: 'annualReport.loadStatus',
    payload: { year },
    idempotencyKey: makeKey('annualReport.loadStatus', String(year)),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeAnnualReportRegenerateIntent(year: number): AnnualReportRegenerateIntent {
  return {
    kind: 'annualReport.regenerate',
    payload: { year },
    idempotencyKey: makeKey('annualReport.regenerate', String(year)),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeAnnualReportShareIntent(year: number): AnnualReportShareIntent {
  return {
    kind: 'annualReport.share',
    payload: { year },
    idempotencyKey: makeKey('annualReport.share', String(year)),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeAnnualReportLoadHistoryIntent(): AnnualReportLoadHistoryIntent {
  return {
    kind: 'annualReport.loadHistory',
    payload: {},
    idempotencyKey: makeKey('annualReport.loadHistory', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}
