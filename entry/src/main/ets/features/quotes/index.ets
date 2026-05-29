// Feature - Quotes - barrel (public surface only)
export { QuotesPage } from './pages/QuotesPage';
export { QuoteDetailPage } from './pages/QuoteDetailPage';
export { QuotesPageAdapter, QuoteDetailAdapter } from './pages/QuotesPageAdapter';
export { QuoteCard } from './components/QuoteCard';
export type { Quote } from '../../model/Quote';
export type { QuotesData, QuotesState } from './viewmodel/QuotesViewModel';
export type { QuotesIntent, QuotesIntentKind } from './intent/QuotesIntents';
export {
  QUOTES_INTENT_KINDS,
  makeLoadDailyIntent,
  makeLoadTrendingIntent,
  makeLoadRandomIntent,
  makeLoadFavoritesIntent,
  makeOpenDetailIntent,
  makeLikeQuoteIntent,
  makeShareQuoteIntent,
} from './intent/QuotesIntents';
