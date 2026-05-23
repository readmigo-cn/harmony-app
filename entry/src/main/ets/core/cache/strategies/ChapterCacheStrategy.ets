/**
 * ChapterCacheStrategy.ets — W10-C4
 *
 * 章节 HTML/CSS 的缓存策略。
 *  - 已读章节（finished）pin 住，永远不淘汰，直到用户主动“清除阅读缓存”
 *  - 未读章节走默认 LRU
 *  - key 形式：chapter:{slug}:{index}
 */

import { CacheManager } from '../CacheManager';
import type { ChapterContent } from '../../../model/Chapter';

const CATEGORY = 'chapters' as const;

interface SerializedChapter {
  html: string;
  css: string;
  title?: string;
}

export class ChapterCacheStrategy {
  static buildKey(slug: string, index: number): string {
    return `chapter:${slug}:${index}`;
  }

  /** 命中返回内容；miss / parse 失败 → null。 */
  static async get(slug: string, index: number): Promise<ChapterContent | null> {
    const raw = await CacheManager.get(ChapterCacheStrategy.buildKey(slug, index));
    if (!raw) return null;
    try {
      const parsed = JSON.parse(raw) as SerializedChapter;
      return {
        html: parsed.html ?? '',
        css: parsed.css ?? '',
        title: parsed.title,
      } as ChapterContent;
    } catch (_e) {
      return null;
    }
  }

  /**
   * 写入章节。已读 chapter（pinned=true）跳过 LRU 淘汰。
   */
  static async put(
    slug: string,
    index: number,
    content: ChapterContent,
    finished: boolean = false,
  ): Promise<void> {
    const payload: SerializedChapter = {
      html: content.html ?? '',
      css: content.css ?? '',
      title: content.title,
    };
    await CacheManager.put(ChapterCacheStrategy.buildKey(slug, index), JSON.stringify(payload), {
      category: CATEGORY,
      pinned: finished,
    });
  }

  /** 切书或主动清理时调用。 */
  static clearAll(): void {
    CacheManager.clear(CATEGORY);
  }
}
