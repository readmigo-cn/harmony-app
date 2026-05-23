import { HttpClient } from '../../api/client/HttpClient';

/**
 * StatsApi — W9-C5 + C8 学习数据 / 弱点分析
 *
 * 与 server-cn 路由对齐：
 *   GET  /api/v1/notes/srs/stats           SRS 复习统计（生词本）
 *   GET  /api/v1/reading/stats             阅读统计（时长 / 字数 / streak）
 *   POST /api/v1/ai/weakness/report        AI 生成弱点报告（占位 prompt）
 *   GET  /api/v1/ai/weakness/history       历史报告列表
 *
 * 服务端部分端点尚在迭代，本类返回结构以本地 UI 期望为 source of truth；
 * 缺字段的旧 server 由 fallback 兼容（详见 mergeReadingStats）。
 */

// ---------------------------------------------------------------------------
// 统计周期
// ---------------------------------------------------------------------------

export type StatsPeriod = 'today' | 'week' | 'month' | 'all';

// ---------------------------------------------------------------------------
// 词汇量统计
// ---------------------------------------------------------------------------

/** CEFR 等级分布桶 */
export interface CefrBucket {
  /** A1 / A2 / B1 / B2 / C1 / C2 */
  level: string;
  /** 该等级词汇数量 */
  count: number;
}

/** 词性分布桶 */
export interface PosBucket {
  /** noun / verb / adj / adv / prep / conj / pron / interj / other */
  pos: string;
  /** 该词性词汇数量 */
  count: number;
}

/** 7 天 sparkline 单点 */
export interface SparkPoint {
  /** ISO 日期 yyyy-MM-dd */
  date: string;
  /** 当日新增词数 */
  count: number;
}

/** 词汇量统计响应 */
export interface VocabStats {
  /** 总词汇量（去重） */
  totalWords: number;
  /** 估算 CEFR 等级（A1/A2/B1/B2/C1/C2） */
  estimatedLevel: string;

  /** 今日新增词汇 */
  todayAdded: number;
  /** 本周复习次数 */
  weekReviewed: number;
  /** 本周复习准确率 0~1 */
  weekAccuracy: number;

  /** 已掌握词数（quality >= 4 且复习≥3 次） */
  mastered: number;
  /** 已掌握占比 0~1 */
  masteredRatio: number;

  /** 待复习词数（dueAt <= now） */
  dueCount: number;
  /** 紧急度：0 ~ 1（dueCount / totalDue 估算） */
  urgency: number;

  /** 学习连续天数 */
  streakDays: number;

  /** CEFR 分布 */
  cefrDistribution: CefrBucket[];
  /** 词性分布 */
  posDistribution: PosBucket[];
  /** 最近 7 天新增 sparkline */
  recentSpark: SparkPoint[];
}

// ---------------------------------------------------------------------------
// 阅读统计
// ---------------------------------------------------------------------------

export interface ReadingStats {
  /** 累计阅读时长（分钟） */
  totalMinutes: number;
  /** 当前周期阅读时长（分钟，跟随 period） */
  periodMinutes: number;
  /** 累计完成章节数 */
  chaptersFinished: number;
  /** 累计完成书数 */
  booksFinished: number;
}

// ---------------------------------------------------------------------------
// 弱点分析
// ---------------------------------------------------------------------------

export interface WeakWord {
  word: string;
  /** 平均 quality 0~5 */
  avgQuality: number;
  /** 复习次数 */
  reviewCount: number;
  /** 失败次数 */
  failureCount: number;
}

export interface WeakPos {
  pos: string;
  /** 该词性正确率 0~1 */
  accuracy: number;
  /** 样本量 */
  sampleSize: number;
}

export interface WeakTopic {
  /** 书 / 主题名 */
  topic: string;
  /** 该主题准确率 0~1 */
  accuracy: number;
  /** 词汇数 */
  wordCount: number;
}

export interface WeaknessReport {
  /** 报告 ID（服务端持久化主键） */
  id: string;
  /** ISO 8601 生成时间 */
  generatedAt: string;
  /** 一句话总结（LLM） */
  summary: string;
  /** 易错词 Top 10 */
  weakWords: WeakWord[];
  /** 易错词性 */
  weakPos: WeakPos[];
  /** 易错主题 */
  weakTopics: WeakTopic[];
  /** 推荐补强方向（自然语言 bullet 列表） */
  recommendations: string[];
}

export interface WeaknessHistoryItem {
  id: string;
  generatedAt: string;
  summary: string;
}

// ---------------------------------------------------------------------------
// StatsApi 主类
// ---------------------------------------------------------------------------

export class StatsApi {
  /**
   * 获取词汇量统计。
   * @param period 时间维度，默认 all
   */
  static async getVocabStats(period: StatsPeriod = 'all'): Promise<VocabStats> {
    return HttpClient.get<VocabStats>('/api/v1/notes/srs/stats', { period });
  }

  /**
   * 获取阅读统计。
   * @param period 时间维度，默认 all
   */
  static async getReadingStats(period: StatsPeriod = 'all'): Promise<ReadingStats> {
    return HttpClient.get<ReadingStats>('/api/v1/reading/stats', { period });
  }

  /**
   * 触发 AI 生成弱点报告。
   *
   * 服务端 prompt 设计（占位，等 server-cn 实现）：
   *   System: "你是英语学习教练。基于学生的 SRS 复习历史 + 阅读数据，
   *   给出三段式弱点分析：(1)易错词 Top 10 (2)易错词性 (3)易错主题，
   *   并给 3 条针对性补强建议。输出严格 JSON。"
   *   User: <serialized stats>
   */
  static async generateWeaknessReport(): Promise<WeaknessReport> {
    return HttpClient.post<WeaknessReport>('/api/v1/ai/weakness/report', {});
  }

  /**
   * 历史报告列表（最近 N 份，默认 5）。
   */
  static async getWeaknessHistory(limit: number = 5): Promise<WeaknessHistoryItem[]> {
    return HttpClient.get<WeaknessHistoryItem[]>('/api/v1/ai/weakness/history', { limit });
  }
}
