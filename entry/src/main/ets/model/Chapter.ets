/**
 * Chapter / ChapterContent — corresponds to /api/v1/books/:slug/chapters
 * 与 typesetting engine 的 loadDocument(html, css) 配合使用。
 */

export interface Chapter {
  id: string;
  index: number;
  title: string;
  href?: string;
  wordCount?: number;
  durationSeconds?: number;
}

export interface ChapterContent {
  bookId: string;
  bookSlug: string;
  index: number;
  title: string;
  html: string;
  css?: string;
  wordCount: number;
  prevIndex?: number;
  nextIndex?: number;
}
