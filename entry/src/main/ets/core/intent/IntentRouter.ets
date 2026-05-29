// L1 - Foundation - Intent
// Static routing table: which intent kind is handled by which feature ViewModel.
// Pure data; no runtime logic.

import type { IntentKind } from './Intent';

/** Identifies a feature ViewModel by feature name and class name. */
export interface ViewModelRef {
  readonly feature: string;
  readonly viewModel: string;
}

/**
 * Maps each IntentKind to the ViewModel responsible for handling it.
 * @since W1
 */
export const INTENT_ROUTES: Record<IntentKind, ViewModelRef> = {
  'reader.openBook':           { feature: 'reader',    viewModel: 'ReaderViewModel' },
  'reader.jumpToChapter':      { feature: 'reader',    viewModel: 'ReaderViewModel' },
  'reader.jumpToPage':         { feature: 'reader',    viewModel: 'ReaderViewModel' },
  'reader.selectText':         { feature: 'reader',    viewModel: 'ReaderViewModel' },
  'reader.openHighlightLayer': { feature: 'reader',    viewModel: 'ReaderViewModel' },
  'reader.openTocSheet':       { feature: 'reader',    viewModel: 'ReaderViewModel' },
  'reader.openSettings':       { feature: 'reader',    viewModel: 'ReaderViewModel' },
  'reader.lookupWord':         { feature: 'reader',    viewModel: 'ReaderViewModel' },
  'discover.browse':           { feature: 'discover',  viewModel: 'DiscoverViewModel' },
  'library.openBookshelf':     { feature: 'library',   viewModel: 'LibraryViewModel' },
  'account.open':              { feature: 'account',   viewModel: 'AccountViewModel' },
  'account.openSubscriptions': { feature: 'account',   viewModel: 'AccountViewModel' },
  'audiobook.play':            { feature: 'audiobook', viewModel: 'AudiobookViewModel' },
  'audiobook.pause':           { feature: 'audiobook', viewModel: 'AudiobookViewModel' },
};
