// L1 - Foundation - Intent
// Public barrel for the intent subsystem.

export type {
  Intent,
  AnyIntent,
  IntentKind,
  TextRange,
  OpenBookIntent,
  JumpToChapterIntent,
  JumpToPageIntent,
  SelectTextIntent,
  OpenHighlightLayerIntent,
  OpenTocSheetIntent,
  OpenReaderSettingsIntent,
  LookupWordIntent,
  BrowseDiscoverIntent,
  OpenBookshelfIntent,
  OpenAccountIntent,
  OpenSubscriptionsIntent,
  PlayAudiobookIntent,
  PauseAudiobookIntent,
} from './Intent';

export { IntentBus } from './IntentBus';
export type { Unsubscribe } from './IntentBus';

export { INTENT_ROUTES } from './IntentRouter';
export type { ViewModelRef } from './IntentRouter';

export { FeatureViewModel } from './ViewModel';
export type { ViewModelState } from './ViewModel';
