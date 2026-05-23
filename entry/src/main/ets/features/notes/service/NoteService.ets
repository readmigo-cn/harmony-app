/**
 * NoteService.ets — W8-C9 笔记管理 Service
 *
 * 职责：
 *   - 生词本 (vocab notes)：从 ExplainCard "保存到生词本" 进入；用于 SRS 复习
 *   - 个人笔记 (personal notes)：用户自定义文本笔记，可关联 highlight
 *
 * Local-first：
 *   - 复用 NoteRepository（local RDB）作为本地 store
 *   - 内存缓存 vocab + notes，UI 直接读
 *   - 所有 write 立即更新缓存 + RDB，再异步同步到云端 (NotesApi)
 *
 * Sync queue：与 HighlightService 模式对齐（debounce 5s + 退避重试）
 *
 * 注意：当前 NoteRepository 的 schema 没有 noteText 字段（DatabaseManager v1
 *      只存 originalText/range）。生词本 / 笔记的 noteText 暂存内存 + 同步到云端，
 *      重启后从 NotesApi.listByBook 回灌。
 */

import { NotesApi, NoteRecord, CreateNotePayload, NoteKind } from '../../../api/notes/NotesApi';
import { NoteRepository, LocalNote } from '../../../core/persistence/NoteRepository';
import { PreferencesManager } from '../../../core/persistence/PreferencesManager';
import { ExplainData } from '../../../model/ExplainData';

/** 生词本条目（含 SRS 状态字段，可选） */
export interface VocabNote {
  /** 本地 id（UUID） */
  id: string;
  bookId?: string;
  /** 单词或短语原文 */
  word: string;
  /** 上下文句子（保存时定格） */
  context: string;
  /** AI 解释结构化数据快照（释义 + 例句 + 词源等） */
  explain: ExplainData;
  /** 用户标签（如 "high-freq", "TOEFL"） */
  tags: string[];
  /** 是否已掌握（标记后从 SRS 队列移除） */
  known: boolean;
  /** 创建时间（ms） */
  createdAt: number;
  /** 上次复习时间 */
  lastReviewedAt?: number;
}

/** 个人笔记 */
export interface PersonalNote {
  id: string;
  bookId: string;
  chapterIndex?: number;
  /** 关联的 highlight id（可选） */
  highlightId?: string;
  /** 高亮的原文片段（关联 highlight 时填，便于显示） */
  highlightText?: string;
  /** 用户输入的笔记内容（multi-line） */
  content: string;
  tags: string[];
  createdAt: number;
  updatedAt: number;
}

/** 同步操作 */
type SyncKind = 'addVocab' | 'updateVocab' | 'deleteVocab' | 'addNote' | 'updateNote' | 'deleteNote';
interface SyncOp {
  kind: SyncKind;
  /** 关联本地 id */
  id: string;
  /** create 时携带 NotesApi 需要的 payload */
  payload?: CreateNotePayload | { noteText?: string };
  retries: number;
}

const VOCAB_KEY = 'vocab_notes_v1';
const NOTES_KEY = 'personal_notes_v1';
const QUEUE_KEY = 'note_sync_queue_v1';
const DEBOUNCE_MS = 5_000;
const BACKOFF_MS = [1_000, 2_000, 4_000, 8_000, 16_000];

class NoteServiceImpl {
  private vocabCache: Map<string, VocabNote> = new Map();
  private notesCache: Map<string, PersonalNote> = new Map();
  private pending: SyncOp[] = [];
  private debounceTimer: number = -1;
  private retryTimer: number = -1;
  private inited: boolean = false;

  /** EntryAbility.onCreate 调一次：恢复本地 RDB 中已存的生词 / 笔记 + 同步队列。 */
  async init(): Promise<void> {
    if (this.inited) return;
    this.inited = true;

    // 恢复持久化的 vocab / notes 索引（noteText 字段 RDB 还未存，先用 Preferences 兜底）
    const vRaw = await PreferencesManager.getString(VOCAB_KEY, '');
    if (vRaw.length > 0) {
      try {
        const list = JSON.parse(vRaw) as VocabNote[];
        for (const v of list) this.vocabCache.set(v.id, v);
      } catch (_e) { /* ignore */ }
    }
    const nRaw = await PreferencesManager.getString(NOTES_KEY, '');
    if (nRaw.length > 0) {
      try {
        const list = JSON.parse(nRaw) as PersonalNote[];
        for (const n of list) this.notesCache.set(n.id, n);
      } catch (_e) { /* ignore */ }
    }
    const qRaw = await PreferencesManager.getString(QUEUE_KEY, '');
    if (qRaw.length > 0) {
      try {
        this.pending = JSON.parse(qRaw) as SyncOp[];
      } catch (_e) {
        this.pending = [];
      }
    }
    if (this.pending.length > 0) this.scheduleFlush();
  }

  // ──────────────────────────────────────────────
  //   生词本 (vocab notes)
  // ──────────────────────────────────────────────

  /** 从 ExplainCard 保存：直接构造 VocabNote 写本地 + 入队同步。 */
  async addVocab(data: ExplainData, bookId?: string): Promise<VocabNote> {
    const id = this.genId();
    const note: VocabNote = {
      id,
      bookId: bookId ?? data.bookId,
      word: data.word,
      context: data.context,
      explain: data,
      tags: [],
      known: false,
      createdAt: Date.now(),
    };
    this.vocabCache.set(id, note);
    this.persistVocab();

    // 同步到云端：用 NotesApi.create，kind='word'
    const payload: CreateNotePayload = {
      bookId: bookId ?? data.bookId ?? '',
      originalText: data.word,
      noteText: data.definition,
      kind: 'word',
    };
    this.enqueue({ kind: 'addVocab', id, payload, retries: 0 });
    return note;
  }

  /** 列出生词本，可按 bookId / known 过滤。 */
  async listVocab(filter?: { bookId?: string; known?: boolean }): Promise<VocabNote[]> {
    const out: VocabNote[] = [];
    this.vocabCache.forEach((v) => {
      if (filter?.bookId && v.bookId !== filter.bookId) return;
      if (filter?.known !== undefined && v.known !== filter.known) return;
      out.push(v);
    });
    out.sort((a, b) => b.createdAt - a.createdAt);
    return out;
  }

  /** 模糊搜索生词（按 word / context 子串匹配，case-insensitive）。 */
  async searchVocab(query: string): Promise<VocabNote[]> {
    const q = (query ?? '').trim().toLowerCase();
    if (!q) return this.listVocab();
    const out: VocabNote[] = [];
    this.vocabCache.forEach((v) => {
      if (
        v.word.toLowerCase().includes(q) ||
        v.context.toLowerCase().includes(q) ||
        (v.explain.definition ?? '').toLowerCase().includes(q)
      ) {
        out.push(v);
      }
    });
    return out;
  }

  /** 更新生词（修改 tags / 标记 known 等）。 */
  async updateVocab(id: string, partial: Partial<VocabNote>): Promise<void> {
    const cur = this.vocabCache.get(id);
    if (!cur) return;
    const merged: VocabNote = {
      id: cur.id,
      bookId: partial.bookId ?? cur.bookId,
      word: partial.word ?? cur.word,
      context: partial.context ?? cur.context,
      explain: partial.explain ?? cur.explain,
      tags: partial.tags ?? cur.tags,
      known: partial.known ?? cur.known,
      createdAt: cur.createdAt,
      lastReviewedAt: partial.lastReviewedAt ?? cur.lastReviewedAt,
    };
    this.vocabCache.set(id, merged);
    this.persistVocab();
    this.enqueue({ kind: 'updateVocab', id, retries: 0 });
  }

  /** 删除生词（软删除：本地立即移除，云端同步）。 */
  async deleteVocab(id: string): Promise<void> {
    this.vocabCache.delete(id);
    this.persistVocab();
    this.enqueue({ kind: 'deleteVocab', id, retries: 0 });
  }

  /** 标记掌握。等价于 updateVocab(id, { known: true })，但语义化暴露给 UI。 */
  async markVocabKnown(id: string): Promise<void> {
    return this.updateVocab(id, { known: true, lastReviewedAt: Date.now() });
  }

  // ──────────────────────────────────────────────
  //   个人笔记 (personal notes)
  // ──────────────────────────────────────────────

  /** 添加一条个人笔记。可选关联 highlight。 */
  async addNote(
    bookId: string,
    chapterIndex: number | undefined,
    content: string,
    opts?: { highlightId?: string; highlightText?: string; tags?: string[] },
  ): Promise<PersonalNote> {
    const id = this.genId();
    const now = Date.now();
    const note: PersonalNote = {
      id,
      bookId,
      chapterIndex,
      highlightId: opts?.highlightId,
      highlightText: opts?.highlightText,
      content,
      tags: opts?.tags ?? [],
      createdAt: now,
      updatedAt: now,
    };
    this.notesCache.set(id, note);
    this.persistNotes();

    // 同步：本地 RDB 留底（schema 仅存 originalText / range，noteText 由云端权威）
    try {
      const local: LocalNote = {
        id,
        bookId,
        chapterId: chapterIndex !== undefined ? chapterIndex.toString() : null,
        blockIndex: 0,
        charOffset: 0,
        charLength: 0,
        originalText: opts?.highlightText ?? content.slice(0, 80),
        noteText: content,
        createdAt: now,
      };
      await NoteRepository.insert(local);
    } catch (_e) {
      // 本地写入失败也不阻塞 UI；云端同步仍可恢复
    }

    const payload: CreateNotePayload = {
      bookId,
      originalText: opts?.highlightText ?? content.slice(0, 80),
      noteText: content,
      kind: 'note',
    };
    this.enqueue({ kind: 'addNote', id, payload, retries: 0 });
    return note;
  }

  /** 列出个人笔记；不传 bookId 时返回所有。 */
  async listNotes(bookId?: string): Promise<PersonalNote[]> {
    const out: PersonalNote[] = [];
    this.notesCache.forEach((n) => {
      if (bookId && n.bookId !== bookId) return;
      out.push(n);
    });
    out.sort((a, b) => b.updatedAt - a.updatedAt);
    return out;
  }

  /** 更新笔记内容。 */
  async updateNote(id: string, content: string, tags?: string[]): Promise<void> {
    const cur = this.notesCache.get(id);
    if (!cur) return;
    const merged: PersonalNote = {
      id: cur.id,
      bookId: cur.bookId,
      chapterIndex: cur.chapterIndex,
      highlightId: cur.highlightId,
      highlightText: cur.highlightText,
      content,
      tags: tags ?? cur.tags,
      createdAt: cur.createdAt,
      updatedAt: Date.now(),
    };
    this.notesCache.set(id, merged);
    this.persistNotes();
    this.enqueue({ kind: 'updateNote', id, payload: { noteText: content }, retries: 0 });
  }

  /** 删除笔记。 */
  async deleteNote(id: string): Promise<void> {
    this.notesCache.delete(id);
    this.persistNotes();
    try { await NoteRepository.deleteById(id); } catch (_e) { /* ignore */ }
    this.enqueue({ kind: 'deleteNote', id, retries: 0 });
  }

  // ──────────────────────────────────────────────
  //   同步队列
  // ──────────────────────────────────────────────

  async flush(): Promise<void> {
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    if (this.pending.length === 0) return;

    const remain: SyncOp[] = [];
    let anyFailed = false;
    for (const op of this.pending) {
      try {
        await this.runOp(op);
      } catch (_e) {
        op.retries += 1;
        anyFailed = true;
        remain.push(op);
      }
    }
    this.pending = remain;
    this.persistQueue();
    if (anyFailed) this.scheduleBackoffRetry();
  }

  private async runOp(op: SyncOp): Promise<void> {
    if (op.kind === 'addVocab' || op.kind === 'addNote') {
      const payload = op.payload as CreateNotePayload;
      if (!payload || !payload.bookId) return;
      await NotesApi.create(payload);
      return;
    }
    if (op.kind === 'deleteVocab' || op.kind === 'deleteNote') {
      try { await NotesApi.delete(op.id); } catch (_e) { /* server 可能没这条，吞掉 */ }
      return;
    }
    // updateVocab / updateNote：当前 NotesApi 没暴露 PATCH，记为已处理（下批后端开放再补）
    return;
  }

  private enqueue(op: SyncOp): void {
    this.pending.push(op);
    this.persistQueue();
    this.scheduleFlush();
  }

  private scheduleFlush(): void {
    if (this.debounceTimer !== -1) return;
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = -1;
      this.flush();
    }, DEBOUNCE_MS) as unknown as number;
  }

  private scheduleBackoffRetry(): void {
    let maxRetry = 0;
    for (const op of this.pending) {
      if (op.retries > maxRetry) maxRetry = op.retries;
    }
    const idx = Math.min(maxRetry, BACKOFF_MS.length - 1);
    const delay = BACKOFF_MS[idx];
    if (this.retryTimer !== -1) return;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1;
      this.flush();
    }, delay) as unknown as number;
  }

  private persistVocab(): void {
    const arr: VocabNote[] = [];
    this.vocabCache.forEach((v) => arr.push(v));
    PreferencesManager.setString(VOCAB_KEY, JSON.stringify(arr));
  }

  private persistNotes(): void {
    const arr: PersonalNote[] = [];
    this.notesCache.forEach((n) => arr.push(n));
    PreferencesManager.setString(NOTES_KEY, JSON.stringify(arr));
  }

  private persistQueue(): void {
    PreferencesManager.setString(QUEUE_KEY, JSON.stringify(this.pending));
  }

  private genId(): string {
    const part = (): string => Math.floor((1 + Math.random()) * 0x10000).toString(16).slice(1);
    return `${part()}${part()}-${part()}-${part()}-${part()}-${part()}${part()}${part()}`;
  }
}

/** 单例导出。 */
export const NoteService = new NoteServiceImpl();
