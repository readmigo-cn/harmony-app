/**
 * @readmigo/reader — public API barrel
 *
 * Source origin (moved from entry/):
 *   features/reader/  (all sub-dirs)
 *   features/ai-tools/ (all sub-dirs)
 *
 * Cross-HSP import rule: only core may import reader; reader may import vocab.
 * DO NOT import paywall/tablet/tv/car/watch/widget from here.
 */

// Reader pages
export { default as ReaderPage } from './src/main/ets/features/reader/pages/Reader';
export { default as ReaderAdapter } from './src/main/ets/features/reader/pages/ReaderAdapter';

// Reader components
export { default as BilingualReader } from './src/main/ets/features/reader/components/BilingualReader';
export { default as ChapterTocSheet } from './src/main/ets/features/reader/components/ChapterTocSheet';
export { default as HighlightLayer } from './src/main/ets/features/reader/components/HighlightLayer';
export { default as NoteEditorSheet } from './src/main/ets/features/reader/components/NoteEditorSheet';
export { default as ReaderSettingsSheet } from './src/main/ets/features/reader/components/ReaderSettingsSheet';
export { default as SelectionLayer } from './src/main/ets/features/reader/components/SelectionLayer';
export { default as SentenceHighlight } from './src/main/ets/features/reader/components/SentenceHighlight';
export { default as WordExplainSheet } from './src/main/ets/features/reader/components/WordExplainSheet';

// Reader services
export { BookmarksService } from './src/main/ets/features/reader/service/BookmarksService';
export { HighlightService } from './src/main/ets/features/reader/service/HighlightService';
export { ReadingService } from './src/main/ets/features/reader/service/ReadingService';
export { ReadingSession } from './src/main/ets/features/reader/service/ReadingSession';

// Reader viewmodels
export { ReaderViewModel } from './src/main/ets/features/reader/viewmodel/ReaderViewModel';
export { ReaderLookupViewModel } from './src/main/ets/features/reader/viewmodel/ReaderLookupViewModel';
export { ReaderProgressViewModel } from './src/main/ets/features/reader/viewmodel/ReaderProgressViewModel';

// Reader intents
export * from './src/main/ets/features/reader/intent/ReaderIntents';

// Reader surfaces (phone/tablet/tv/car/watch — surface variants kept here per split plan)
export { default as ReaderPhoneSurface } from './src/main/ets/features/reader/surfaces/PhoneSurface';
export { default as ReaderTabletSurface } from './src/main/ets/features/reader/surfaces/TabletSurface';
export { default as ReaderTvSurface } from './src/main/ets/features/reader/surfaces/TvSurface';
export { default as ReaderCarSurface } from './src/main/ets/features/reader/surfaces/CarSurface';
export { default as ReaderWatchSurface } from './src/main/ets/features/reader/surfaces/WatchSurface';

// AI tools components
export { default as AiContentBadge } from './src/main/ets/features/ai-tools/components/AiContentBadge';
export { default as ExplainCard } from './src/main/ets/features/ai-tools/components/ExplainCard';

// AI tools pages
export { default as ReadingComprehensionPage } from './src/main/ets/features/ai-tools/pages/ReadingComprehension';
export { default as WeaknessAnalysisPage } from './src/main/ets/features/ai-tools/pages/WeaknessAnalysis';

// AI tools services
export { LlmAdapter } from './src/main/ets/features/ai-tools/service/LlmAdapter';
export { PromptTemplates } from './src/main/ets/features/ai-tools/service/PromptTemplates';
export { TranslateService } from './src/main/ets/features/ai-tools/service/TranslateService';
