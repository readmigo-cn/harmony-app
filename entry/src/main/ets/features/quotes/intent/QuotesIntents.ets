// L3 Feature - Quotes - Intent
import type { Intent } from '../../../core/intent/Intent';

export type LoadDailyQuoteIntent   = Intent<'quotes.loadDaily',     Record<string, never>>;
export type LoadTrendingIntent     = Intent<'quotes.loadTrending',  Record<string, never>>;
export type LoadRandomQuoteIntent  = Intent<'quotes.loadRandom',    Record<string, never>>;
export type LoadFavoritesIntent    = Intent<'quotes.loadFavorites', Record<string, never>>;
export type OpenQuoteDetailIntent  = Intent<'quotes.openDetail',    { quoteId: string }>;
export type LikeQuoteIntent        = Intent<'quotes.likeQuote',     { quoteId: string }>;
export type ShareQuoteIntent       = Intent<'quotes.shareQuote',    { quoteId: string }>;

export type QuotesIntent =
  | LoadDailyQuoteIntent
  | LoadTrendingIntent
  | LoadRandomQuoteIntent
  | LoadFavoritesIntent
  | OpenQuoteDetailIntent
  | LikeQuoteIntent
  | ShareQuoteIntent;

export type QuotesIntentKind = QuotesIntent['kind'];

export const QUOTES_INTENT_KINDS: QuotesIntentKind[] = [
  'quotes.loadDaily',
  'quotes.loadTrending',
  'quotes.loadRandom',
  'quotes.loadFavorites',
  'quotes.openDetail',
  'quotes.likeQuote',
  'quotes.shareQuote',
];

function makeKey(kind: string, extra: string): string {
  return `${kind}:${extra}:${Date.now()}`;
}

export function makeLoadDailyIntent(): LoadDailyQuoteIntent {
  return {
    kind: 'quotes.loadDaily',
    payload: {},
    idempotencyKey: makeKey('quotes.loadDaily', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadTrendingIntent(): LoadTrendingIntent {
  return {
    kind: 'quotes.loadTrending',
    payload: {},
    idempotencyKey: makeKey('quotes.loadTrending', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadRandomIntent(): LoadRandomQuoteIntent {
  return {
    kind: 'quotes.loadRandom',
    payload: {},
    idempotencyKey: makeKey('quotes.loadRandom', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadFavoritesIntent(): LoadFavoritesIntent {
  return {
    kind: 'quotes.loadFavorites',
    payload: {},
    idempotencyKey: makeKey('quotes.loadFavorites', ''),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeOpenDetailIntent(quoteId: string): OpenQuoteDetailIntent {
  return {
    kind: 'quotes.openDetail',
    payload: { quoteId },
    idempotencyKey: makeKey('quotes.openDetail', quoteId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLikeQuoteIntent(quoteId: string): LikeQuoteIntent {
  return {
    kind: 'quotes.likeQuote',
    payload: { quoteId },
    idempotencyKey: makeKey('quotes.likeQuote', quoteId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeShareQuoteIntent(quoteId: string): ShareQuoteIntent {
  return {
    kind: 'quotes.shareQuote',
    payload: { quoteId },
    idempotencyKey: makeKey('quotes.shareQuote', quoteId),
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}
