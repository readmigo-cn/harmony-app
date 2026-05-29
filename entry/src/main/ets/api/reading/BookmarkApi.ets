import { HttpClient } from '../client/HttpClient';

/**
 * BookmarkApi — 对齐 iOS readmigo 的 /bookmarks 端点（route 名假设按 iOS 风格）。
 *
 * **端点状态**: server-cn 是否已开放 /api/v1/reading/bookmarks 未确认（P0-B Q2=C 决策：
 * 先搭客户端架子，端点对齐留 P1-B）。当前 ENDPOINT_AVAILABLE=false，所有方法 no-op
 * 静默返回成功，本地 Repository 仍正常落盘。
 *
 * P1-B 联调时：
 *   1. 把 ENDPOINT_AVAILABLE 翻 true
 *   2. 根据 server-cn 实际响应调整 BookmarkDto 字段命名
 *   3. 同步队列里堆积的项会自动随 ProgressSync 网络监听重发
 */

const ENDPOINT_AVAILABLE: boolean = false;

export interface BookmarkDto {
  id: string;
  bookId: string;
  chapterId: string;
  pageIdx: number;
  label?: string;
  /** ISO 8601 */
  createdAt: string;
}

export class BookmarkApi {
  static isAvailable(): boolean {
    return ENDPOINT_AVAILABLE;
  }

  static async upsert(dto: BookmarkDto): Promise<void> {
    if (!ENDPOINT_AVAILABLE) return;
    await HttpClient.post<void>('/api/v1/reading/bookmarks', dto as unknown as object);
  }

  static async delete(id: string): Promise<void> {
    if (!ENDPOINT_AVAILABLE) return;
    await HttpClient.delete<void>(`/api/v1/reading/bookmarks/${encodeURIComponent(id)}`);
  }

  static async getById(id: string): Promise<BookmarkDto | null> {
    if (!ENDPOINT_AVAILABLE) return null;
    try {
      return await HttpClient.get<BookmarkDto>(
        `/api/v1/reading/bookmarks/${encodeURIComponent(id)}`,
      );
    } catch (_e) {
      return null;
    }
  }

  static async listByBook(bookId: string): Promise<BookmarkDto[]> {
    if (!ENDPOINT_AVAILABLE) return [];
    try {
      return await HttpClient.get<BookmarkDto[]>(
        `/api/v1/reading/bookmarks/book/${encodeURIComponent(bookId)}`,
      );
    } catch (_e) {
      return [];
    }
  }
}
