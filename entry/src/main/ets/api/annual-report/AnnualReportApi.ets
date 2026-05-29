// L2 - API - AnnualReport
import { HttpClient } from '../../api/client/HttpClient';

export interface AnnualReportSlideData {
  kind: string;
  title: string;
  value: string;
  illustration?: string;
}

export interface AnnualReport {
  year: number;
  booksRead: number;
  minutesRead: number;
  topAuthor: string;
  topGenre: string;
  narrative: string;
  slides: AnnualReportSlideData[];
}

export interface AnnualReportGenerationStatus {
  year: number;
  status: 'pending' | 'inProgress' | 'done' | 'failed';
  message?: string;
}

export interface AnnualReportHistoryEntry {
  year: number;
  available: boolean;
}

export interface AnnualReportShareResult {
  shareUrl: string;
}

export class AnnualReportApi {
  static getReport(year: number): Promise<AnnualReport> {
    return HttpClient.get<AnnualReport>(`/api/v1/annual-report/${year}`);
  }

  static getStatus(year: number): Promise<AnnualReportGenerationStatus> {
    return HttpClient.get<AnnualReportGenerationStatus>(`/api/v1/annual-report/${year}/status`);
  }

  static regenerate(year: number): Promise<AnnualReportGenerationStatus> {
    return HttpClient.post<AnnualReportGenerationStatus>(`/api/v1/annual-report/${year}/regenerate`, {});
  }

  static share(year: number): Promise<AnnualReportShareResult> {
    return HttpClient.post<AnnualReportShareResult>(`/api/v1/annual-report/${year}/share`, {});
  }

  static getHistory(): Promise<AnnualReportHistoryEntry[]> {
    return HttpClient.get<AnnualReportHistoryEntry[]>('/api/v1/annual-report/history');
  }
}
