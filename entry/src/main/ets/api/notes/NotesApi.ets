import { HttpClient } from '../../api/client/HttpClient';

export type NoteKind = 'highlight' | 'note' | 'word';

export interface NoteRecord {
  id: string;
  bookId: string;
  chapterId: string | null;
  blockIndex: number;
  charOffset: number;
  charLength: number;
  originalText: string;
  noteText: string | null;
  kind: NoteKind;
  color: string | null;
  createdAt: string;
}

export interface CreateNotePayload {
  bookId: string;
  chapterId?: string;
  blockIndex?: number;
  charOffset?: number;
  charLength?: number;
  originalText: string;
  noteText?: string;
  kind?: NoteKind;
  color?: string;
}

// ─────────────────────────────────────────────
//  W9-C1+C2: VocabNote + SRS 类型（与后端 server-cn/notes.service.ts 对齐）
// ─────────────────────────────────────────────

/** CEFR 难度等级（与 explain prompt 对齐） */
export type CefrLevel = 'A1' | 'A2' | 'B1' | 'B2' | 'C1' | 'C2';

/** 后端 VocabNoteEntity（生词本条目，含 SRS 状态） */
export interface VocabNoteRecord {
  id: string;
  userId: string;
  word: string;
  lemma: string | null;
  pronunciation: string | null;
  definition: string | null;
  exampleSentence: string | null;
  sourceBookId: string | null;
  sourceChapterIndex: number | null;
  sourceParagraphIndex: number | null;
  sourceContext: string | null;
  userTag: string | null;
  aiTags: string[] | null;
  partOfSpeech: string | null;
  difficulty: number | null;
  /** SuperMemo-2 SRS 字段 */
  easinessFactor: number;
  interval: number;
  reviewCount: number;
  nextReviewAt: string | null;
  lastReviewedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface VocabListResp {
  items: VocabNoteRecord[];
  total: number;
}

export interface ListVocabQuery {
  page?: number;
  limit?: number;
  sourceBookId?: string;
  userTag?: string;
  /** 仅返回 nextReviewAt <= now 的待复习生词 */
  dueOnly?: boolean;
}

export interface SearchVocabQuery {
  q: string;
  limit?: number;
}

export interface CreateVocabPayload {
  word: string;
  lemma?: string;
  pronunciation?: string;
  definition?: string;
  exampleSentence?: string;
  sourceBookId?: string;
  sourceChapterIndex?: number;
  sourceParagraphIndex?: number;
  sourceContext?: string;
  userTag?: string;
  aiTags?: string[];
  partOfSpeech?: string;
  difficulty?: number;
}

export interface UpdateVocabPayload {
  lemma?: string;
  pronunciation?: string;
  definition?: string;
  exampleSentence?: string;
  userTag?: string;
  aiTags?: string[];
  partOfSpeech?: string;
  difficulty?: number;
}

export interface GetDueQuery {
  count?: number;
  sourceBookId?: string;
  userTag?: string;
}

export interface ReviewSubmitPayload {
  vocabNoteId: string;
  /** SuperMemo-2 quality：0=完全遗忘, 1-2=想起一些(不通过), 3=吃力通过, 4=正确, 5=轻松 */
  quality: 0 | 1 | 2 | 3 | 4 | 5;
}

export type StatsPeriod = 'today' | '7d' | '30d';

export interface ReviewStats {
  totalReviews: number;
  correctCount: number;
  incorrectCount: number;
  /** 0-100 正确率百分比 */
  accuracy: number;
  /** 今日累计待复习 */
  dueToday: number;
}

export class NotesApi {
  // ── 旧接口（W7 笔记 / 高亮）保留以维持兼容 ────────────────────────────
  static listByBook(bookId: string): Promise<NoteRecord[]> {
    return HttpClient.get<NoteRecord[]>('/notes', { bookId });
  }

  static list(): Promise<NoteRecord[]> {
    return HttpClient.get<NoteRecord[]>('/notes');
  }

  static create(payload: CreateNotePayload): Promise<NoteRecord> {
    return HttpClient.post<NoteRecord>('/notes', payload);
  }

  static delete(id: string): Promise<void> {
    return HttpClient.delete<void>(`/notes/${id}`);
  }

  // ── W9 VocabNote CRUD ────────────────────────────────────────────────

  /** 列出生词本（分页 + 过滤） */
  static listVocab(query?: ListVocabQuery): Promise<VocabListResp> {
    const q: Record<string, string | number> = {};
    if (query?.page !== undefined) q.page = query.page;
    if (query?.limit !== undefined) q.limit = query.limit;
    if (query?.sourceBookId) q.sourceBookId = query.sourceBookId;
    if (query?.userTag) q.userTag = query.userTag;
    if (query?.dueOnly !== undefined) q.dueOnly = query.dueOnly ? 'true' : 'false';
    return HttpClient.get<VocabListResp>('/notes/vocab', q);
  }

  /** 模糊搜索生词（word / lemma 字段 ILIKE） */
  static searchVocab(query: SearchVocabQuery): Promise<VocabNoteRecord[]> {
    const q: Record<string, string | number> = { q: query.q };
    if (query.limit !== undefined) q.limit = query.limit;
    return HttpClient.get<VocabNoteRecord[]>('/notes/vocab/search', q);
  }

  /** 获取单个生词详情 */
  static getVocab(id: string): Promise<VocabNoteRecord> {
    return HttpClient.get<VocabNoteRecord>(`/notes/vocab/${id}`);
  }

  /** 添加生词 */
  static createVocab(payload: CreateVocabPayload): Promise<VocabNoteRecord> {
    return HttpClient.post<VocabNoteRecord>('/notes/vocab', payload);
  }

  /** 更新生词 */
  static updateVocab(id: string, payload: UpdateVocabPayload): Promise<VocabNoteRecord> {
    return HttpClient.patch<VocabNoteRecord>(`/notes/vocab/${id}`, payload);
  }

  /** 删除生词 */
  static deleteVocab(id: string): Promise<void> {
    return HttpClient.delete<void>(`/notes/vocab/${id}`);
  }

  // ── W9 SRS（SuperMemo-2 闪卡复习）────────────────────────────────────

  /** 获取待复习生词（按逾期时间升序） */
  static getDue(query?: GetDueQuery): Promise<VocabNoteRecord[]> {
    const q: Record<string, string | number> = {};
    if (query?.count !== undefined) q.count = query.count;
    if (query?.sourceBookId) q.sourceBookId = query.sourceBookId;
    if (query?.userTag) q.userTag = query.userTag;
    return HttpClient.get<VocabNoteRecord[]>('/notes/srs/due', q);
  }

  /** 提交一次复习结果（quality 0-5），返回更新后的生词条目 */
  static submitReview(payload: ReviewSubmitPayload): Promise<VocabNoteRecord> {
    return HttpClient.post<VocabNoteRecord>('/notes/srs/review', payload);
  }

  /** 获取复习统计（默认 7d） */
  static getReviewStats(period: StatsPeriod = '7d'): Promise<ReviewStats> {
    return HttpClient.get<ReviewStats>('/notes/srs/stats', { period });
  }
}
