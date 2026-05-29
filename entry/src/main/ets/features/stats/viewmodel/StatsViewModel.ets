// L3 Feature - Stats - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import { StatsService } from '../service/StatsService';
import type { OverviewData, DailyPoint, TrendPoint, ProgressEntry, BookStatsData } from '../service/StatsService';
import { STATS_INTENT_KINDS } from '../intent/StatsIntents';
import type { LoadDailyIntent, OpenBookDetailIntent } from '../intent/StatsIntents';

export interface StatsData {
  readonly overview?: OverviewData;
  readonly daily?: DailyPoint[];
  readonly trend?: TrendPoint[];
  readonly progress?: ProgressEntry[];
  readonly insights?: string[];
  readonly selectedBookStats?: BookStatsData;
}

export type StatsState = ViewModelState<StatsData>;

export class StatsViewModel extends FeatureViewModel<StatsData> {
  readonly kind = 'stats';

  constructor() {
    super(STATS_INTENT_KINDS as never);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    switch (intent.kind) {
      case 'stats.loadOverview':
        await this.handleLoadOverview();
        break;
      case 'stats.loadDaily':
        await this.handleLoadDaily(intent as unknown as LoadDailyIntent);
        break;
      case 'stats.loadTrend':
        await this.handleLoadTrend();
        break;
      case 'stats.loadProgress':
        await this.handleLoadProgress();
        break;
      case 'stats.loadInsights':
        await this.handleLoadInsights();
        break;
      case 'stats.openBookDetail':
        await this.handleOpenBookDetail(intent as unknown as OpenBookDetailIntent);
        break;
      default:
        break;
    }
  }

  private currentData(): StatsData {
    return this.state.status === 'data' ? this.state.data : {};
  }

  private async handleLoadOverview(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const overview = await StatsService.shared.loadOverview();
      this.state = { status: 'data', data: { ...this.currentData(), overview } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_overview_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadDaily(intent: LoadDailyIntent): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const daily = await StatsService.shared.loadDaily(intent.payload.range);
      this.state = { status: 'data', data: { ...this.currentData(), daily } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_daily_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadTrend(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const trend = await StatsService.shared.loadTrend();
      this.state = { status: 'data', data: { ...this.currentData(), trend } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_trend_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadProgress(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const progress = await StatsService.shared.loadProgress();
      this.state = { status: 'data', data: { ...this.currentData(), progress } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_progress_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadInsights(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const insights = await StatsService.shared.loadInsights();
      this.state = { status: 'data', data: { ...this.currentData(), insights } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_insights_failed', message: (e as Error).message } };
    }
  }

  private async handleOpenBookDetail(intent: OpenBookDetailIntent): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const selectedBookStats = await StatsService.shared.loadBookStats(intent.payload.bookId);
      this.state = { status: 'data', data: { ...this.currentData(), selectedBookStats } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_book_stats_failed', message: (e as Error).message } };
    }
  }
}
