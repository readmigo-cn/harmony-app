/**
 * Highlight / annotation — /api/v1/reading/highlights endpoints.
 * 与 NotesApi.NoteRecord 区分：highlight 着重 selection range + color，
 * note 着重 noteText。
 */

export type HighlightColor = 'yellow' | 'green' | 'blue' | 'pink' | 'orange';

export interface Highlight {
  id: string;
  bookId: string;
  chapterId?: string;
  chapterIndex?: number;
  blockIndex: number;
  charOffset: number;
  charLength: number;
  text: string;
  color: HighlightColor;
  note?: string;
  createdAt: string;
  updatedAt?: string;
}

export interface CreateHighlightDto {
  bookId: string;
  chapterId?: string;
  chapterIndex?: number;
  blockIndex: number;
  charOffset: number;
  charLength: number;
  text: string;
  color?: HighlightColor;
  note?: string;
}

export interface UpdateHighlightDto {
  color?: HighlightColor;
  note?: string;
}
