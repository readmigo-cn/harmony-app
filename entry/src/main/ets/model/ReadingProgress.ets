/**
 * Reading progress / sessions — corresponds to /api/v1/reading endpoints.
 *
 * 与 store/ReadingStore.ets 中本地缓存的 ReadingProgress（简化版，含 percent）
 * 区分：此模块用于 server roundtrip，store 那个用于 AppStorage 快照。
 */

export interface ReadingProgressDto {
  bookId: string;
  chapterIndex: number;
  blockIndex?: number;
  charOffset?: number;
  pageIndex?: number;
  percent: number;
  updatedAt?: string;
}

export interface ReadingSessionStartResponse {
  sessionId: string;
  startedAt: string;
}

export interface ReadingSessionEndDto {
  durationSeconds: number;
  pagesRead?: number;
  chapterIndex?: number;
  endedAt?: string;
}
