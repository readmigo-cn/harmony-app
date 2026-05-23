/**
 * StudyPlanApi — W9-C6/C7 学习计划 + 阅读理解题
 *
 * 服务端没有专门的 study-plan / comprehension 端点，本类通过 AiApi.contentQA
 * 配特殊 prompt 走 SSE 流，前端聚合 chunk 后再 JSON.parse 出结构化结果。
 *
 * 所有"AI 调用"用同一个 contentQA 通道：bookId 用 stub（'__study_plan__' /
 * `__comprehension__:${bookId}`），chapterIndex 用 0，question 字段塞 JSON
 * payload，服务端 prompt 模板会原样透传给 LLM。
 */

import { AiApi, ContentQAPayload } from '../ai/AiApi';

// ---- StudyPlan 类型 -----------------------------------------------------

export type CefrLevel = 'A1' | 'A2' | 'B1' | 'B2' | 'C1' | 'C2';

export interface StudyPlanInput {
  /** 当前 CEFR 等级 */
  currentLevel: CefrLevel;
  /** 目标 CEFR 等级 */
  targetLevel: CefrLevel;
  /** 每日可学习时长（分钟） */
  dailyMinutes: number;
  /** 兴趣主题（中英文标签皆可） */
  interests: string[];
  /** 截止日期 ISO 8601（可选） */
  deadline?: string;
}

export interface StudyTask {
  id: string;
  /** 任务类型 */
  kind: 'reading' | 'review' | 'listening' | 'writing' | 'quiz';
  title: string;
  /** 预计时长（分钟） */
  minutes: number;
  /** 是否已完成（本地态） */
  completed: boolean;
}

export interface DailyPlan {
  /** 第 N 天，1-based */
  day: number;
  /** ISO 8601 日期（可选；前端按 startedAt + day 推算） */
  date?: string;
  tasks: StudyTask[];
}

export interface WeeklyMilestone {
  week: number;
  goal: string;
}

export interface StudyPlan {
  id: string;
  input: StudyPlanInput;
  /** 总天数 */
  totalDays: number;
  /** 已完成天数（前端聚合 daily.tasks.completed 算出） */
  completedDays: number;
  daily: DailyPlan[];
  milestones: WeeklyMilestone[];
  /** 推荐书籍 slug 列表 */
  recommendedBooks: string[];
  /** 复习节奏建议（自然语言） */
  reviewCadence: string;
  /** 计划创建时间 ISO 8601 */
  createdAt: string;
}

// ---- ReadingComprehension 类型 ------------------------------------------

export type QuestionType = 'mcq' | 'fill' | 'short';

export interface ComprehensionQuestion {
  id: string;
  bookId: string;
  chapterIndex: number;
  type: QuestionType;
  /** 原文引用片段（≤ 200 char） */
  quote: string;
  /** 题干 */
  prompt: string;
  /** 选择题选项（mcq 必填，4 选 1） */
  options?: string[];
  /** 标准答案（评分时用） */
  answer: string;
  /** 难度 1-5 */
  difficulty: number;
}

export interface AnswerEvaluation {
  questionId: string;
  /** 用户作答 */
  userAnswer: string;
  /** 是否正确 */
  correct: boolean;
  /** 0-100 分 */
  score: number;
  /** 解析（中文） */
  explanation: string;
  /** 标准答案 */
  reference: string;
}

export interface ComprehensionAttempt {
  id: string;
  bookId: string;
  chapterIndex: number;
  questions: ComprehensionQuestion[];
  evaluations: AnswerEvaluation[];
  /** 总分 0-100 */
  totalScore: number;
  /** 弱点反馈（自然语言） */
  weaknessFeedback: string;
  /** ISO 8601 */
  createdAt: string;
}

// ---- API ----------------------------------------------------------------

const STUB_BOOK_PLAN = '__study_plan__';

function genId(prefix: string): string {
  return `${prefix}_${Date.now().toString(36)}_${Math.floor(Math.random() * 1e6).toString(36)}`;
}

/**
 * 把 SSE chunk 聚合成完整字符串后尝试解析 JSON。
 * 服务端 LLM 经常会在 JSON 外包 ```json ... ``` 围栏，做一次 strip。
 */
function stripJsonFence(s: string): string {
  const trimmed = s.trim();
  if (trimmed.startsWith('```')) {
    const start = trimmed.indexOf('\n');
    const end = trimmed.lastIndexOf('```');
    if (start > 0 && end > start) return trimmed.substring(start + 1, end).trim();
  }
  return trimmed;
}

function aiInvokeJson(prompt: string, bookId: string = STUB_BOOK_PLAN): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const payload: ContentQAPayload = { bookId, chapterIndex: 0, question: prompt };
    let acc = '';
    const stop = AiApi.contentQA(payload, {
      onChunk: (delta: string) => { acc += delta; },
      onDone: () => resolve(stripJsonFence(acc)),
      onError: (e: Error) => reject(e),
    });
    // 30s 超时保护
    setTimeout(() => { stop(); if (acc.length === 0) reject(new Error('ai_timeout')); }, 30_000);
  });
}

export class StudyPlanApi {
  // ---- Plan ------------------------------------------------------------

  static async generatePlan(input: StudyPlanInput): Promise<StudyPlan> {
    const prompt = StudyPlanApi.buildPlanPrompt(input);
    const raw = await aiInvokeJson(prompt);
    const parsed = JSON.parse(raw) as Partial<StudyPlan>;
    const totalDays = parsed.totalDays ?? StudyPlanApi.estimateDays(input);
    const plan: StudyPlan = {
      id: genId('plan'),
      input,
      totalDays,
      completedDays: 0,
      daily: parsed.daily ?? [],
      milestones: parsed.milestones ?? [],
      recommendedBooks: parsed.recommendedBooks ?? [],
      reviewCadence: parsed.reviewCadence ?? '每 3 天复习一次新词',
      createdAt: new Date().toISOString(),
    };
    return plan;
  }

  /** 本地态更新 task.completed，并返回新的 plan（不写后端） */
  static async updatePlanProgress(plan: StudyPlan, taskId: string, completed: boolean): Promise<StudyPlan> {
    let changedDay = -1;
    for (const d of plan.daily) {
      for (const t of d.tasks) {
        if (t.id === taskId) {
          t.completed = completed;
          changedDay = d.day;
          break;
        }
      }
    }
    if (changedDay > 0) {
      plan.completedDays = plan.daily.filter((d) =>
        d.tasks.length > 0 && d.tasks.every((t) => t.completed),
      ).length;
    }
    return plan;
  }

  // ---- Comprehension ---------------------------------------------------

  static async generateComprehension(
    bookId: string,
    chapterIndex: number,
    /** 难度自适应：来自历史的弱项题型偏置（W9-C7） */
    weaknessBias?: Partial<Record<QuestionType, number>>,
  ): Promise<ComprehensionQuestion[]> {
    const prompt = StudyPlanApi.buildComprehensionPrompt(bookId, chapterIndex, weaknessBias);
    const raw = await aiInvokeJson(prompt, `__comprehension__:${bookId}`);
    const arr = JSON.parse(raw) as ComprehensionQuestion[];
    return arr.map((q, idx) => {
      const out: ComprehensionQuestion = {
        id: q.id ?? genId(`q${idx}`),
        bookId,
        chapterIndex,
        type: q.type,
        quote: q.quote ?? '',
        prompt: q.prompt,
        options: q.options,
        answer: q.answer,
        difficulty: q.difficulty ?? 3,
      };
      return out;
    });
  }

  static async submitAnswer(q: ComprehensionQuestion, userAnswer: string): Promise<AnswerEvaluation> {
    // 选择题本地评分省一次 AI 调用；填空 / 简答让 LLM 给解析
    if (q.type === 'mcq') {
      const correct = userAnswer.trim() === q.answer.trim();
      const evalRes: AnswerEvaluation = {
        questionId: q.id,
        userAnswer,
        correct,
        score: correct ? 100 : 0,
        explanation: correct ? '答对了。' : `正确答案：${q.answer}`,
        reference: q.answer,
      };
      return evalRes;
    }
    const prompt = StudyPlanApi.buildEvalPrompt(q, userAnswer);
    const raw = await aiInvokeJson(prompt, `__comprehension__:${q.bookId}`);
    const parsed = JSON.parse(raw) as Partial<AnswerEvaluation>;
    const evalOut: AnswerEvaluation = {
      questionId: q.id,
      userAnswer,
      correct: parsed.correct ?? false,
      score: parsed.score ?? 0,
      explanation: parsed.explanation ?? '',
      reference: q.answer,
    };
    return evalOut;
  }

  // ---- Prompt 模板 -----------------------------------------------------

  /** 学习计划生成 prompt（中文，要求严格 JSON） */
  private static buildPlanPrompt(input: StudyPlanInput): string {
    const days = StudyPlanApi.estimateDays(input);
    return [
      '你是一名英语学习教练。基于以下学员信息，输出一份个性化学习计划。',
      `当前 CEFR：${input.currentLevel}`,
      `目标 CEFR：${input.targetLevel}`,
      `每日可学习时长：${input.dailyMinutes} 分钟`,
      `兴趣主题：${input.interests.join('、') || '通用'}`,
      `计划总天数：${days} 天`,
      '',
      '严格按下列 JSON schema 输出，禁止任何额外解释、禁止代码围栏：',
      '{',
      '  "totalDays": number,',
      '  "daily": [{ "day": number, "tasks": [',
      '    { "id": string, "kind": "reading"|"review"|"listening"|"writing"|"quiz", "title": string, "minutes": number, "completed": false }',
      '  ] }],',
      '  "milestones": [{ "week": number, "goal": string }],',
      '  "recommendedBooks": [string],',
      '  "reviewCadence": string',
      '}',
      '',
      '约束：',
      `- daily 数组长度 = totalDays（最多 ${Math.min(days, 30)}，超过的按周期模板压缩）`,
      '- 每天 tasks 总分钟数 ≤ dailyMinutes',
      '- recommendedBooks 给 3-5 本，与 interests + 当前等级匹配（用 slug：pride-and-prejudice / alice-in-wonderland 这类）',
      '- milestones 每周 1 条',
    ].join('\n');
  }

  /** 阅读理解生成 prompt（W9-C7 难度自适应） */
  private static buildComprehensionPrompt(
    bookId: string,
    chapterIndex: number,
    weaknessBias?: Partial<Record<QuestionType, number>>,
  ): string {
    const biasNote = weaknessBias
      ? `用户在以下题型上历史正确率较低，请多出该类题（权重越大占比越高）：${JSON.stringify(weaknessBias)}。`
      : '题型分布：mcq 60%、fill 20%、short 20%。';
    return [
      `你是一名英语阅读理解出题老师。请根据书 ${bookId} 第 ${chapterIndex} 章生成 5 道阅读理解题。`,
      biasNote,
      '',
      '严格按下列 JSON 数组 schema 输出，禁止任何额外解释、禁止代码围栏：',
      '[',
      '  { "id": string, "type": "mcq"|"fill"|"short", "quote": string,',
      '    "prompt": string, "options": [string,string,string,string]?,',
      '    "answer": string, "difficulty": 1-5 }',
      ']',
      '',
      '约束：',
      '- mcq 必须 4 个 options，answer 是其中之一的完整文本',
      '- fill 的 prompt 含一个 "____" 空缺，answer 是填入文本',
      '- short 的 answer 是 1-2 句中文参考答案',
      '- quote 来自原文，最多 200 字符',
    ].join('\n');
  }

  /** fill / short 题评分 prompt */
  private static buildEvalPrompt(q: ComprehensionQuestion, userAnswer: string): string {
    return [
      '你是一名英语阅读理解评分老师。基于参考答案给学员作答评分。',
      `题型：${q.type}`,
      `题干：${q.prompt}`,
      `参考答案：${q.answer}`,
      `学员作答：${userAnswer}`,
      '',
      '严格按下列 JSON schema 输出（中文 explanation），禁止围栏：',
      '{ "correct": boolean, "score": 0-100, "explanation": string }',
    ].join('\n');
  }

  /** 估算总天数：dailyMinutes 不变情况下，跨级别需要约 60-180 天 */
  private static estimateDays(input: StudyPlanInput): number {
    if (input.deadline) {
      const ms = new Date(input.deadline).getTime() - Date.now();
      const d = Math.max(7, Math.floor(ms / 86400_000));
      return Math.min(d, 365);
    }
    const levelOrder: CefrLevel[] = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
    const gap = Math.max(1, levelOrder.indexOf(input.targetLevel) - levelOrder.indexOf(input.currentLevel));
    return Math.min(30 + gap * 30, 180);
  }
}
