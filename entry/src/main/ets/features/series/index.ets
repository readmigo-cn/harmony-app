// L4 Feature - Series - barrel
export { SeriesListPage } from './pages/SeriesListPage';
export { SeriesDetailPage } from './pages/SeriesDetailPage';
export { SeriesListPageAdapter } from './pages/SeriesListPageAdapter';
export type { SeriesIntent, SeriesIntentKind } from './intent/SeriesIntents';
export {
  SERIES_INTENT_KINDS,
  makeLoadSeriesListIntent,
  makeOpenSeriesDetailIntent,
  makeLoadSeriesReadingProgressIntent,
} from './intent/SeriesIntents';
export type { SeriesData, SeriesState } from './viewmodel/SeriesViewModel';
