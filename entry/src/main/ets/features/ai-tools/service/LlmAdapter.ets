/**
 * LlmAdapter.ets — W4 LLM 适配层（ArkTS 端）
 *
 * Provider 模式：
 *   - 'server-proxy'   (default) → 走 HttpClient + AiApi，后端转发给 LLM provider
 *   - 'direct-deepseek' / 'direct-qwen' → POC 直连 OpenAI 兼容协议（仅内部实验）
 *
 * 接口：
 *   - chat(messages, opts?)                         → Promise<string>
 *   - chatStream(messages, opts, sink)              → () => void   返回 stop()
 *   - stream(prompt, opts?)                         → { iterator: AsyncIterableIterator<string>; abort: () => void }
 *   - complete(prompt, opts?)                       → Promise<string>
 *   - embeddings(text)                              → Promise<number[]>
 *   - getQuota()                                    → Promise<QuotaStatus>
 *   - configure(cfg)                                → void  (singleton 配置)
 *
 * 所有后端 AI 调用走 /api/v1/ai/* 端点，服务端持密钥，客户端不暴露。
 */

import http from '@ohos.net.http';
import { HttpClient, RequestOptions, ApiError } from '../../../api/client/HttpClient';
import { SseClient } from '../../../api/client/SseClient';
import { AiApi, QuotaStatus } from '../../../api/ai/AiApi';
import { SensorsAnalytics } from '../../../core/analytics/SensorsAnalytics';

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export type LlmRole = 'system' | 'user' | 'assistant';

export interface LlmMessage {
  role: LlmRole;
  content: string;
}

export type LlmProvider = 'server-proxy' | 'direct-deepseek' | 'direct-qwen';

export interface LlmCallOptions {
  provider?: LlmProvider;
  model?: string;
  temperature?: number;
  maxTokens?: number;
  timeoutMs?: number;
  retries?: number;
  bookId?: string;
  chapterIndex?: number;
}

export interface LlmStreamSink {
  onChunk: (delta: string) => void;
  onDone?: (full: string) => void;
  onError?: (err: LlmError) => void;
}

/** Normalized error emitted by LlmAdapter on every failure path. */
export interface LlmError {
  code: string;
  message: string;
  /** Whether caller may safely retry after a short delay. */
  retryable: boolean;
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

interface ServerChatResponse {
  text: string;
  promptTokens?: number;
  completionTokens?: number;
}

interface ServerEmbeddingResponse {
  embedding: number[];
  dim: number;
}

interface DirectProviderConfig {
  baseUrl: string;
  apiKey: string;
  defaultModel: string;
}

interface LlmAdapterConfig {
  provider?: LlmProvider;
  apiKey?: string;
  model?: string;
  baseUrl?: string;
}

// ---------------------------------------------------------------------------
// Defaults
// ---------------------------------------------------------------------------

const DEFAULT_TEMPERATURE = 0.7;
const DEFAULT_MAX_TOKENS = 1024;
const DEFAULT_TIMEOUT_MS = 60_000;
const DEFAULT_RETRIES = 1;

// ---------------------------------------------------------------------------
// LlmAdapter
// ---------------------------------------------------------------------------

export class LlmAdapter {
  private static defaultProvider: LlmProvider = 'server-proxy';
  private static directConfigs: Map<LlmProvider, DirectProviderConfig> = new Map();

  // ─── Singleton configure ────────────────────────────────────────────────

  /** One-call bootstrap; safe to call multiple times (merges config). */
  static configure(cfg: LlmAdapterConfig): void {
    if (cfg.provider) LlmAdapter.defaultProvider = cfg.provider;
    if (cfg.provider && cfg.provider !== 'server-proxy' && cfg.apiKey && cfg.baseUrl) {
      LlmAdapter.directConfigs.set(cfg.provider, {
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        defaultModel: cfg.model ?? 'default',
      });
    }
  }

  static setDefaultProvider(p: LlmProvider): void {
    LlmAdapter.defaultProvider = p;
  }

  static configureDirectProvider(p: LlmProvider, cfg: DirectProviderConfig): void {
    if (p === 'server-proxy') return;
    LlmAdapter.directConfigs.set(p, cfg);
  }

  // ─── Primary streaming API (AsyncIterableIterator) ──────────────────────

  /**
   * Primary streaming interface. Returns an async iterator of text deltas
   * and an abort() function. Caller:
   *   const { iterator, abort } = LlmAdapter.stream(prompt);
   *   for await (const chunk of iterator) { ... }
   */
  static stream(
    prompt: string,
    opts: LlmCallOptions = {},
  ): { iterator: AsyncIterableIterator<string>; abort: () => void } {
    const messages: LlmMessage[] = [{ role: 'user', content: prompt }];

    let abortFn: () => void = () => {};
    let resolveNext: ((value: IteratorResult<string>) => void) | null = null;
    const pending: string[] = [];
    let done = false;
    let error: LlmError | null = null;

    const push = (chunk: string): void => {
      if (resolveNext) {
        const res = resolveNext;
        resolveNext = null;
        res({ value: chunk, done: false });
      } else {
        pending.push(chunk);
      }
    };

    const finish = (err?: LlmError): void => {
      done = true;
      error = err ?? null;
      if (resolveNext) {
        const res = resolveNext;
        resolveNext = null;
        if (err) {
          res({ value: undefined as unknown as string, done: true });
        } else {
          res({ value: undefined as unknown as string, done: true });
        }
      }
    };

    const sink: LlmStreamSink = {
      onChunk: (delta: string) => push(delta),
      onDone: (_full: string) => finish(),
      onError: (e: LlmError) => finish(e),
    };

    abortFn = LlmAdapter.chatStream(messages, opts, sink);

    const iterator: AsyncIterableIterator<string> = {
      next(): Promise<IteratorResult<string>> {
        if (pending.length > 0) {
          return Promise.resolve({ value: pending.shift()!, done: false });
        }
        if (done) {
          if (error) return Promise.reject(new Error(error.message));
          return Promise.resolve({ value: undefined as unknown as string, done: true });
        }
        return new Promise<IteratorResult<string>>((resolve) => {
          resolveNext = resolve;
        });
      },
      return(): Promise<IteratorResult<string>> {
        abortFn();
        finish();
        return Promise.resolve({ value: undefined as unknown as string, done: true });
      },
      [Symbol.asyncIterator](): AsyncIterableIterator<string> {
        return this;
      },
    };

    return { iterator, abort: abortFn };
  }

  /** Non-streaming convenience — single prompt → full response string. */
  static complete(prompt: string, opts: LlmCallOptions = {}): Promise<string> {
    return LlmAdapter.chat([{ role: 'user', content: prompt }], opts);
  }

  // ─── chat / chatStream ──────────────────────────────────────────────────

  static async chat(messages: LlmMessage[], opts: LlmCallOptions = {}): Promise<string> {
    const provider = opts.provider ?? LlmAdapter.defaultProvider;
    if (provider === 'server-proxy' || !LlmAdapter.directConfigs.has(provider)) {
      return LlmAdapter.chatViaProxy(messages, opts);
    }
    return LlmAdapter.chatDirect(provider, messages, opts);
  }

  static chatStream(messages: LlmMessage[], opts: LlmCallOptions, sink: LlmStreamSink): () => void {
    const provider = opts.provider ?? LlmAdapter.defaultProvider;
    if (provider !== 'server-proxy') {
      let aborted = false;
      LlmAdapter.chat(messages, opts).then((full) => {
        if (aborted) return;
        sink.onChunk(full);
        sink.onDone?.(full);
      }).catch((err: Error) => {
        if (!aborted) sink.onError?.(LlmAdapter.normalizeError(err));
      });
      return () => { aborted = true; };
    }
    return LlmAdapter.chatStreamViaProxy(messages, opts, sink);
  }

  // ─── Embeddings ─────────────────────────────────────────────────────────

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

  static getQuota(): Promise<QuotaStatus> {
    return AiApi.getQuotaStatus();
  }

  // ─── Token estimation ───────────────────────────────────────────────────

  static estimateTokens(text: string): number {
    if (!text) return 0;
    let cjk = 0;
    let other = 0;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      if ((code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF)) {
        cjk += 1;
      } else {
        other += 1;
      }
    }
    return Math.ceil(cjk * 1.2 + other / 4);
  }

  static estimateMessagesTokens(messages: LlmMessage[]): number {
    let sum = 0;
    for (const m of messages) {
      sum += LlmAdapter.estimateTokens(m.content) + 4;
    }
    return sum;
  }

  // ─── Error normalization ─────────────────────────────────────────────────

  static normalizeError(err: unknown): LlmError {
    if (err instanceof ApiError) {
      const retryable = err.statusCode === 0 || err.statusCode >= 500;
      return { code: `api_${err.statusCode}`, message: err.message, retryable };
    }
    if (err instanceof Error) {
      const retryable = err.message.includes('timeout') || err.message.includes('network');
      return { code: 'network_error', message: err.message, retryable };
    }
    return { code: 'unknown', message: String(err), retryable: false };
  }

  // ─── server-proxy impl ──────────────────────────────────────────────────

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
    try {
      const resp = await HttpClient.post<ServerChatResponse>('/api/v1/ai/chat', body, reqOpts);
      LlmAdapter.trackTokenUsage(
        opts.provider ?? 'server-proxy',
        opts.model ?? 'default',
        resp.promptTokens,
        resp.completionTokens,
      );
      return resp.text;
    } catch (err) {
      throw LlmAdapter.normalizeError(err);
    }
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
          const parsed = JSON.parse(raw) as {
            delta?: string;
            done?: boolean;
            error?: string;
            promptTokens?: number;
            completionTokens?: number;
          };
          if (parsed.error) {
            sink.onError?.({ code: 'server_error', message: parsed.error, retryable: false });
            return;
          }
          if (parsed.delta) {
            full += parsed.delta;
            sink.onChunk(parsed.delta);
          }
          if (parsed.done) {
            LlmAdapter.trackTokenUsage(
              opts.provider ?? 'server-proxy',
              opts.model ?? 'default',
              parsed.promptTokens,
              parsed.completionTokens,
            );
            sink.onDone?.(full);
          }
        } catch (_e) {
          full += raw;
          sink.onChunk(raw);
        }
      },
      onDone: () => sink.onDone?.(full),
      onError: (err: Error) => sink.onError?.(LlmAdapter.normalizeError(err)),
    });
  }

  // ─── direct-* impl (POC, OpenAI-compatible) ──────────────────────────────

  private static async chatDirect(
    provider: LlmProvider,
    messages: LlmMessage[],
    opts: LlmCallOptions,
  ): Promise<string> {
    const cfg = LlmAdapter.directConfigs.get(provider);
    if (!cfg) {
      throw { code: 'misconfigured', message: `direct provider ${provider} not configured`, retryable: false } as LlmError;
    }
    const httpReq = http.createHttp();
    try {
      const url = `${cfg.baseUrl.replace(/\/$/, '')}/chat/completions`;
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${cfg.apiKey}`,
      };
      const bodyObj = {
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
        extraData: JSON.stringify(bodyObj),
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
      });
      const text = typeof resp.result === 'string'
        ? resp.result
        : new TextDecoder('utf-8').decode(resp.result as ArrayBuffer);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw LlmAdapter.normalizeError(new ApiError(resp.responseCode, `direct_http_${resp.responseCode}`, resp.responseCode, { body: text }));
      }
      const parsed = JSON.parse(text) as {
        choices?: { message?: { content?: string } }[];
        usage?: { prompt_tokens?: number; completion_tokens?: number };
      };
      const content = parsed.choices?.[0]?.message?.content ?? '';
      LlmAdapter.trackTokenUsage(
        provider,
        opts.model ?? cfg.defaultModel,
        parsed.usage?.prompt_tokens,
        parsed.usage?.completion_tokens,
      );
      return content;
    } catch (err) {
      if ((err as LlmError).code) throw err;
      throw LlmAdapter.normalizeError(err);
    } finally {
      httpReq.destroy();
    }
  }

  // ─── Token usage tracking ─────────────────────────────────────────────

  private static trackTokenUsage(
    provider: string,
    model: string,
    inputTokens?: number,
    outputTokens?: number,
  ): void {
    if (!inputTokens && !outputTokens) return;
    const costUsd = LlmAdapter.estimateCostUsd(provider, model, inputTokens ?? 0, outputTokens ?? 0);
    SensorsAnalytics.getInstance().track('llm.tokens.used', {
      provider,
      model,
      input_tokens: inputTokens ?? 0,
      output_tokens: outputTokens ?? 0,
      cost_estimate_usd: costUsd,
    });
  }

  private static estimateCostUsd(
    _provider: string,
    _model: string,
    inputTokens: number,
    outputTokens: number,
  ): number {
    // Rough estimate: $0.001 / 1K tokens (server-proxy — billed server-side; this is local telemetry only)
    return Math.round(((inputTokens + outputTokens) / 1000) * 0.001 * 1e6) / 1e6;
  }
}

export { QuotaStatus };
