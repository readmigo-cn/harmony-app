// Feature - AnnualReport - Public barrel
// Re-exports the page entry, intent factory, and public state type.
// ViewModel and Service are internal and not re-exported.
export { AnnualReportPage } from './pages/AnnualReportPage';
export { AnnualReportHistoryPage } from './pages/AnnualReportHistoryPage';
export { AnnualReportPageAdapter } from './pages/AnnualReportPageAdapter';
export {
  makeAnnualReportLoadIntent,
  makeAnnualReportLoadStatusIntent,
  makeAnnualReportRegenerateIntent,
  makeAnnualReportShareIntent,
  makeAnnualReportLoadHistoryIntent,
  ANNUAL_REPORT_INTENT_KINDS,
} from './intent/AnnualReportIntents';
export type { AnnualReportIntent, AnnualReportIntentKind } from './intent/AnnualReportIntents';
export type { AnnualReportData, AnnualReportState } from './viewmodel/AnnualReportViewModel';
