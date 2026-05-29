/**
 * @readmigo/widget — public API barrel
 *
 * Source origin (moved from entry/):
 *   core/widget/AiTipExtensionAbility.ets
 *   core/widget/DailyWordExtensionAbility.ets
 *   core/widget/ReadingProgressExtensionAbility.ets
 *   core/widget/UniversalCardAdapter.ets
 *   core/widget/FormDataStore.ets
 *   core/widget/pages/AiTipCard.ets
 *   core/widget/pages/DailyWordCard.ets
 *   core/widget/pages/ReadingProgressCard.ets
 *
 * Trigger: loaded by FormExtensionAbility.onAddForm.
 * Cross-HSP import rule: only core may import widget. Atomic services may only
 * depend on this widget HAR (not reader) per bundle-strategy.md §5.
 */

// ExtensionAbilities (registered in widget/src/main/module.json5)
export { default as DailyWordExtensionAbility } from './src/main/ets/core/widget/DailyWordExtensionAbility';
export { default as ReadingProgressExtensionAbility } from './src/main/ets/core/widget/ReadingProgressExtensionAbility';
export { default as AiTipExtensionAbility } from './src/main/ets/core/widget/AiTipExtensionAbility';

// Core adapter & store
export { UniversalCardAdapter } from './src/main/ets/core/widget/UniversalCardAdapter';
export { FormDataStore } from './src/main/ets/core/widget/FormDataStore';

// Card pages
export { default as DailyWordCard } from './src/main/ets/core/widget/pages/DailyWordCard';
export { default as ReadingProgressCard } from './src/main/ets/core/widget/pages/ReadingProgressCard';
export { default as AiTipCard } from './src/main/ets/core/widget/pages/AiTipCard';
