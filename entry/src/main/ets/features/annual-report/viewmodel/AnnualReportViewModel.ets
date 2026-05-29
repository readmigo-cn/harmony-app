// L3 Feature - AnnualReport - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState, IntentKind } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import { AnnualReportService } from '../service/AnnualReportService';
import type { AnnualReport, AnnualReportHistoryEntry } from '../service/AnnualReportService';
import { ANNUAL_REPORT_INTENT_KINDS } from '../intent/AnnualReportIntents';
import type {
  AnnualReportLoadIntent,
  AnnualReportLoadStatusIntent,
  AnnualReportRegenerateIntent,
  AnnualReportShareIntent,
} from '../intent/AnnualReportIntents';

export interface AnnualReportData {
  readonly currentYear?: number;
  readonly report?: AnnualReport;
  readonly generationStatus?: 'pending' | 'inProgress' | 'done' | 'failed';
  readonly history?: AnnualReportHistoryEntry[];
}

export type AnnualReportState = ViewModelState<AnnualReportData>;

export class AnnualReportViewModel extends FeatureViewModel<AnnualReportData> {
  readonly kind = 'annual-report';

  constructor() {
    // Annual-report kinds are not in the W1 AnyIntent union; cast required since
    // IntentBus.subscribe is keyed by IntentKind. The bus accepts any string key
    // at runtime — the cast is safe because bus dispatches by kind string only.
    super(ANNUAL_REPORT_INTENT_KINDS as unknown as IntentKind[]);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    switch (intent.kind) {
      case 'annualReport.load':
        await this.handleLoad(intent as unknown as AnnualReportLoadIntent);
        break;
      case 'annualReport.loadStatus':
        await this.handleLoadStatus(intent as unknown as AnnualReportLoadStatusIntent);
        break;
      case 'annualReport.regenerate':
        await this.handleRegenerate(intent as unknown as AnnualReportRegenerateIntent);
        break;
      case 'annualReport.share':
        await this.handleShare(intent as unknown as AnnualReportShareIntent);
        break;
      case 'annualReport.loadHistory':
        await this.handleLoadHistory();
        break;
      default:
        break;
    }
  }

  private async handleLoad(intent: AnnualReportLoadIntent): Promise<void> {
    const { year } = intent.payload;
    this.state = { status: 'loading' };
    try {
      const report = await AnnualReportService.loadReport(year);
      this.state = {
        status: 'data',
        data: { currentYear: year, report, generationStatus: 'done' },
      };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'load_failed', message: (e as Error).message },
      };
    }
  }

  private async handleLoadStatus(intent: AnnualReportLoadStatusIntent): Promise<void> {
    const { year } = intent.payload;
    try {
      const statusResult = await AnnualReportService.loadStatus(year);
      const current = this.state.status === 'data' ? this.state.data : {};
      this.state = {
        status: 'data',
        data: { ...current, currentYear: year, generationStatus: statusResult.status },
      };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'status_failed', message: (e as Error).message },
      };
    }
  }

  private async handleRegenerate(intent: AnnualReportRegenerateIntent): Promise<void> {
    const { year } = intent.payload;
    this.state = { status: 'loading' };
    try {
      const statusResult = await AnnualReportService.regenerate(year);
      this.state = {
        status: 'data',
        data: { currentYear: year, generationStatus: statusResult.status },
      };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'regenerate_failed', message: (e as Error).message },
      };
    }
  }

  private async handleShare(intent: AnnualReportShareIntent): Promise<void> {
    const { year } = intent.payload;
    try {
      await AnnualReportService.share(year);
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'share_failed', message: (e as Error).message },
      };
    }
  }

  private async handleLoadHistory(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const history = await AnnualReportService.loadHistory();
      this.state = {
        status: 'data',
        data: { history },
      };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'history_failed', message: (e as Error).message },
      };
    }
  }
}
