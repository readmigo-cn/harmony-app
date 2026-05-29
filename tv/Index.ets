/**
 * @readmigo/tv — public API barrel
 *
 * Source origin (moved from entry/):
 *   features/multi-platform/pages/tv/
 *   features/multi-platform/service/RemoteController.ets
 *   features/library/surfaces/TvSurface.ets
 *   features/discover/surfaces/TvSurface.ets
 *   features/reader/surfaces/TvSurface.ets
 *   features/audiobook/surfaces/TvSurface.ets
 *   features/account/surfaces/TvSurface.ets
 *
 * Trigger: loaded synchronously at SmartScreenAbility launch.
 * Cross-HSP import rule: only core may import tv.
 */

// TV pages
export { default as SmartScreenHome } from './src/main/ets/features/multi-platform/pages/tv/SmartScreenHome';
export { default as SmartScreenReader } from './src/main/ets/features/multi-platform/pages/tv/SmartScreenReader';
export { default as SmartScreenAudiobook } from './src/main/ets/features/multi-platform/pages/tv/SmartScreenAudiobook';

// TV service
export { RemoteController } from './src/main/ets/features/multi-platform/service/RemoteController';

// Per-feature TV surfaces
export { default as LibraryTvSurface } from './src/main/ets/features/library/surfaces/TvSurface';
export { default as DiscoverTvSurface } from './src/main/ets/features/discover/surfaces/TvSurface';
export { default as ReaderTvSurface } from './src/main/ets/features/reader/surfaces/TvSurface';
export { default as AudiobookTvSurface } from './src/main/ets/features/audiobook/surfaces/TvSurface';
export { default as AccountTvSurface } from './src/main/ets/features/account/surfaces/TvSurface';
