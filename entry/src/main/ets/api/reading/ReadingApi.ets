import { HttpClient } from '../../api/client/HttpClient';
import {
  ReadingProgressDto,
  ReadingSessionStartResponse,
  ReadingSessionEndDto,
} from '../../model/ReadingProgress';
import {
  Highlight,
  CreateHighlightDto,
  UpdateHighlightDto,
} from '../../model/Highlight';
import { UserBook, BookStatus } from '../../model/Book';

/**
 * Reading API client. 与 server-cn 路由对齐：
 *   GET   /api/v1/bookshelf
 *   POST  /api/v1/bookshelf/:bookId
 *   PATCH /api/v1/bookshelf/:bookId/status
 *   GET   /api/v1/reading/progress/:bookId
 *   PUT   /api/v1/reading/progress/:bookId
 *   POST  /api/v1/reading/sessions/start
 *   POST  /api/v1/reading/sessions/:id/end
 *   GET   /api/v1/reading/highlights/:bookId
 *   POST  /api/v1/reading/highlights
 *   PATCH /api/v1/reading/highlights/:id
 *   DELETE /api/v1/reading/highlights/:id
 */
export class ReadingApi {
  // ---------- Progress ------------------------------------------------------

  static getProgress(bookId: string): Promise<ReadingProgressDto> {
    return HttpClient.get<ReadingProgressDto>(
      `/api/v1/reading/progress/${encodeURIComponent(bookId)}`,
    );
  }

  static updateProgress(bookId: string, dto: ReadingProgressDto): Promise<void> {
    return HttpClient.put<void>(
      `/api/v1/reading/progress/${encodeURIComponent(bookId)}`,
      dto,
    );
  }

  // ---------- Sessions ------------------------------------------------------

  static startSession(bookId: string): Promise<ReadingSessionStartResponse> {
    return HttpClient.post<ReadingSessionStartResponse>(
      '/api/v1/reading/sessions/start',
      { bookId },
    );
  }

  static endSession(sessionId: string, dto: ReadingSessionEndDto): Promise<void> {
    return HttpClient.post<void>(
      `/api/v1/reading/sessions/${encodeURIComponent(sessionId)}/end`,
      dto,
    );
  }

  // ---------- Highlights ----------------------------------------------------

  static listHighlights(bookId: string): Promise<Highlight[]> {
    return HttpClient.get<Highlight[]>(
      `/api/v1/reading/highlights/${encodeURIComponent(bookId)}`,
    );
  }

  static createHighlight(dto: CreateHighlightDto): Promise<Highlight> {
    return HttpClient.post<Highlight>('/api/v1/reading/highlights', dto);
  }

  static updateHighlight(id: string, dto: UpdateHighlightDto): Promise<void> {
    return HttpClient.patch<void>(
      `/api/v1/reading/highlights/${encodeURIComponent(id)}`,
      dto,
    );
  }

  static deleteHighlight(id: string): Promise<void> {
    return HttpClient.delete<void>(
      `/api/v1/reading/highlights/${encodeURIComponent(id)}`,
    );
  }

  // ---------- Bookshelf -----------------------------------------------------

  static listShelf(): Promise<UserBook[]> {
    return HttpClient.get<UserBook[]>('/api/v1/bookshelf');
  }

  static addToShelf(bookId: string): Promise<UserBook> {
    return HttpClient.post<UserBook>(
      `/api/v1/bookshelf/${encodeURIComponent(bookId)}`,
      {},
    );
  }

  static updateShelfStatus(bookId: string, status: BookStatus): Promise<void> {
    return HttpClient.patch<void>(
      `/api/v1/bookshelf/${encodeURIComponent(bookId)}/status`,
      { status },
    );
  }
}
