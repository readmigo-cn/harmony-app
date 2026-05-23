/**
 * TranslateService.ets — W8-C4 翻译服务抽象
 *
 * 定位：选段翻译 / 句子翻译 / 句子流式翻译，统一对外接口；底层 provider 可切换。
 *
 * Provider：
 *   - 'server'  默认。调后端 /api/v1/ai/translate/sentence (+ /stream)
 *               走统一 HttpClient / SseClient + 服务端配额。
 *   - 'baidu'   Phase 4 接入 百度翻译 直连（appid + secretKey + 签名）
 *   - 'youdao'  Phase 4 接入 有道翻译 直连
 * 当前所有非 server provider 都抛 NOT_IMPLEMENTED 并 fall back 到 server。
 *
 * 内置 LRU(50) 缓存，避免重复段落（设置／导航返回）触发重复翻译；
 * 缓存 key = `${provider}:${from}->${to}:${text}`。
 */

import { HttpClient } from '../../../api/client/HttpClient';
import { SseClient } from '../../../api/client/SseClient';
import { TranslationCacheStrategy } from '../../../core/cache/strategies/TranslationCacheStrategy';

// ---------- 公共类型 ----------

export type TranslateProvider = 'server' | 'baidu' | 'youdao';

export interface TranslateOptions {
  /** 上下文（句子前 / 后），server provider 用作 prompt 提示 */
  context?: string;
  /** 是否人类风格译文（更自然，server 才支持） */
  natural?: boolean;
}

export interface TranslateResult {
  translated: string;
  sourceLang: string;
  targetLang: string;
  provider: TranslateProvider;
  /** 来自 LRU 缓存命中标记 */
  fromCache?: boolean;
}

export interface TranslateStreamHandlers {
  onChunk: (delta: string) => void;
  onDone?: (full: string) => void;
  onError?: (err: Error) => void;
}

export interface TranslateQuota {
  used: number;
  limit: number;
  remaining: number;
}

// ---------- 后端响应类型 ----------

interface ServerTranslateResp {
  translated: string;
}

interface ServerQuotaResp {
  used: number;
  limit: number;
}

// ---------- LRU 缓存（50 条） ----------

class LruCache {
  private capacity: number;
  private map: Map<string, TranslateResult>;

  constructor(capacity: number) {
    this.capacity = capacity;
    this.map = new Map<string, TranslateResult>();
  }

  get(key: string): TranslateResult | undefined {
    const v = this.map.get(key);
    if (v === undefined) return undefined;
    // 触发一次 reinsert 以维持 LRU 顺序
    this.map.delete(key);
    this.map.set(key, v);
    return v;
  }

  set(key: string, value: TranslateResult): void {
    if (this.map.has(key)) {
      this.map.delete(key);
    } else if (this.map.size >= this.capacity) {
      // 删最旧
      const oldestKey: string | undefined = this.map.keys().next().value;
      if (oldestKey !== undefined) this.map.delete(oldestKey);
    }
    this.map.set(key, value);
  }

  clear(): void {
    this.map.clear();
  }
}

// ---------- 主服务 ----------

export class TranslateService {
  private static instance: TranslateService | null = null;
  private provider: TranslateProvider = 'server';
  private cache: LruCache = new LruCache(50);

  static getInstance(): TranslateService {
    if (!TranslateService.instance) {
      TranslateService.instance = new TranslateService();
    }
    return TranslateService.instance;
  }

  /** 切换 provider；非 server 暂未实装会自动 fallback。 */
  setProvider(provider: TranslateProvider): void {
    this.provider = provider;
  }

  getProvider(): TranslateProvider {
    return this.provider;
  }

  /** 同步翻译。命中缓存直接返回，否则走后端。 */
  async translate(
    text: string,
    sourceLang: string,
    targetLang: string,
    opts?: TranslateOptions,
  ): Promise<TranslateResult> {
    const trimmed = (text ?? '').trim();
    if (!trimmed) {
      return {
        translated: '',
        sourceLang,
        targetLang,
        provider: this.provider,
      };
    }
    const key = this.cacheKey(this.provider, sourceLang, targetLang, trimmed);
    const cached = this.cache.get(key);
    if (cached) {
      return {
        translated: cached.translated,
        sourceLang: cached.sourceLang,
        targetLang: cached.targetLang,
        provider: cached.provider,
        fromCache: true,
      };
    }

    // W10-C4：内存 LRU miss 时再查文件级缓存（30 天 TTL）
    const persistent = await TranslationCacheStrategy.get(
      this.provider, sourceLang, targetLang, trimmed,
    );
    if (persistent) {
      const hit: TranslateResult = {
        translated: persistent.translated,
        sourceLang,
        targetLang,
        provider: this.provider,
        fromCache: true,
      };
      // 同时回写内存 LRU，避免下次又走文件
      this.cache.set(key, hit);
      return hit;
    }

    // 非 server provider 暂未实装 → fallback
    if (this.provider !== 'server') {
      console.warn(`[TranslateService] provider ${this.provider} not implemented, fallback to server`);
    }
    const result = await this.translateViaServer(trimmed, sourceLang, targetLang, opts);
    this.cache.set(key, result);
    // 静默回写文件级缓存
    TranslationCacheStrategy.put(
      this.provider, sourceLang, targetLang, trimmed, result.translated,
    ).catch(() => {});
    return result;
  }

  /**
   * 流式翻译（SSE）。返回 stop() 用于中止；不写入缓存（流式数据需要在 onDone 主动 set）。
   */
  translateStream(
    text: string,
    sourceLang: string,
    targetLang: string,
    handlers: TranslateStreamHandlers,
  ): () => void {
    const trimmed = (text ?? '').trim();
    if (!trimmed) {
      handlers.onDone?.('');
      return () => {};
    }
    // 命中缓存：直接 fire onDone
    const key = this.cacheKey(this.provider, sourceLang, targetLang, trimmed);
    const cached = this.cache.get(key);
    if (cached) {
      handlers.onChunk(cached.translated);
      handlers.onDone?.(cached.translated);
      return () => {};
    }
    if (this.provider !== 'server') {
      console.warn(`[TranslateService] stream provider ${this.provider} not implemented, fallback to server`);
    }
    let buffered = '';
    const stop = SseClient.stream('/ai/translate/sentence/stream', {
      text: trimmed,
      from: sourceLang,
      to: targetLang,
      context: opts_context(handlers),
    } as object, {
      onMessage: (raw: string) => {
        try {
          const parsed = JSON.parse(raw) as { delta?: string; done?: boolean; error?: string };
          if (parsed.error) {
            handlers.onError?.(new Error(parsed.error));
            return;
          }
          if (parsed.delta) {
            buffered += parsed.delta;
            handlers.onChunk(parsed.delta);
          }
          if (parsed.done) {
            this.cache.set(key, {
              translated: buffered,
              sourceLang,
              targetLang,
              provider: 'server',
            });
            // W10-C4：流式完成同时写入持久层
            TranslationCacheStrategy.put(
              'server', sourceLang, targetLang, trimmed, buffered,
            ).catch(() => {});
            handlers.onDone?.(buffered);
          }
        } catch (_e) {
          // 非 JSON 当 raw 透传
          buffered += raw;
          handlers.onChunk(raw);
        }
      },
      onDone: () => {
        if (buffered.length > 0) {
          this.cache.set(key, {
            translated: buffered,
            sourceLang,
            targetLang,
            provider: 'server',
          });
          TranslationCacheStrategy.put(
            'server', sourceLang, targetLang, trimmed, buffered,
          ).catch(() => {});
        }
        handlers.onDone?.(buffered);
      },
      onError: (err) => handlers.onError?.(err),
    });
    return stop;
  }

  /** 查询服务端 AI 翻译配额（kind=translate）。 */
  async getQuota(): Promise<TranslateQuota> {
    try {
      const resp = await HttpClient.get<ServerQuotaResp>('/ai/quota', { kind: 'translate' });
      const used = resp?.used ?? 0;
      const limit = resp?.limit ?? 0;
      return { used, limit, remaining: Math.max(0, limit - used) };
    } catch (_e) {
      return { used: 0, limit: 0, remaining: 0 };
    }
  }

  /** 清空 LRU（设置改语言对、provider 切换、登出时调用）。 */
  clearCache(): void {
    this.cache.clear();
  }

  // ---------- 内部 ----------

  private async translateViaServer(
    text: string,
    sourceLang: string,
    targetLang: string,
    _opts?: TranslateOptions,
  ): Promise<TranslateResult> {
    const body: Record<string, string> = {
      text,
      from: sourceLang,
      to: targetLang,
    };
    // W11 Critical 修复：默认 30s 超时（HttpClient 自身可能不带；用 Promise.race 保底）
    // 防止后端卡住时客户端无限等待
    const TIMEOUT_MS = 30000;
    const resp = await Promise.race<ServerTranslateResp>([
      HttpClient.post<ServerTranslateResp>('/ai/translate/sentence', body),
      new Promise<ServerTranslateResp>((_resolve, reject) => {
        setTimeout(() => reject(new Error('translate_timeout')), TIMEOUT_MS);
      }),
    ]);
    return {
      translated: resp?.translated ?? '',
      sourceLang,
      targetLang,
      provider: 'server',
    };
  }

  private cacheKey(provider: TranslateProvider, from: string, to: string, text: string): string {
    return `${provider}:${from}->${to}:${text}`;
  }
}

// 兼容 stream 调用时透传 context 字段（防止 SseClient body 不接受 undefined 字段）
function opts_context(_h: TranslateStreamHandlers): string {
  return '';
}
