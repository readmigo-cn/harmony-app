// L2 Feature - AnnualReport - Service
import { AnnualReportApi } from '../../../api/annual-report/AnnualReportApi';
import type {
  AnnualReport,
  AnnualReportGenerationStatus,
  AnnualReportHistoryEntry,
  AnnualReportShareResult,
} from '../../../api/annual-report/AnnualReportApi';

export type { AnnualReport, AnnualReportGenerationStatus, AnnualReportHistoryEntry, AnnualReportShareResult };

export class AnnualReportService {
  static async loadReport(year: number): Promise<AnnualReport> {
    return AnnualReportApi.getReport(year);
  }

  static async loadStatus(year: number): Promise<AnnualReportGenerationStatus> {
    return AnnualReportApi.getStatus(year);
  }

  static async regenerate(year: number): Promise<AnnualReportGenerationStatus> {
    return AnnualReportApi.regenerate(year);
  }

  static async share(year: number): Promise<AnnualReportShareResult> {
    return AnnualReportApi.share(year);
  }

  static async loadHistory(): Promise<AnnualReportHistoryEntry[]> {
    return AnnualReportApi.getHistory();
  }
}
