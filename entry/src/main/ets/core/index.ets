// entry/src/main/ets/core/index.ets
// 跨切关注点与平台能力的统一入口。consumer 应通过此 barrel 引入 core 的公开 API。

// ─── router ─────────────────────────────────────────────
export * from './router/RouteConstants';
export * from './router/RouterService';

// ─── persistence ────────────────────────────────────────
export * from './persistence/PreferencesManager';
export * from './persistence/DatabaseManager';
export * from './persistence/NoteRepository';

// ─── theme ──────────────────────────────────────────────
export * from './theme/AppColors';
export * from './theme/AppSpacing';
export * from './theme/AppTokens';
export * from './theme/AppTypography';
export * from './theme/Breakpoints';
export * from './theme/ThemeService';
