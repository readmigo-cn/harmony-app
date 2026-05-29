// L2 Feature - Stats - Service
import { HttpClient } from '../../../api/client/HttpClient';

export interface OverviewData {
  readonly booksRead: number;
  readonly minutesRead: number;
  readonly currentStreak: number;
}

export interface DailyPoint {
  readonly date: string;
  readonly minutes: number;
}

export interface TrendPoint {
  readonly week: string;
  readonly books: number;
}

export interface ProgressEntry {
  readonly bookId: string;
  readonly percent: number;
}

export interface BookStatsData {
  readonly bookId: string;
  readonly sessions: number;
  readonly chapters: number;
  readonly durationMs: number;
}

export type DailyRange = '7d' | '30d' | 'all';

export class StatsService {
  static readonly shared: StatsService = new StatsService();

  async loadOverview(): Promise<OverviewData> {
    return HttpClient.get<OverviewData>('/analytics/overview');
  }

  async loadDaily(range: DailyRange): Promise<DailyPoint[]> {
    return HttpClient.get<DailyPoint[]>('/analytics/daily', { range });
  }

  async loadTrend(): Promise<TrendPoint[]> {
    return HttpClient.get<TrendPoint[]>('/analytics/reading-trend');
  }

  async loadProgress(): Promise<ProgressEntry[]> {
    return HttpClient.get<ProgressEntry[]>('/analytics/reading-progress');
  }

  async loadInsights(): Promise<string[]> {
    return HttpClient.get<string[]>('/analytics/insights');
  }

  async loadBookStats(bookId: string): Promise<BookStatsData> {
    return HttpClient.get<BookStatsData>(`/analytics/book/${bookId}`);
  }
}
