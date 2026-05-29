/**
 * TranslateService.ets — W4 翻译服务（含 lookupWord / summarize / batch / stream）
 *
 * 层级：L2 (features/ai-tools/service/) — 禁止导入 @ohos.arkui.*
 *
 * Fallback chain:
 *   1. TranslationCacheStrategy (memory LRU + 文件 7d TTL)
 *   2. AiApi.translateSentenceStream (SSE)
 *   3. 预翻译端点 /books/{bookId}/chapters/{chapterId}/translations/{locale}/paragraphs/{idx}
 *   4. throw TranslationUnavailableError
 */

import { AiApi, TranslatePayload } from '../../../api/ai/AiApi';
import { HttpClient } from '../../../api/client/HttpClient';
import { TranslationCacheStrategy } from '../../../core/cache/strategies/TranslationCacheStrategy';

// ---------------------------------------------------------------------------
// 公共类型
// ---------------------------------------------------------------------------

export interface TranslateOpts {
  sourceLang: 'en' | 'zh' | 'auto';
  targetLang: 'en' | 'zh';
  bookId?: string;
  chapterId?: string;
  paragraphIdx?: number;
}

export interface WordExplanation {
  word: string;
  definition: string;
  partOfSpeech: string;
  examples: string[];
  wordFamily: string[];
}

export type TranslationErrorCode = 'NETWORK' | 'QUOTA' | 'UNSUPPORTED_LANG';

export class TranslationUnavailableError extends Error {
  readonly code: TranslationErrorCode;
  constructor(code: TranslationErrorCode, message?: string) {
    super(message ?? code);
    this.code = code;
    this.name = 'TranslationUnavailableError';
  }
}

// ---------------------------------------------------------------------------
// 内部 in-memory LRU (cap 500)
// ---------------------------------------------------------------------------

class LruMap<V> {
  private capacity: number;
  private map: Map<string, V> = new Map();

  constructor(capacity: number) {
    this.capacity = capacity;
  }

  get(key: string): V | undefined {
    const v = this.map.get(key);
    if (v === undefined) return undefined;
    this.map.delete(key);
    this.map.set(key, v);
    return v;
  }

  set(key: string, value: V): void {
    if (this.map.has(key)) this.map.delete(key);
    else if (this.map.size >= this.capacity) {
      const oldest = this.map.keys().next().value as string | undefined;
      if (oldest !== undefined) this.map.delete(oldest);
    }
    this.map.set(key, value);
  }

  delete(key: string): void {
    this.map.delete(key);
  }

  clear(): void {
    this.map.clear();
  }
}

// ---------------------------------------------------------------------------
// TranslateService
// ---------------------------------------------------------------------------

const CACHE_TTL_7D = 7 * 24 * 60 * 60 * 1000;
const BATCH_CONCURRENCY = 3;

export class TranslateService {
  private static _instance: TranslateService | null = null;

  private memCache: LruMap<string> = new LruMap(500);

  static get shared(): TranslateService {
    if (!TranslateService._instance) {
      TranslateService._instance = new TranslateService();
    }
    return TranslateService._instance;
  }

  // ---------------------------------------------------------------------------
  // translateSentence
  // ---------------------------------------------------------------------------

  async translateSentence(sentence: string, opts: TranslateOpts): Promise<string> {
    const trimmed = sentence.trim();
    if (!trimmed) return '';

    const cacheKey = this.buildKey(trimmed, opts.sourceLang, opts.targetLang);

    // 1. Memory LRU
    const memHit = this.memCache.get(cacheKey);
    if (memHit !== undefined) return memHit;

    // 2. Persistent cache
    const persHit = await TranslationCacheStrategy.get('server', opts.sourceLang, opts.targetLang, trimmed);
    if (persHit) {
      this.memCache.set(cacheKey, persHit.translated);
      return persHit.translated;
    }

    // 3. LlmAdapter via AiApi stream — collect to string
    try {
      const result = await this.collectStream(trimmed, opts);
      this.memCache.set(cacheKey, result);
      TranslationCacheStrategy.put('server', opts.sourceLang, opts.targetLang, trimmed, result).catch(() => {});
      return result;
    } catch (e1) {
      // 4. Pre-translation endpoint fallback
      if (opts.bookId && opts.chapterId && opts.paragraphIdx !== undefined) {
        try {
          const locale = opts.targetLang === 'zh' ? 'zh-CN' : 'en';
          const resp = await HttpClient.get<{ text: string }>(
            `/books/${opts.bookId}/chapters/${opts.chapterId}/translations/${locale}/paragraphs/${opts.paragraphIdx}`,
          );
          if (resp?.text) return resp.text;
        } catch (_e2) {}
      }
      // 5. Classify and throw
      throw this.classify(e1 as Error);
    }
  }

  // ---------------------------------------------------------------------------
  // translateSentenceStream
  // ---------------------------------------------------------------------------

  async *translateSentenceStream(sentence: string, opts: TranslateOpts): AsyncGenerator<string> {
    const trimmed = sentence.trim();
    if (!trimmed) return;

    const cacheKey = this.buildKey(trimmed, opts.sourceLang, opts.targetLang);

    // Memory hit → yield entire string once
    const memHit = this.memCache.get(cacheKey);
    if (memHit !== undefined) {
      yield memHit;
      return;
    }

    // Persistent hit → yield once
    const persHit = await TranslationCacheStrategy.get('server', opts.sourceLang, opts.targetLang, trimmed);
    if (persHit) {
      this.memCache.set(cacheKey, persHit.translated);
      yield persHit.translated;
      return;
    }

    // SSE stream via AiApi
    let full = '';
    const chunks: string[] = [];
    let done = false;
    let error: Error | null = null;

    const payload: TranslatePayload = {
      text: trimmed,
      from: opts.sourceLang === 'auto' ? 'en' : opts.sourceLang,
      to: opts.targetLang,
      bookId: opts.bookId,
    };

    const stop = AiApi.translateSentenceStream(payload, {
      onChunk: (delta: string) => {
        chunks.push(delta);
        full += delta;
      },
      onDone: () => { done = true; },
      onError: (e: Error) => { error = e; done = true; },
    });

    // Drain chunks as they arrive using a polling async loop
    let idx = 0;
    const POLL_INTERVAL = 16;
    while (!done || idx < chunks.length) {
      while (idx < chunks.length) {
        yield chunks[idx];
        idx++;
      }
      if (!done) {
        await new Promise<void>((r) => setTimeout(() => r(), POLL_INTERVAL));
      }
    }

    if (error) {
      stop();
      throw this.classify(error);
    }

    // Cache final
    if (full) {
      this.memCache.set(cacheKey, full);
      TranslationCacheStrategy.put('server', opts.sourceLang, opts.targetLang, trimmed, full).catch(() => {});
    }
  }

  // ---------------------------------------------------------------------------
  // translateBatch
  // ---------------------------------------------------------------------------

  async translateBatch(sentences: string[], opts: TranslateOpts): Promise<string[]> {
    const results: string[] = new Array(sentences.length).fill('');
    let cursor = 0;

    const worker = async (): Promise<void> => {
      while (cursor < sentences.length) {
        const idx = cursor++;
        try {
          results[idx] = await this.translateSentence(sentences[idx], opts);
        } catch (_e) {
          results[idx] = '';
        }
      }
    };

    const workers: Promise<void>[] = [];
    for (let i = 0; i < Math.min(BATCH_CONCURRENCY, sentences.length); i++) {
      workers.push(worker());
    }
    await Promise.all(workers);
    return results;
  }

  // ---------------------------------------------------------------------------
  // lookupWord — calls /ai/explain/word for structured JSON
  // ---------------------------------------------------------------------------

  async lookupWord(word: string, contextSentence: string, targetLang: 'en' | 'zh'): Promise<WordExplanation> {
    const trimmed = word.trim();
    if (!trimmed) {
      return { word: '', definition: '', partOfSpeech: '', examples: [], wordFamily: [] };
    }

    try {
      const resp = await HttpClient.post<{
        word?: string;
        definition?: string;
        partOfSpeech?: string;
        examples?: string[];
        wordFamily?: string[];
        raw?: string;
      }>('/ai/explain', {
        word: trimmed,
        context: contextSentence,
        locale: targetLang === 'zh' ? 'zh-CN' : 'en',
      });

      return {
        word: resp.word ?? trimmed,
        definition: resp.definition ?? resp.raw ?? '',
        partOfSpeech: resp.partOfSpeech ?? '',
        examples: resp.examples ?? [],
        wordFamily: resp.wordFamily ?? [],
      };
    } catch (e) {
      throw this.classify(e as Error);
    }
  }

  // ---------------------------------------------------------------------------
  // summarize — chapter-level summary
  // ---------------------------------------------------------------------------

  async summarize(chapterText: string, targetLang: 'en' | 'zh'): Promise<string> {
    const trimmed = chapterText.trim();
    if (!trimmed) return '';

    const cacheKey = this.buildKey(`summary:${trimmed.slice(0, 120)}`, 'auto', targetLang);
    const memHit = this.memCache.get(cacheKey);
    if (memHit !== undefined) return memHit;

    try {
      const payload: TranslatePayload = {
        text: trimmed,
        from: 'auto',
        to: targetLang,
        bookId: undefined,
      };
      // Reuse translate endpoint with a summarize marker; server handles by intent
      const resp = await HttpClient.post<{ translated: string }>('/ai/summarize', {
        text: trimmed,
        locale: targetLang === 'zh' ? 'zh-CN' : 'en',
      });
      const result = resp.translated ?? '';
      if (result) this.memCache.set(cacheKey, result);
      return result;
    } catch (e) {
      // Fallback: use translate stream on truncated text
      const short = trimmed.slice(0, 2000);
      try {
        return await this.translateSentence(short, { sourceLang: 'auto', targetLang });
      } catch (_e2) {
        throw this.classify(e as Error);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Cache management
  // ---------------------------------------------------------------------------

  clearMemoryCache(): void {
    this.memCache.clear();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  private async collectStream(text: string, opts: TranslateOpts): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      let buf = '';
      let settled = false;
      const payload: TranslatePayload = {
        text,
        from: opts.sourceLang === 'auto' ? 'en' : opts.sourceLang,
        to: opts.targetLang,
        bookId: opts.bookId,
      };
      const stop = AiApi.translateSentenceStream(payload, {
        onChunk: (delta: string) => { buf += delta; },
        onDone: () => {
          if (settled) return;
          settled = true;
          resolve(buf);
        },
        onError: (e: Error) => {
          if (settled) return;
          settled = true;
          try { stop(); } catch (_e) {}
          reject(e);
        },
      });
      // Safety timeout 30s
      setTimeout(() => {
        if (settled) return;
        settled = true;
        try { stop(); } catch (_e) {}
        if (buf.length > 0) resolve(buf);
        else reject(new Error('translate_timeout'));
      }, 30000);
    });
  }

  private buildKey(text: string, from: string, to: string): string {
    return `${from}>${to}:${text}`;
  }

  private classify(e: Error): TranslationUnavailableError {
    const msg = e.message ?? '';
    if (msg.includes('quota') || msg.includes('429')) {
      return new TranslationUnavailableError('QUOTA', msg);
    }
    if (msg.includes('unsupported') || msg.includes('lang')) {
      return new TranslationUnavailableError('UNSUPPORTED_LANG', msg);
    }
    return new TranslationUnavailableError('NETWORK', msg);
  }
}
