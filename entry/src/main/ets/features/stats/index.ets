// features/stats public surface
export { StatsPage } from './pages/StatsPage';
export { BookStatsDetailPage } from './pages/BookStatsDetailPage';
export { makeLoadOverviewIntent, makeLoadDailyIntent, makeOpenBookDetailIntent } from './intent/StatsIntents';
export type { StatsData, StatsState } from './viewmodel/StatsViewModel';
