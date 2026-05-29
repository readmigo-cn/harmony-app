/**
 * @readmigo/watch — public API barrel
 *
 * Source origin (moved from entry/):
 *   features/multi-platform/pages/watch/
 *   features/library/surfaces/WatchSurface.ets
 *   features/discover/surfaces/WatchSurface.ets
 *   features/reader/surfaces/WatchSurface.ets
 *   features/audiobook/surfaces/WatchSurface.ets
 *   features/account/surfaces/WatchSurface.ets
 *   core/widget/WatchVocabCardExtensionAbility.ets
 *   core/widget/pages/WatchVocabCard.ets
 *
 * Trigger: loaded synchronously at WatchAbility launch.
 * Cross-HSP import rule: only core may import watch.
 */

// Watch pages
export { default as WatchHome } from './src/main/ets/features/multi-platform/pages/watch/WatchHome';
export { default as WatchStats } from './src/main/ets/features/multi-platform/pages/watch/WatchStats';
export { default as WatchVocab } from './src/main/ets/features/multi-platform/pages/watch/WatchVocab';

// Watch widget card
export { default as WatchVocabCard } from './src/main/ets/core/widget/pages/WatchVocabCard';

// Watch ExtensionAbility (registered in watch/src/main/module.json5)
export { default as WatchVocabCardExtensionAbility } from './src/main/ets/core/widget/WatchVocabCardExtensionAbility';

// Per-feature watch surfaces
export { default as LibraryWatchSurface } from './src/main/ets/features/library/surfaces/WatchSurface';
export { default as DiscoverWatchSurface } from './src/main/ets/features/discover/surfaces/WatchSurface';
export { default as ReaderWatchSurface } from './src/main/ets/features/reader/surfaces/WatchSurface';
export { default as AudiobookWatchSurface } from './src/main/ets/features/audiobook/surfaces/WatchSurface';
export { default as AccountWatchSurface } from './src/main/ets/features/account/surfaces/WatchSurface';
