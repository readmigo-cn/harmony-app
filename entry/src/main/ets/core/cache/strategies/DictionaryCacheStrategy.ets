/**
 * DictionaryCacheStrategy.ets — W10-C4
 *
 * 字典查询结果（高频词查询）：
 *  - 7 天 TTL（高频词随时间漂移）
 *  - 普通 LRU，无 pinned
 *  - key 形式：dict:{lang}:{word}
 */

import { CacheManager } from '../CacheManager';

const CATEGORY = 'dict' as const;
const TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

export class DictionaryCacheStrategy {
  static buildKey(lang: string, word: string): string {
    return `dict:${lang}:${word.toLowerCase()}`;
  }

  static async get<T>(lang: string, word: string): Promise<T | null> {
    const raw = await CacheManager.get(DictionaryCacheStrategy.buildKey(lang, word));
    if (!raw) return null;
    try {
      return JSON.parse(raw) as T;
    } catch (_e) {
      return null;
    }
  }

  static async put<T>(lang: string, word: string, payload: T): Promise<void> {
    await CacheManager.put(
      DictionaryCacheStrategy.buildKey(lang, word),
      JSON.stringify(payload),
      { category: CATEGORY, ttlMs: TTL_MS },
    );
  }

  static clearAll(): void {
    CacheManager.clear(CATEGORY);
  }
}
