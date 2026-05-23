/**
 * LlmAdapter.ets — W10-C3 LLM 适配层（ArkTS 端）
 *
 * 主旨：
 *   - 默认走后端代理 `/api/v1/ai/*`，由 server-cn 选择 provider（DeepSeek / Qwen / 文心 / 智谱）
 *     —— 服务端密钥不下发到客户端，符合中国市场合规要求
 *   - 同时抽出 provider switch 接口，POC 场景允许客户端直连（内部实验，默认关闭）
 *
 * Provider 模式：
 *   - 'server-proxy'   (default) → 走 HttpClient + AiApi，等同现有调用链
 *   - 'direct-deepseek' / 'direct-qwen' → 客户端持密钥直连 OpenAI 兼容协议（仅 POC）
 *
 * 接口：
 *   - chat(messages, opts?)            → Promise<string>
 *   - chatStream(messages, opts, sink) → () => void   返回 stop()
 *   - embeddings(text)                 → Promise<number[]>   预留 W12 向量检索
 *   - getQuota()                       → Promise<QuotaStatus>
 *
 * 跨调用复用：
 *   - 重试 + 超时 + 退避配置直接复用 HttpClient 的 RequestOptions
 *   - SSE 流式直接复用 SseClient（与 AiApi 一致）
 *   - Token 估算：本地粗略 4 chars ≈ 1 token，便于客户端裁剪 prompt 长度
 */

import http from '@ohos.net.http';
import { HttpClient, RequestOptions, ApiError } from '../../../api/client/HttpClient';
import { SseClient } from '../../../api/client/SseClient';
import { ApiConfig } from '../../../api/client/ApiConfig';
import { UserStore } from '../../../store/UserStore';
import { AiApi, QuotaStatus } from '../../../api/ai/AiApi';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type LlmRole = 'system' | 'user' | 'assistant';

export interface LlmMessage {
  role: LlmRole;
  content: string;
}

export type LlmProvider = 'server-proxy' | 'direct-deepseek' | 'direct-qwen';

export interface LlmCallOptions {
  /** 覆盖默认 provider（默认 server-proxy） */
  provider?: LlmProvider;
  /** 模型 ID；server-proxy 下被服务端忽略 */
  model?: string;
  /** 温度 0~2，默认 0.7 */
  temperature?: number;
  /** 最大输出 token，默认 1024 */
  maxTokens?: number;
  /** 单次请求超时（ms） */
  timeoutMs?: number;
  /** 重试次数，默认 1（与 HttpClient default=2 区分：LLM 重试代价更高） */
  retries?: number;
  /** 关联书籍 / 章节，用于服务端配额统计 + 个性化 prompt */
  bookId?: string;
  chapterIndex?: number;
}

export interface LlmStreamSink {
  onChunk: (delta: string) => void;
  onDone?: (full: string) => void;
  onError?: (err: Error) => void;
}

interface ServerChatResponse {
  /** 服务端返回的完整文本 */
  text: string;
  /** 用量统计（可选） */
  promptTokens?: number;
  completionTokens?: number;
}

interface ServerEmbeddingResponse {
  embedding: number[];
  /** 维度（如 1536 / 1024） */
  dim: number;
}

// 直连 provider 的最小配置（Settings 注入；缺失时拒绝直连）
interface DirectProviderConfig {
  baseUrl: string;
  apiKey: string;
  defaultModel: string;
}

// ---------------------------------------------------------------------------
// 默认参数
// ---------------------------------------------------------------------------

const DEFAULT_TEMPERATURE = 0.7;
const DEFAULT_MAX_TOKENS = 1024;
const DEFAULT_TIMEOUT_MS = 60_000;
const DEFAULT_RETRIES = 1;

// ---------------------------------------------------------------------------
// LlmAdapter 主类
// ---------------------------------------------------------------------------

export class LlmAdapter {
  /** 当前进程默认 provider；可由 Settings 在启动时调用 setDefaultProvider 改写 */
  private static defaultProvider: LlmProvider = 'server-proxy';

  /** direct-* 配置（仅 POC；正式环境留空 → 自动 fallback 到 server-proxy） */
  private static directConfigs: Map<LlmProvider, DirectProviderConfig> = new Map();

  // ─── 配置 ───────────────────────────────────────────────────────────────

  static setDefaultProvider(p: LlmProvider): void {
    LlmAdapter.defaultProvider = p;
  }

  static configureDirectProvider(p: LlmProvider, cfg: DirectProviderConfig): void {
    if (p === 'server-proxy') return;
    LlmAdapter.directConfigs.set(p, cfg);
  }

  // ─── 公共接口 ───────────────────────────────────────────────────────────

  /** 单次同步调用，返回完整文本。 */
  static async chat(messages: LlmMessage[], opts: LlmCallOptions = {}): Promise<string> {
    const provider = opts.provider ?? LlmAdapter.defaultProvider;
    if (provider === 'server-proxy' || !LlmAdapter.directConfigs.has(provider)) {
      return LlmAdapter.chatViaProxy(messages, opts);
    }
    return LlmAdapter.chatDirect(provider, messages, opts);
  }

  /**
   * 流式调用，返回 stop() 函数。完整文本通过 sink.onDone(full) 回调一次。
   * direct-* 模式下未实现流式（OpenAI SSE 解析复杂），自动 fallback 到 chat() + 一次性 chunk。
   */
  static chatStream(messages: LlmMessage[], opts: LlmCallOptions, sink: LlmStreamSink): () => void {
    const provider = opts.provider ?? LlmAdapter.defaultProvider;
    if (provider !== 'server-proxy') {
      // 直连暂不支持真流；fallback：发起一次同步 chat，把结果当一个 chunk 推
      let aborted = false;
      LlmAdapter.chat(messages, opts).then((full) => {
        if (aborted) return;
        sink.onChunk(full);
        sink.onDone?.(full);
      }).catch((err: Error) => {
        if (!aborted) sink.onError?.(err);
      });
      return () => { aborted = true; };
    }
    return LlmAdapter.chatStreamViaProxy(messages, opts, sink);
  }

  /** 文本嵌入（W12+ 向量检索用）。仅 server-proxy 实现。 */
  static async embeddings(text: string, opts: LlmCallOptions = {}): Promise<number[]> {
    const reqOpts: RequestOptions = {
      timeoutMs: opts.timeoutMs ?? DEFAULT_TIMEOUT_MS,
      retries: opts.retries ?? DEFAULT_RETRIES,
    };
    const resp = await HttpClient.post<ServerEmbeddingResponse>(
      '/api/v1/ai/embeddings',
      { text, model: opts.model },
      reqOpts,
    );
    return resp.embedding;
  }

  /** 当日配额状态（与 paywall 联动）。直接复用 AiApi.getQuotaStatus。 */
  static getQuota(): Promise<QuotaStatus> {
    return AiApi.getQuotaStatus();
  }

  /**
   * 粗略 token 计数估算：英文 4 chars ≈ 1 token，中文 1 char ≈ 1.2 token。
   * 仅用于客户端裁剪 prompt（防止超长），服务端会重新精确计费。
   */
  static estimateTokens(text: string): number {
    if (!text) return 0;
    let cjk = 0;
    let other = 0;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      // CJK 基本区 + 扩展 A
      if ((code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF)) {
        cjk += 1;
      } else {
        other += 1;
      }
    }
    return Math.ceil(cjk * 1.2 + other / 4);
  }

  /** 估算多条 message 总 token（含 role overhead 4 token / msg）。 */
  static estimateMessagesTokens(messages: LlmMessage[]): number {
    let sum = 0;
    for (const m of messages) {
      sum += LlmAdapter.estimateTokens(m.content) + 4;
    }
    return sum;
  }

  // ─── server-proxy 实现 ─────────────────────────────────────────────────

  private static async chatViaProxy(messages: LlmMessage[], opts: LlmCallOptions): Promise<string> {
    const reqOpts: RequestOptions = {
      timeoutMs: opts.timeoutMs ?? DEFAULT_TIMEOUT_MS,
      retries: opts.retries ?? DEFAULT_RETRIES,
    };
    const body: Record<string, unknown> = {
      messages,
      model: opts.model,
      temperature: opts.temperature ?? DEFAULT_TEMPERATURE,
      maxTokens: opts.maxTokens ?? DEFAULT_MAX_TOKENS,
      bookId: opts.bookId,
      chapterIndex: opts.chapterIndex,
    };
    const resp = await HttpClient.post<ServerChatResponse>('/api/v1/ai/chat', body, reqOpts);
    return resp.text;
  }

  private static chatStreamViaProxy(
    messages: LlmMessage[],
    opts: LlmCallOptions,
    sink: LlmStreamSink,
  ): () => void {
    const body: Record<string, unknown> = {
      messages,
      model: opts.model,
      temperature: opts.temperature ?? DEFAULT_TEMPERATURE,
      maxTokens: opts.maxTokens ?? DEFAULT_MAX_TOKENS,
      bookId: opts.bookId,
      chapterIndex: opts.chapterIndex,
    };
    let full = '';
    return SseClient.stream('/api/v1/ai/chat/stream', body, {
      onMessage: (raw: string) => {
        try {
          const parsed = JSON.parse(raw) as { delta?: string; done?: boolean; error?: string };
          if (parsed.error) {
            sink.onError?.(new Error(parsed.error));
            return;
          }
          if (parsed.delta) {
            full += parsed.delta;
            sink.onChunk(parsed.delta);
          }
          if (parsed.done) {
            sink.onDone?.(full);
          }
        } catch (_e) {
          full += raw;
          sink.onChunk(raw);
        }
      },
      onDone: () => sink.onDone?.(full),
      onError: (err: Error) => sink.onError?.(err),
    });
  }

  // ─── direct-* 实现（OpenAI 兼容，POC） ─────────────────────────────────

  private static async chatDirect(
    provider: LlmProvider,
    messages: LlmMessage[],
    opts: LlmCallOptions,
  ): Promise<string> {
    const cfg = LlmAdapter.directConfigs.get(provider);
    if (!cfg) {
      throw new ApiError(-1, `direct provider ${provider} not configured`, 0);
    }
    const httpReq = http.createHttp();
    try {
      const url = `${cfg.baseUrl.replace(/\/$/, '')}/chat/completions`;
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${cfg.apiKey}`,
      };
      const body = {
        model: opts.model ?? cfg.defaultModel,
        messages,
        temperature: opts.temperature ?? DEFAULT_TEMPERATURE,
        max_tokens: opts.maxTokens ?? DEFAULT_MAX_TOKENS,
        stream: false,
      };
      const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
      const resp = await httpReq.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
      });
      const text = typeof resp.result === 'string'
        ? resp.result
        : new TextDecoder('utf-8').decode(resp.result as ArrayBuffer);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new ApiError(resp.responseCode, `direct_http_${resp.responseCode}`, resp.responseCode, { body: text });
      }
      const parsed = JSON.parse(text) as {
        choices?: { message?: { content?: string } }[];
      };
      const content = parsed.choices?.[0]?.message?.content ?? '';
      return content;
    } finally {
      httpReq.destroy();
    }
  }
}

// 兼容字面量导出（让其他模块用 import { QuotaStatus } from './LlmAdapter' 也能拿到）
export { QuotaStatus };
