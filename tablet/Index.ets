/**
 * @readmigo/tablet — public API barrel
 *
 * Source origin (moved from entry/):
 *   features/library/surfaces/TabletSurface.ets
 *   features/discover/surfaces/TabletSurface.ets
 *   features/reader/surfaces/TabletSurface.ets
 *   features/audiobook/surfaces/TabletSurface.ets
 *   features/account/surfaces/TabletSurface.ets
 *   features/multi-platform/pages/tablet/
 *
 * Trigger: loaded when BreakpointController switches to LG breakpoint.
 * Cross-HSP import rule: only core may import tablet.
 */

// Tablet layout pages
export { default as LibraryTabletLayout } from './src/main/ets/features/multi-platform/pages/tablet/LibraryTabletLayout';
export { default as DiscoverTabletLayout } from './src/main/ets/features/multi-platform/pages/tablet/DiscoverTabletLayout';
export { default as ReaderTabletLayout } from './src/main/ets/features/multi-platform/pages/tablet/ReaderTabletLayout';
export { default as NotesTabletLayout } from './src/main/ets/features/multi-platform/pages/tablet/NotesTabletLayout';

// Per-feature tablet surfaces
export { default as LibraryTabletSurface } from './src/main/ets/features/library/surfaces/TabletSurface';
export { default as DiscoverTabletSurface } from './src/main/ets/features/discover/surfaces/TabletSurface';
export { default as ReaderTabletSurface } from './src/main/ets/features/reader/surfaces/TabletSurface';
export { default as AudiobookTabletSurface } from './src/main/ets/features/audiobook/surfaces/TabletSurface';
export { default as AccountTabletSurface } from './src/main/ets/features/account/surfaces/TabletSurface';
