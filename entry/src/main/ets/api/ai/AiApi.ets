import { HttpClient } from '../../api/client/HttpClient';
import { SseClient } from '../../api/client/SseClient';

/**
 * AiApi — server-cn AI 端点全量封装
 *
 * 架构决策：ALL AI calls go through the backend (/api/v1/ai/*).
 * The backend holds LLM provider keys (DeepSeek / Qwen / Claude) and handles
 * billing, rate-limiting, and abuse control. Clients NEVER call LLM providers
 * directly in production. SseClient targets backend SSE endpoints only.
 *
 * Endpoints:
 *   - /ai/explain/word(/stream)     划词解释（同步 + SSE）
 *   - /ai/translate/sentence(/stream) 整句翻译（同步 + SSE）
 *   - /ai/content/qa/stream         内容问答（SSE，conversationId 复用 → 多轮）
 *   - /ai/summarize/stream          章节摘要（SSE）
 *   - /ai/analyze-weakness          弱点分析（同步，返回 JSON）
 *   - /ai/generate-question         出题（同步，返回 JSON）
 *   - /ai/quota                     当前用户 AI 调用配额
 *   - /ai/conversations             会话列表 / 删除
 *
 * SSE 格式：每条事件是 JSON `{delta?: string, done?: boolean, error?: string}`
 * 每个 stream 函数返回 `() => void` 用于中止连接（拷贝自 SseClient）
 */

// ---------------------------------------------------------------------------
// Payload / Response 类型定义
// ---------------------------------------------------------------------------

/** 划词解释入参 */
export interface ExplainWordPayload {
  word: string;
  context: string;
  /** 用户当前界面语言；服务端据此选 zh-CN 或 zh-TW 释义 */
  locale?: 'zh-CN' | 'zh-TW' | 'en';
  /** CEFR 难度，影响释义繁简度 */
  cefrLevel?: 'A1' | 'A2' | 'B1' | 'B2' | 'C1' | 'C2';
  /** 关联书籍 ID（用于个性化 + 配额统计） */
  bookId?: string;
}

/** 翻译入参 */
export interface TranslatePayload {
  text: string;
  /** 源语言；'auto' 让服务端自动识别 */
  from: 'en' | 'zh' | 'auto';
  /** 目标语言 */
  to: 'en' | 'zh';
  /** 关联书籍 ID（可选） */
  bookId?: string;
}

/** 内容问答入参 */
export interface ContentQAPayload {
  bookId: string;
  chapterIndex: number;
  question: string;
  /** 已存在的会话 ID；不传则服务端创建新会话 */
  conversationId?: string;
}

/** 同步 explain/translate 响应（非流式版本） */
export interface ExplainResponse {
  /** 服务端原始 raw 文本（可能是 JSON 字符串） */
  raw: string;
  /** 服务端如果已经解析过，直接给结构化字段 */
  word?: string;
  partOfSpeech?: string;
  definition?: string;
  exampleEn?: string;
  exampleZh?: string;
  pronunciation?: string;
  etymology?: string;
}

export interface TranslateResponse {
  translated: string;
  detectedFrom?: 'en' | 'zh';
}

/** 配额状态（用于 paywall 触达判断） */
export interface QuotaStatus {
  /** 当日已用次数 */
  used: number;
  /** 当日总额度（未订阅 free / 订阅 pro 不同） */
  total: number;
  /** 是否已超额 */
  exceeded: boolean;
  /** 下一次重置时间 ISO 8601 */
  resetAt: string;
  /** 当前用户订阅 tier */
  tier: 'free' | 'pro' | 'premium';
}

/** 会话列表项 */
export interface ConversationItem {
  id: string;
  kind: 'qa' | 'explain' | 'translate';
  bookId?: string;
  chapterIndex?: number;
  /** 首条消息预览（30 字截断） */
  preview: string;
  /** 消息数 */
  messageCount: number;
  /** ISO 8601 创建时间 */
  createdAt: string;
  /** ISO 8601 最后更新时间 */
  updatedAt: string;
}

export interface ConversationListResponse {
  items: ConversationItem[];
  page: number;
  pageSize: number;
  total: number;
}

// ---------------------------------------------------------------------------
// SSE handler 接口
// ---------------------------------------------------------------------------

export interface SseHandlers {
  /** 收到 delta 文本片段 */
  onChunk: (delta: string) => void;
  /** 收到完整结束信号 */
  onDone?: () => void;
  /** 出错（含 server 端 {error: ...} / 网络错误） */
  onError?: (err: Error) => void;
}

/** ExplainStreamHandlers 兼容旧名称（WordExplainSheet 在用） */
export type ExplainStreamHandlers = SseHandlers;

// ---------------------------------------------------------------------------
// AiApi 主类
// ---------------------------------------------------------------------------

export class AiApi {
  // ---- 划词解释 ----------------------------------------------------------

  /**
   * 流式划词解释。返回 stop() 函数中止连接。
   *
   * 优先尝试新路径 /ai/explain/word/stream；服务端如果未上线该路径会返回 404，
   * 上层通过 onError 处理（Reader 暂时不区分新旧路径）。
   */
  static explainWordStream(payload: ExplainWordPayload, handlers: SseHandlers): () => void {
    return SseClient.stream('/ai/explain/word/stream', payload, AiApi.wrapJsonHandlers(handlers));
  }

  /** 同步版本（用于 prefetch / 缓存命中场景） */
  static explainWord(payload: ExplainWordPayload): Promise<ExplainResponse> {
    return HttpClient.post<ExplainResponse>('/ai/explain/word', payload);
  }

  // ---- 翻译 --------------------------------------------------------------

  /**
   * 同步整句翻译（W8-B 主用入口）。
   * 短句首选，长段落建议走 stream。
   */
  static translateSentence(payload: TranslatePayload): Promise<TranslateResponse> {
    return HttpClient.post<TranslateResponse>('/ai/translate/sentence', payload);
  }

  /** 流式整句翻译（W8-B 长文本场景） */
  static translateSentenceStream(payload: TranslatePayload, handlers: SseHandlers): () => void {
    return SseClient.stream('/ai/translate/sentence/stream', payload, AiApi.wrapJsonHandlers(handlers));
  }

  /** 兼容旧名 translate（保留给已写好的调用方） */
  static translate(payload: { text: string; from: 'en' | 'zh'; to: 'en' | 'zh' }): Promise<{ translated: string }> {
    return HttpClient.post<{ translated: string }>('/ai/translate', payload);
  }

  // ---- 内容问答 ----------------------------------------------------------

  /**
   * 流式内容问答（多轮对话）。
   * conversationId 复用：第一轮服务端返回新 id，后续轮请求带上即可。
   * 返回 stop() 函数中止流式连接。
   */
  static contentQA(payload: ContentQAPayload, handlers: SseHandlers): () => void {
    return SseClient.stream('/ai/content/qa/stream', payload, AiApi.wrapJsonHandlers(handlers));
  }

  // ---- 章节摘要 ----------------------------------------------------------

  /** 流式章节摘要。返回 stop() 函数中止流式连接。 */
  static summarizeStream(
    payload: { bookId: string; chapterIndex: number; targetLanguage?: 'zh-CN' | 'en' },
    handlers: SseHandlers,
  ): () => void {
    return SseClient.stream('/ai/summarize/stream', payload, AiApi.wrapJsonHandlers(handlers));
  }

  // ---- 弱点分析 ----------------------------------------------------------

  /** 同步弱点分析，返回 JSON 报告（服务端根据用户 SRS/阅读历史生成）。 */
  static analyzeWeakness(payload: { userId?: string }): Promise<Record<string, unknown>> {
    return HttpClient.post<Record<string, unknown>>('/ai/analyze-weakness', payload);
  }

  // ---- 出题 --------------------------------------------------------------

  /** 同步出题，返回 JSON 题目（难度 + 题型由 payload 指定）。 */
  static generateQuestion(payload: {
    bookId: string;
    chapterIndex: number;
    difficulty: 'easy' | 'medium' | 'hard';
    type: 'mcq' | 'fill' | 'short';
    weaknessBias?: Record<string, number>;
  }): Promise<Record<string, unknown>> {
    return HttpClient.post<Record<string, unknown>>('/ai/generate-question', payload);
  }

  // ---- 配额 --------------------------------------------------------------

  /** 查询当前用户当日配额状态 */
  static getQuotaStatus(): Promise<QuotaStatus> {
    return HttpClient.get<QuotaStatus>('/ai/quota');
  }

  // ---- 会话历史 ----------------------------------------------------------

  /**
   * 列出当前用户的 AI 会话。
   * @param kind  过滤会话类型（不传 = 全部）
   * @param page  1-based 页码
   * @param pageSize 单页条数（默认 20，最大 100）
   */
  static listConversations(
    kind?: 'qa' | 'explain' | 'translate',
    page: number = 1,
    pageSize: number = 20,
  ): Promise<ConversationListResponse> {
    const query: Record<string, string | number> = { page, pageSize };
    if (kind) query.kind = kind;
    return HttpClient.get<ConversationListResponse>('/ai/conversations', query);
  }

  /** 删除指定会话（含其下所有消息） */
  static deleteConversation(id: string): Promise<void> {
    return HttpClient.delete<void>(`/ai/conversations/${encodeURIComponent(id)}`);
  }

  // ---- 内部辅助 ----------------------------------------------------------

  /**
   * 把 SseClient 的原始 onMessage(rawData) 包成 onChunk(delta)：
   *  - rawData 是 JSON  → 解析 {delta, done, error}
   *  - rawData 不是 JSON → 当 raw 透传（兼容服务端旧实现）
   */
  private static wrapJsonHandlers(handlers: SseHandlers): { onMessage: (data: string) => void; onDone?: () => void; onError?: (e: Error) => void } {
    return {
      onMessage: (rawData: string) => {
        try {
          const parsed = JSON.parse(rawData) as { delta?: string; done?: boolean; error?: string };
          if (parsed.error) {
            handlers.onError?.(new Error(parsed.error));
            return;
          }
          if (parsed.delta) handlers.onChunk(parsed.delta);
          if (parsed.done) handlers.onDone?.();
        } catch (_e) {
          handlers.onChunk(rawData);
        }
      },
      onDone: () => handlers.onDone?.(),
      onError: (e: Error) => handlers.onError?.(e),
    };
  }
}
