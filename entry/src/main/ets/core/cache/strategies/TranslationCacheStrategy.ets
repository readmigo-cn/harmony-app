/**
 * TranslationCacheStrategy.ets — W10-C4
 *
 * 句子级翻译缓存：
 *  - 30 天 TTL
 *  - 与 TranslateService 内置 50 条 LRU 互补：
 *      内置 LRU 解决“当前阅读会话内重复”
 *      此处解决“跨次启动 / 跨章节重复段落”
 *  - key 形式：trans:{provider}:{from}->{to}:{sha-ish text}
 */

import { CacheManager } from '../CacheManager';

const CATEGORY = 'translations' as const;
const TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

interface TranslationPayload {
  translated: string;
  sourceLang: string;
  targetLang: string;
  provider: string;
}

export class TranslationCacheStrategy {
  static buildKey(provider: string, from: string, to: string, text: string): string {
    // 直接拼，长 key 由 CacheManager.makeFilename 做 base64
    const trimmed = (text ?? '').trim();
    return `trans:${provider}:${from}->${to}:${trimmed}`;
  }

  static async get(
    provider: string,
    from: string,
    to: string,
    text: string,
  ): Promise<TranslationPayload | null> {
    const raw = await CacheManager.get(
      TranslationCacheStrategy.buildKey(provider, from, to, text),
    );
    if (!raw) return null;
    try {
      return JSON.parse(raw) as TranslationPayload;
    } catch (_e) {
      return null;
    }
  }

  static async put(
    provider: string,
    from: string,
    to: string,
    text: string,
    translated: string,
  ): Promise<void> {
    const payload: TranslationPayload = {
      translated,
      sourceLang: from,
      targetLang: to,
      provider,
    };
    await CacheManager.put(
      TranslationCacheStrategy.buildKey(provider, from, to, text),
      JSON.stringify(payload),
      { category: CATEGORY, ttlMs: TTL_MS },
    );
  }

  static clearAll(): void {
    CacheManager.clear(CATEGORY);
  }
}
