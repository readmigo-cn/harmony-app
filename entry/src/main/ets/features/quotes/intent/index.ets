// L3 Feature - Quotes - Intent barrel
export type {
  QuotesIntent,
  QuotesIntentKind,
  LoadDailyQuoteIntent,
  LoadTrendingIntent,
  LoadRandomQuoteIntent,
  LoadFavoritesIntent,
  OpenQuoteDetailIntent,
  LikeQuoteIntent,
  ShareQuoteIntent,
} from './QuotesIntents';
export {
  QUOTES_INTENT_KINDS,
  makeLoadDailyIntent,
  makeLoadTrendingIntent,
  makeLoadRandomIntent,
  makeLoadFavoritesIntent,
  makeOpenDetailIntent,
  makeLikeQuoteIntent,
  makeShareQuoteIntent,
} from './QuotesIntents';
