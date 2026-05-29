/**
 * @readmigo/vocab — public API barrel
 *
 * Source origin (moved from entry/):
 *   features/vocab/ (all sub-dirs)
 *
 * Cross-HSP import rule: only core and reader may import vocab; vocab may import paywall.
 */

// Vocab pages
export { default as VocabPage } from './src/main/ets/features/vocab/pages/Vocab';
export { default as FlashcardSessionPage } from './src/main/ets/features/vocab/pages/FlashcardSession';
export { default as VocabStatsPage } from './src/main/ets/features/vocab/pages/VocabStats';
export { default as WordAssociationPage } from './src/main/ets/features/vocab/pages/WordAssociation';
export { default as WordFamilyPage } from './src/main/ets/features/vocab/pages/WordFamily';

// Vocab components
export { default as VocabDetailSheet } from './src/main/ets/features/vocab/components/VocabDetailSheet';
