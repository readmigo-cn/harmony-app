import { HttpClient } from '../../api/client/HttpClient';

/**
 * Widget backend API client. 与 server-cn 路由对齐：
 *   GET /widget/daily-word              （legacy public，no-auth, 24h cache）
 *   GET /widget/daily-word/me           （JWT，优先返回 due 生词，否则池）
 *   GET /widget/reading-progress        （JWT，最近阅读书籍）
 *   GET /widget/ai-tip                  （JWT，7 天轮换贴士）
 *
 * NOTE: 卡片宿主进程是 FormExtensionAbility，运行在独立 sandbox。
 * 鉴权 token 通过 PreferencesManager 共享读到的 access_token（与主进程同 store）。
 */

// ---------- DTOs ----------

export interface DailyWordCardData {
  word: string;
  partOfSpeech: string;
  definition: string;
  exampleEn: string;
  exampleZh: string;
  date: string;
  /** 来自用户生词本（true）还是公共池（false） */
  fromVocab?: boolean;
  vocabId?: string;
}

export interface ReadingProgressCardData {
  bookId: string | null;
  bookTitle?: string;
  coverUrl?: string;
  chapterTitle?: string;
  percentComplete: number;
  currentChapterIndex: number;
  /** 累计阅读分钟（全部时长，非今日） */
  totalReadMinutes: number;
  /** 今日已读分钟（widget 端可叠加 session 状态） */
  todayMinutes?: number;
  /** 连续打卡天数 */
  streakDays?: number;
  /** 推荐下本书 */
  recommendBookId?: string;
  recommendBookTitle?: string;
  lastReadAt: string | null;
}

export interface AiTipCardData {
  tip: string;
  /** day-of-week 0–6，用于轮换标识 */
  day: number;
}

// ---------- Client ----------

export class WidgetApi {
  /** 公共池每日单词，no-auth，24h 缓存 */
  static getDailyWordPublic(): Promise<DailyWordCardData> {
    return HttpClient.get<DailyWordCardData>('/widget/daily-word', undefined, { auth: false });
  }

  /** 个性化每日单词，优先返回到期生词，回退到公共池 */
  static getDailyWord(): Promise<DailyWordCardData> {
    return HttpClient.get<DailyWordCardData>('/widget/daily-word/me');
  }

  /** 最近阅读书籍 + 进度（widget 用） */
  static getReadingProgress(): Promise<ReadingProgressCardData> {
    return HttpClient.get<ReadingProgressCardData>('/widget/reading-progress');
  }

  /** 每日 AI 学习贴士（7 天轮换） */
  static getAiTip(): Promise<AiTipCardData> {
    return HttpClient.get<AiTipCardData>('/widget/ai-tip');
  }
}
