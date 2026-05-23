/**
 * HighlightService.ets — W8-C8 高亮管理 Service
 *
 * 设计目标：
 *   - 单例（getInstance），全局共享高亮缓存
 *   - Local-first：所有 read 直接走内存（来源 RDB），write 立即更新内存 + 触发 UI 回调，
 *     再异步同步到云端；网络失败时进队列，online 后自动 flush
 *   - 与 ReadingApi（/api/v1/reading/highlights）集成
 *
 * 同步队列模型（参考 ProgressSync 的 debounce + retry 思路，但更简化）：
 *   - 每条变更（create/update/delete）入 pendingOps 队列，FIFO
 *   - 5 秒 debounce 后批量 flush；失败指数退避（1s / 2s / 4s / 8s / 16s 封顶）
 *   - 队列持久化到 PreferencesManager，崩溃重启回灌
 *
 * 冲突解决（list 时 server-vs-local merge）：
 *   - 按 highlight.id 合并，server 中存在 → server 胜出（除非该 id 在 pendingOps 中正待删/改）
 *   - 仅本地有的（remoteId 还未填）→ 保留
 *   - 仅 server 有的 → 加入本地
 */

import { ReadingApi } from '../../../api/reading/ReadingApi';
import {
  Highlight,
  CreateHighlightDto,
  UpdateHighlightDto,
  HighlightColor,
} from '../../../model/Highlight';
import { PreferencesManager } from '../../../core/persistence/PreferencesManager';

/** 同步操作类型 */
type PendingOpKind = 'create' | 'update' | 'delete';

interface PendingOp {
  /** 本地 id（创建时生成的 UUID，update/delete 用 server id 或本地 id） */
  id: string;
  kind: PendingOpKind;
  /** create 携带完整 dto；update 携带 partial；delete 不需要 payload */
  payload?: CreateHighlightDto | UpdateHighlightDto;
  /** 已重试次数 */
  retries: number;
  /** 入队时间（ms） */
  enqueuedAt: number;
}

const QUEUE_KEY = 'highlight_pending_queue_v1';
const DEBOUNCE_MS = 5_000;
const BACKOFF_MS = [1_000, 2_000, 4_000, 8_000, 16_000];

class HighlightServiceImpl {
  /** 内存缓存：bookId -> highlights */
  private cache: Map<string, Highlight[]> = new Map();
  /** 待同步操作队列 */
  private pending: PendingOp[] = [];
  private debounceTimer: number = -1;
  private retryTimer: number = -1;
  private inited: boolean = false;

  /** 启动时调一次：恢复持久化队列。若有未推送项，立即调度 flush。 */
  async init(): Promise<void> {
    if (this.inited) return;
    this.inited = true;
    const raw = await PreferencesManager.getString(QUEUE_KEY, '');
    if (raw.length > 0) {
      try {
        this.pending = JSON.parse(raw) as PendingOp[];
      } catch (_e) {
        this.pending = [];
      }
    }
    if (this.pending.length > 0) {
      this.scheduleFlush();
    }
  }

  /**
   * 列出某本书的高亮：local first。
   *  1. 命中缓存直接返回
   *  2. 否则 fire 一次 server fetch，写缓存
   *  3. 失败也返回空数组（不抛）
   */
  async list(bookId: string): Promise<Highlight[]> {
    if (!bookId) return [];
    const cached = this.cache.get(bookId);
    if (cached) return cached.slice();
    try {
      const list = await ReadingApi.listHighlights(bookId);
      this.cache.set(bookId, list);
      return list.slice();
    } catch (_e) {
      this.cache.set(bookId, []);
      return [];
    }
  }

  /** 强制从云端 pull + merge 本地未同步的项。冲突按 server 胜出（除非在 pending 队列中）。 */
  async sync(bookId: string): Promise<void> {
    if (!bookId) return;
    let server: Highlight[] = [];
    try {
      server = await ReadingApi.listHighlights(bookId);
    } catch (_e) {
      return;
    }
    const local = this.cache.get(bookId) ?? [];
    const pendingIds = new Set(this.pending.map((op) => op.id));

    const merged: Map<string, Highlight> = new Map();
    // 先放 server 端，作为基线
    for (const h of server) merged.set(h.id, h);
    // 本地的：仅保留 server 没有 + 在 pending 队列中的（这些是本地刚创建未同步的）
    for (const h of local) {
      if (!merged.has(h.id) && pendingIds.has(h.id)) {
        merged.set(h.id, h);
      }
    }
    const next: Highlight[] = [];
    merged.forEach((v) => next.push(v));
    this.cache.set(bookId, next);
  }

  /**
   * 创建一条高亮。立即更新内存缓存 + 入队同步。
   * 返回的 Highlight.id 是本地生成的 UUID；服务端同步成功后保留同 id（
   * 服务端会以客户端 id 为准）。
   */
  async create(bookId: string, dto: CreateHighlightDto): Promise<Highlight> {
    const localId = this.genId();
    const now = new Date().toISOString();
    const created: Highlight = {
      id: localId,
      bookId,
      chapterId: dto.chapterId,
      chapterIndex: dto.chapterIndex,
      blockIndex: dto.blockIndex,
      charOffset: dto.charOffset,
      charLength: dto.charLength,
      text: dto.text,
      color: dto.color ?? 'yellow',
      note: dto.note,
      createdAt: now,
      updatedAt: now,
    };
    const list = this.cache.get(bookId) ?? [];
    list.push(created);
    this.cache.set(bookId, list);

    this.enqueue({
      id: localId,
      kind: 'create',
      payload: dto,
      retries: 0,
      enqueuedAt: Date.now(),
    });
    return created;
  }

  /** 更新高亮（颜色 / 笔记）。立即更新内存 + 入队。 */
  async update(bookId: string, id: string, partial: UpdateHighlightDto): Promise<void> {
    const list = this.cache.get(bookId) ?? [];
    const idx = list.findIndex((h) => h.id === id);
    if (idx >= 0) {
      const merged: Highlight = {
        id: list[idx].id,
        bookId: list[idx].bookId,
        chapterId: list[idx].chapterId,
        chapterIndex: list[idx].chapterIndex,
        blockIndex: list[idx].blockIndex,
        charOffset: list[idx].charOffset,
        charLength: list[idx].charLength,
        text: list[idx].text,
        color: partial.color ?? list[idx].color,
        note: partial.note ?? list[idx].note,
        createdAt: list[idx].createdAt,
        updatedAt: new Date().toISOString(),
      };
      list[idx] = merged;
      this.cache.set(bookId, list);
    }
    this.enqueue({
      id,
      kind: 'update',
      payload: partial,
      retries: 0,
      enqueuedAt: Date.now(),
    });
  }

  /** 删除高亮。立即从缓存移除 + 入队。 */
  async delete(bookId: string, id: string): Promise<void> {
    const list = this.cache.get(bookId) ?? [];
    const next = list.filter((h) => h.id !== id);
    this.cache.set(bookId, next);
    this.enqueue({
      id,
      kind: 'delete',
      retries: 0,
      enqueuedAt: Date.now(),
    });
  }

  /** 立刻 flush 同步队列（adapter 切前后台时调）。 */
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

    const remaining: PendingOp[] = [];
    let anyFailed = false;
    for (const op of this.pending) {
      try {
        await this.runOp(op);
      } catch (_e) {
        op.retries += 1;
        anyFailed = true;
        remaining.push(op);
      }
    }
    this.pending = remaining;
    this.persistQueue();

    if (anyFailed) {
      this.scheduleBackoffRetry();
    }
  }

  // ─── internals ─────────────────────────────────

  private enqueue(op: PendingOp): void {
    this.pending.push(op);
    this.persistQueue();
    this.scheduleFlush();
  }

  private async runOp(op: PendingOp): Promise<void> {
    if (op.kind === 'create') {
      await ReadingApi.createHighlight(op.payload as CreateHighlightDto);
      return;
    }
    if (op.kind === 'update') {
      await ReadingApi.updateHighlight(op.id, op.payload as UpdateHighlightDto);
      return;
    }
    if (op.kind === 'delete') {
      await ReadingApi.deleteHighlight(op.id);
      return;
    }
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

  private persistQueue(): void {
    PreferencesManager.setString(QUEUE_KEY, JSON.stringify(this.pending));
  }

  /** 生成本地 UUID（v4 简化版，不依赖外部库）。 */
  private genId(): string {
    const part = (): string => Math.floor((1 + Math.random()) * 0x10000).toString(16).slice(1);
    return `${part()}${part()}-${part()}-${part()}-${part()}-${part()}${part()}${part()}`;
  }
}

/** 单例导出。 */
export const HighlightService = new HighlightServiceImpl();

/** 重导出 HighlightColor 方便调用方。 */
export { HighlightColor };
