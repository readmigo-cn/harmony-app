/**
 * Quote domain model — 字段对齐 server-cn /api/v1/quotes DTO。
 * L0 (model/) — pure DTO, consumed by L2 api/quotes/ and L3 features/quotes/.
 */

export interface Quote {
  readonly id: string;
  readonly text: string;
  readonly author: string;
  readonly bookId?: string;
  readonly bookTitle?: string;
  readonly liked: boolean;
}
