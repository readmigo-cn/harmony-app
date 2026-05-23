import { HttpClient } from '../../api/client/HttpClient';
import {
  Book,
  BookDetail,
  BookFilters,
  BookListResponse,
  Rating,
} from '../../model/Book';
import { Chapter, ChapterContent } from '../../model/Chapter';
import { ChapterCacheStrategy } from '../../core/cache/strategies/ChapterCacheStrategy';

/**
 * BookSummary —— 旧 import 兼容（discover/library 旧调用点用）。
 * 新代码统一用 model/Book.ets 中的 Book interface。
 */
export interface BookSummary {
  id: string;
  title: string;
  author: string;
  coverUrl?: string;
  language: string;
  cefrLevel?: string;
}

/**
 * Books API client. 与 server-cn 路由对齐：
 *   GET    /api/v1/books?page=&limit=&language=&cefrLevel=&category=&search=&sortBy=
 *   GET    /api/v1/books/:slug
 *   GET    /api/v1/books/:slug/chapters
 *   GET    /api/v1/books/:slug/chapters/:index
 *   GET    /api/v1/books/recommend
 *   POST   /api/v1/books/:id/rate
 *   GET    /api/v1/books/:id/ratings
 */
export class BooksApi {
  /** 列表（分页 + 多维筛选）。 */
  static listBooks(filters: BookFilters = {}): Promise<BookListResponse> {
    const query: Record<string, string | number> = {};
    if (filters.page !== undefined) query.page = filters.page;
    if (filters.limit !== undefined) query.limit = filters.limit;
    if (filters.language) query.language = filters.language;
    if (filters.cefrLevel) query.cefrLevel = filters.cefrLevel;
    if (filters.category) query.category = filters.category;
    if (filters.search) query.search = filters.search;
    if (filters.sortBy) query.sortBy = filters.sortBy;
    return HttpClient.get<BookListResponse>('/api/v1/books', query);
  }

  /** 详情（slug）。 */
  static getBookBySlug(slug: string): Promise<BookDetail> {
    return HttpClient.get<BookDetail>(`/api/v1/books/${encodeURIComponent(slug)}`);
  }

  /** 章节目录。 */
  static getChapters(slug: string): Promise<Chapter[]> {
    return HttpClient.get<Chapter[]>(`/api/v1/books/${encodeURIComponent(slug)}/chapters`);
  }

  /**
   * 章节内容（含 html + css）。
   * W10-C4：先查 ChapterCache，miss 才请求后端；命中后异步刷新。
   * `forceFresh=true` 跳过 cache，强制走网络（设置 / pull-to-refresh 用）。
   */
  static async getChapterContent(
    slug: string,
    index: number,
    forceFresh: boolean = false,
  ): Promise<ChapterContent> {
    if (!forceFresh) {
      const cached = await ChapterCacheStrategy.get(slug, index);
      if (cached) {
        // 已命中本地，不阻塞 UI；忽略后台刷新错误
        return cached;
      }
    }
    const fresh = await HttpClient.get<ChapterContent>(
      `/api/v1/books/${encodeURIComponent(slug)}/chapters/${index}`,
    );
    // 静默写入缓存
    ChapterCacheStrategy.put(slug, index, fresh, false).catch(() => {});
    return fresh;
  }

  /**
   * 后台 prefetch：用户翻页时调用，最多预拉 lookahead 章。
   * 失败静默；命中已缓存自动跳过。
   */
  static async prefetchChapters(
    slug: string,
    fromIndex: number,
    lookahead: number = 2,
  ): Promise<void> {
    for (let i = 1; i <= lookahead; i++) {
      const idx = fromIndex + i;
      const cached = await ChapterCacheStrategy.get(slug, idx);
      if (cached) continue;
      try {
        const fresh = await HttpClient.get<ChapterContent>(
          `/api/v1/books/${encodeURIComponent(slug)}/chapters/${idx}`,
        );
        await ChapterCacheStrategy.put(slug, idx, fresh, false);
      } catch (_e) {
        // 章节不存在或网络失败：直接退出，避免无意义的连环请求
        break;
      }
    }
  }

  /** 标记某章节为“已读”，pin 在缓存里不被淘汰。 */
  static async pinReadChapter(slug: string, index: number, content: ChapterContent): Promise<void> {
    await ChapterCacheStrategy.put(slug, index, content, true);
  }

  /** 模糊搜索。 */
  static searchBooks(query: string, limit: number = 20): Promise<Book[]> {
    return HttpClient.get<Book[]>('/api/v1/books', { search: query, limit });
  }

  /** 推荐（首页 / Library 空态用）。 */
  static getRecommended(limit: number = 10): Promise<Book[]> {
    return HttpClient.get<Book[]>('/api/v1/books/recommend', { limit });
  }

  /** 评分。 */
  static rateBook(id: string, rating: number, comment?: string): Promise<void> {
    const body: Record<string, string | number> = { rating };
    if (comment) body.comment = comment;
    return HttpClient.post<void>(`/api/v1/books/${encodeURIComponent(id)}/rate`, body);
  }

  /** 评分列表。 */
  static getRatings(id: string): Promise<Rating[]> {
    return HttpClient.get<Rating[]>(`/api/v1/books/${encodeURIComponent(id)}/ratings`);
  }

  // -------------------- Legacy alias（旧页面引用）----------------------------

  /** Legacy: 旧 list 签名，返回扁平 Book[]，内部转 listBooks。 */
  static async list(page: number = 1, pageSize: number = 20): Promise<BookSummary[]> {
    const resp = await BooksApi.listBooks({ page, limit: pageSize });
    return resp.items.map((b): BookSummary => ({
      id: b.id,
      title: b.title,
      author: b.author,
      coverUrl: b.coverUrl,
      language: b.language,
      cefrLevel: b.cefrLevel,
    }));
  }

  static get(slug: string): Promise<BookDetail> {
    return BooksApi.getBookBySlug(slug);
  }

  static search(keyword: string): Promise<Book[]> {
    return BooksApi.searchBooks(keyword);
  }
}
