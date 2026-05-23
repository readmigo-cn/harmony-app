/**
 * Book domain model — 单一源（合并自历史的 Book.ts + Book.ets）。
 * 字段对齐 server-cn /api/v1/books DTO，保留海外 mobile 端的产品字段为 optional。
 */

export type BookStatus = 'want-to-read' | 'reading' | 'finished';
export type SortBy = 'recent' | 'lastRead' | 'title' | 'rating';
export type BookListType =
  | 'RANKING' | 'EDITORS_PICK' | 'COLLECTION' | 'UNIVERSITY'
  | 'CELEBRITY' | 'ANNUAL_BEST' | 'AI_RECOMMENDED' | 'PERSONALIZED' | 'AI_FEATURED';

export interface Book {
  id: string;
  slug: string;
  title: string;
  author: string;
  authorId?: string;
  authorZh?: string;
  coverUrl?: string;
  coverThumbUrl?: string;
  description?: string;
  language: string;
  cefrLevel?: string;
  difficulty?: number;
  difficultyScore?: number;
  category?: string;
  wordCount?: number;
  publishYear?: number;
  source?: string;
  goodreadsRating?: number;
  doubanRating?: number;
  genres?: string[];
  hasAudiobook?: boolean;
  audiobookId?: string;
}

export interface BookDetail extends Book {
  epubUrl?: string;
  chapters?: Chapter[];
  aiScore?: number;
  estimatedReadTime?: number;
  totalChapters?: number;
  tags?: string[];
  seriesId?: string;
  seriesName?: string;
  seriesPosition?: number;
  seriesBookCount?: number;
}

export interface UserBook {
  bookId: string;
  book: Book;
  status: BookStatus;
  addedAt: string;
  lastReadAt?: string;
  progress: number;
  currentChapterIndex?: number;
  currentCfi?: string;
}

export interface Chapter {
  id: string;
  title: string;
  href?: string;
  order: number;
  wordCount?: number;
}

export interface BookFilters {
  page?: number;
  limit?: number;
  language?: string;
  cefrLevel?: string;
  category?: string;
  search?: string;
  sortBy?: SortBy;
}

export interface BookListResponse {
  items: Book[];
  total: number;
  page: number;
  limit: number;
  hasMore: boolean;
}

export interface BookListBook {
  id: string;
  title: string;
  author: string;
  authorId?: string;
  description?: string;
  coverUrl?: string;
  coverThumbUrl?: string;
  difficultyScore?: number;
  wordCount?: number;
  genres?: string[];
  doubanRating?: number;
  goodreadsRating?: number;
  rank?: number;
  customDescription?: string;
  difficulty?: number;
  audiobookId?: string;
}

export interface BookList {
  id: string;
  name: string;
  nameEn?: string;
  subtitle?: string;
  description?: string;
  coverUrl?: string;
  type: BookListType;
  displayStyle?: string;
  bookCount: number;
  sortOrder?: number;
  isActive?: boolean;
  showRank?: boolean;
  showDescription?: boolean;
  maxDisplayCount?: number;
  isAiGenerated?: boolean;
  books?: BookListBook[];
  createdAt?: string;
  updatedAt?: string;
}

export interface Rating {
  id: string;
  userId: string;
  userName?: string;
  rating: number;
  comment?: string;
  createdAt: string;
}
