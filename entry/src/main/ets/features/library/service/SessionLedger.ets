import { PreferencesManager, NamespacedPreferences } from '../../../core/persistence/PreferencesManager';

/**
 * 阅读会话本地账本（client-side session ledger）。
 *
 * server-cn `/reading/stats` 不返回 streak，连续天数必须客户端算；
 * SessionLedger 负责存原始 SessionRecord，StreakService 负责推导。
 *
 * 存储：PreferencesManager namespace 'session_ledger'，JSON 数组持久化。
 * 容量：保留最近 365 条（约 1 年阅读历史），超出按 FIFO 截断。
 */

export interface SessionRecord {
  sessionId: string;
  bookId: string;
  startedAtMs: number;
  endedAtMs: number;
  durationMs: number;
  charactersRead?: number;
  /** endedAtMs 的本地日期（YYYY-MM-DD），存进 record 方便 streak 算法 O(1) 查询。 */
  endedDate: string;
}

const STORE_KEY = 'records_v1';
const MAX_RECORDS = 365;

export class SessionLedger {
  private static readonly ns: NamespacedPreferences =
    PreferencesManager.createNamespace('session_ledger');
  private static cache: SessionRecord[] | null = null;

  static async init(): Promise<void> {
    if (SessionLedger.cache !== null) return;
    SessionLedger.cache = await SessionLedger.ns.getArray<SessionRecord>(STORE_KEY, []);
  }

  static async append(rec: SessionRecord): Promise<void> {
    await SessionLedger.ensureLoaded();
    const cache = SessionLedger.cache as SessionRecord[];
    cache.push(rec);
    if (cache.length > MAX_RECORDS) {
      SessionLedger.cache = cache.slice(cache.length - MAX_RECORDS);
    }
    await SessionLedger.ns.setArray<SessionRecord>(STORE_KEY, SessionLedger.cache as SessionRecord[]);
  }

  /** 返回 records 拷贝（避免外部修改污染内部 cache）。 */
  static async all(): Promise<SessionRecord[]> {
    await SessionLedger.ensureLoaded();
    return (SessionLedger.cache as SessionRecord[]).slice();
  }

  static async recentDays(n: number): Promise<SessionRecord[]> {
    const cutoff = Date.now() - n * 24 * 60 * 60 * 1000;
    const all = await SessionLedger.all();
    return all.filter((r) => r.endedAtMs >= cutoff);
  }

  static async clear(): Promise<void> {
    SessionLedger.cache = [];
    await SessionLedger.ns.setArray<SessionRecord>(STORE_KEY, []);
  }

  /** 本地时区下的 YYYY-MM-DD 日期串。 */
  static formatLocalDate(ms: number): string {
    const d = new Date(ms);
    const y = d.getFullYear();
    const m = (d.getMonth() + 1).toString().padStart(2, '0');
    const day = d.getDate().toString().padStart(2, '0');
    return `${y}-${m}-${day}`;
  }

  // ---------- internals ----------

  private static async ensureLoaded(): Promise<void> {
    if (SessionLedger.cache === null) await SessionLedger.init();
  }
}
