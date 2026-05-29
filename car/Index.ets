/**
 * @readmigo/car — public API barrel
 *
 * Source origin (moved from entry/):
 *   features/multi-platform/pages/car/
 *   features/multi-platform/service/VoiceCommand.ets
 *   features/library/surfaces/CarSurface.ets
 *   features/discover/surfaces/CarSurface.ets
 *   features/reader/surfaces/CarSurface.ets
 *   features/audiobook/surfaces/CarSurface.ets
 *   features/account/surfaces/CarSurface.ets
 *
 * Trigger: loaded synchronously at CarAbility launch.
 * Cross-HSP import rule: only core may import car.
 */

// Car pages
export { default as CarHome } from './src/main/ets/features/multi-platform/pages/car/CarHome';
export { default as CarPlayer } from './src/main/ets/features/multi-platform/pages/car/CarPlayer';

// Car service
export { VoiceCommand } from './src/main/ets/features/multi-platform/service/VoiceCommand';

// Per-feature car surfaces
export { default as LibraryCarSurface } from './src/main/ets/features/library/surfaces/CarSurface';
export { default as DiscoverCarSurface } from './src/main/ets/features/discover/surfaces/CarSurface';
export { default as ReaderCarSurface } from './src/main/ets/features/reader/surfaces/CarSurface';
export { default as AudiobookCarSurface } from './src/main/ets/features/audiobook/surfaces/CarSurface';
export { default as AccountCarSurface } from './src/main/ets/features/account/surfaces/CarSurface';
