// entry/src/main/ets/api/index.ets
// HTTP 客户端与各业务域 API 的统一入口。

// ─── client ─────────────────────────────────────────────
export * from './client/HttpClient';
export * from './client/ApiConfig';
export * from './client/SseClient';

// ─── domain APIs ────────────────────────────────────────
export * from './books/BooksApi';
export * from './auth/AuthApi';
export * from './reading/ReadingApi';
export * from './reading/StatsApi';
export * from './ai/AiApi';
export * from './ai/WordAnalysisApi';
export * from './notes/NotesApi';
export * from './study/StudyPlanApi';
export * from './subscription/SubscriptionApi';
export * from './support/SupportApi';
export * from './widget/WidgetApi';
