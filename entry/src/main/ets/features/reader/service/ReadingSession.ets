/**
 * ReadingSession.ets — W7-C6 阅读会话追踪
 *
 * 职责：
 *   - start(bookId, chapterIndex)：调 ReadingApi.startSession 拿 sessionId，本地记 startTime
 *   - tick()：每 30s 由 Reader 调用，刷新 activeMs（或调用方自行实现）
 *   - recordPageTurn / recordChapterChange / recordWordLookup：累加计数
 *   - end()：聚合计数 + 时长，调 ReadingApi.endSession，清空状态
 *   - 自动暂停：onBackground() 进入；超过 30s 没回前台则不计入时长
 *   - 自动恢复：onForeground() + 同 bookId 时无缝接续
 *   - getCurrentSession()：UI 展示用（如顶部 "已读 12 分钟"）
 */

import { ReadingApi } from '../../../api/reading/ReadingApi';

export interface SessionInfo {
  sessionId: string | null;
  bookId: string;
  chapterIndex: number;
  startedAt: number;
  /** 累计活跃毫秒数（暂停时不增长） */
  activeMs: number;
  pagesRead: number;
  chaptersRead: number;
  wordsLooked: number;
  paused: boolean;
}

const AUTO_PAUSE_THRESHOLD_MS = 30_000;

class ReadingSessionImpl {
  private session: SessionInfo | null = null;
  /** 上次 tick 时间（用于增量累加 activeMs） */
  private lastTickTs: number = 0;
  /** 进入后台的时间戳（用于自动暂停判定） */
  private backgroundedAt: number = 0;

  /** 启动一个新 session。重复 start 同 book 直接返回。 */
  async start(bookId: string, chapterIndex: number): Promise<void> {
    if (!bookId) return;
    if (this.session && this.session.bookId === bookId) {
      // 已有 session，确保未暂停
      if (this.session.paused) {
        this.resumeInternal();
      }
      return;
    }
    // 切到新 book：先 end 旧 session
    if (this.session) {
      await this.end();
    }
    const now = Date.now();
    this.session = {
      sessionId: null,
      bookId,
      chapterIndex,
      startedAt: now,
      activeMs: 0,
      pagesRead: 0,
      chaptersRead: 0,
      wordsLooked: 0,
      paused: false,
    };
    this.lastTickTs = now;
    try {
      const resp = await ReadingApi.startSession(bookId);
      if (this.session) {
        this.session.sessionId = resp.sessionId;
      }
    } catch (_e) {
      // 服务器拒绝时仍维持本地 session，end 时会跳过 endSession 调用
    }
  }

  /** 由 Reader 周期触发（推荐 30s 一次）。返回当前 activeMs，便于 UI 显示。 */
  tick(): number {
    if (!this.session || this.session.paused) return this.session?.activeMs ?? 0;
    const now = Date.now();
    const delta = now - this.lastTickTs;
    if (delta > 0 && delta < AUTO_PAUSE_THRESHOLD_MS * 2) {
      this.session.activeMs += delta;
    }
    this.lastTickTs = now;
    return this.session.activeMs;
  }

  recordPageTurn(): void {
    if (!this.session) return;
    this.session.pagesRead += 1;
  }

  recordChapterChange(newIndex: number): void {
    if (!this.session) return;
    if (newIndex !== this.session.chapterIndex) {
      this.session.chaptersRead += 1;
      this.session.chapterIndex = newIndex;
    }
  }

  recordWordLookup(): void {
    if (!this.session) return;
    this.session.wordsLooked += 1;
  }

  /** 结束当前 session 并把聚合数据上报。失败静默。 */
  async end(): Promise<void> {
    const s = this.session;
    if (!s) return;
    this.session = null;
    // 未暂停时把最后一段时间累入
    if (!s.paused) {
      const now = Date.now();
      const delta = now - this.lastTickTs;
      if (delta > 0 && delta < AUTO_PAUSE_THRESHOLD_MS * 2) {
        s.activeMs += delta;
      }
    }
    if (!s.sessionId) return;
    try {
      await ReadingApi.endSession(s.sessionId, {
        durationSeconds: Math.max(0, Math.round(s.activeMs / 1000)),
        pagesRead: s.pagesRead,
        chapterIndex: s.chapterIndex,
      });
    } catch (_e) {
      // 失败不阻塞，下一次 ServiceExtAbility 会重投
    }
  }

  /** 获取当前 session（UI 只读）。返回拷贝避免外部改写。 */
  getCurrentSession(): SessionInfo | null {
    if (!this.session) return null;
    const s = this.session;
    return {
      sessionId: s.sessionId,
      bookId: s.bookId,
      chapterIndex: s.chapterIndex,
      startedAt: s.startedAt,
      activeMs: s.activeMs,
      pagesRead: s.pagesRead,
      chaptersRead: s.chaptersRead,
      wordsLooked: s.wordsLooked,
      paused: s.paused,
    };
  }

  /** 由 EntryAbility.onBackground 或 Reader.onPageHide 触发。 */
  onBackground(): void {
    if (!this.session) return;
    // 把进入后台前的最后一段时间累入
    this.tick();
    this.session.paused = true;
    this.backgroundedAt = Date.now();
  }

  /** 由 EntryAbility.onForeground 或 Reader.onPageShow 触发。 */
  onForeground(bookId?: string): void {
    if (!this.session) return;
    // 不同 book 不复用
    if (bookId && bookId !== this.session.bookId) return;
    // 后台时间过长则视为新一段，但不丢失计数
    const now = Date.now();
    const bgMs = this.backgroundedAt > 0 ? now - this.backgroundedAt : 0;
    if (bgMs > AUTO_PAUSE_THRESHOLD_MS) {
      // 长时间未回前台：不补回这段时间，但允许后续继续累计
      this.lastTickTs = now;
    } else {
      this.lastTickTs = now - bgMs; // 短暂切走允许补回
    }
    this.session.paused = false;
    this.backgroundedAt = 0;
  }

  private resumeInternal(): void {
    if (!this.session) return;
    this.session.paused = false;
    this.lastTickTs = Date.now();
    this.backgroundedAt = 0;
  }
}

export const ReadingSession = new ReadingSessionImpl();
