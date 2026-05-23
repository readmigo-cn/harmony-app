// entry/src/main/ets/ui/index.ets
// 跨 feature 共享 UI 组件的统一入口。

// ─── primitives ─────────────────────────────────────────
export * from './primitives/Button';
export * from './primitives/Card';
export * from './primitives/Input';
export * from './primitives/List';
export * from './primitives/Tab';
export * from './primitives/Toast';
export * from './primitives/Modal';
export * from './primitives/Loading';
export * from './primitives/EmptyState';

// ─── responsive ─────────────────────────────────────────
export * from './responsive/AdaptiveGrid';
export * from './responsive/FoldAwareLayout';
export * from './responsive/ResponsiveContainer';

// ─── lazy ───────────────────────────────────────────────
export * from './lazy/LazyImage';
