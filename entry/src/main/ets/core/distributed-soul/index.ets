// L1 - Foundation - DistributedSoul
// Public barrel — only ReadingSoul, SoulEngine.init, and SoulSchema types are exported.
// SoulEngine singleton, LocalFallback, and internal helpers are internal.

export { ReadingSoul } from './ReadingSoul';
export type { ReadingPosition } from './ReadingSoul';

// SoulEngine: only init/attach/flush/dispose surface; getInstance is intentionally internal.
export { SoulEngine } from './SoulEngine';
export type { SoulSnapshot } from './SoulEngine';

// Schema types for consumers that need to type-check soul shapes.
export type {
  AnySoul,
  LamportTs,
  ReadingSoul as ReadingSoulShape,
  BookSoul,
  ChapterSoul,
  SelectionSoul,
  DeviceSoul,
  TextRange,
  SoulKind,
} from './SoulSchema';
