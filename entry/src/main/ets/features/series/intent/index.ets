// L3 Feature - Series - Intent barrel
export type {
  SeriesIntent,
  SeriesIntentKind,
  LoadSeriesListIntent,
  OpenSeriesDetailIntent,
  LoadSeriesReadingProgressIntent,
} from './SeriesIntents';
export {
  SERIES_INTENT_KINDS,
  makeLoadSeriesListIntent,
  makeOpenSeriesDetailIntent,
  makeLoadSeriesReadingProgressIntent,
} from './SeriesIntents';
