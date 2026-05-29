import { ReadingStore } from '../../../store/ReadingStore';
import { SessionLedger, SessionRecord } from './SessionLedger';

/**
 * 阅读连续天数（streak）服务。
 *
 * 算法（computeStreak）：
 *   1. 取所有 records 的 endedDate（YYYY-MM-DD），去重
 *   2. 起点：今天有 session → 今天；今天无 + 昨天有 → 昨天（允许今天补打卡）；
 *      否则 streak=0（已断卡）
 *   3. 从起点向前逐日检查，连续找到为止
 *
 * 调用：
 *   - 启动时 init() → 加载 ledger + 重算 + 回灌 ReadingStore.streakDays
 *   - 会话结束时 recordSessionEnd(meta) → append + 重算
 *   - UI 用 ReadingStore.getStreak() 直接读（已被 init/record 同步更新）
 *
 * 与 server 的关系：server-cn /reading/stats 不返回 streak，故纯客户端。
 * 多设备：每台设备各自基于本地 ledger 算；ledger 跨设备同步留 B.3+。
 */
export class StreakService {
  private static inited: boolean = false;

  static async init(): Promise<void> {
    if (StreakService.inited) return;
    StreakService.inited = true;
    await SessionLedger.init();
    await StreakService.recompute();
  }

  /**
   * Reader / AudioPlayer 在 ReadingApi.endSession 成功后调一次。
   * 把会话记入 ledger 并立刻重算 streak 回灌 store。
   */
  static async recordSessionEnd(meta: {
    sessionId: string;
    bookId: string;
    startedAtMs: number;
    endedAtMs: number;
    charactersRead?: number;
  }): Promise<void> {
    const rec: SessionRecord = {
      sessionId: meta.sessionId,
      bookId: meta.bookId,
      startedAtMs: meta.startedAtMs,
      endedAtMs: meta.endedAtMs,
      durationMs: meta.endedAtMs - meta.startedAtMs,
      charactersRead: meta.charactersRead,
      endedDate: SessionLedger.formatLocalDate(meta.endedAtMs),
    };
    await SessionLedger.append(rec);
    await StreakService.recompute();
  }

  /** 强制重算（启动 / 后台拉新数据后调用）。 */
  static async recompute(): Promise<number> {
    const records = await SessionLedger.all();
    const streak = StreakService.computeStreak(records);
    ReadingStore.setStreak(streak);
    return streak;
  }

  /**
   * 纯函数：从 records 算出当前连续天数。
   * 对调用方暴露便于单元测试（无副作用，可注入 mock records）。
   */
  static computeStreak(records: SessionRecord[]): number {
    if (records.length === 0) return 0;
    const days = new Set<string>();
    for (let i = 0; i < records.length; i++) days.add(records[i].endedDate);
    const todayMs = Date.now();
    const today = SessionLedger.formatLocalDate(todayMs);
    const yesterday = SessionLedger.formatLocalDate(todayMs - 24 * 60 * 60 * 1000);

    let cursorMs: number;
    if (days.has(today)) {
      cursorMs = todayMs;
    } else if (days.has(yesterday)) {
      cursorMs = todayMs - 24 * 60 * 60 * 1000;
    } else {
      return 0;
    }

    let streak = 0;
    while (days.has(SessionLedger.formatLocalDate(cursorMs))) {
      streak += 1;
      cursorMs -= 24 * 60 * 60 * 1000;
    }
    return streak;
  }

  static getCurrentStreak(): number {
    return ReadingStore.getStreak();
  }
}
