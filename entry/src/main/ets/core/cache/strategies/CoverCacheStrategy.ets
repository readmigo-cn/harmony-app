/**
 * CoverCacheStrategy.ets — W10-C4
 *
 * 书籍封面：永久缓存（pinned），用于 widget / push 通知 / library 离线时显示。
 *  - key: cover:{bookId}
 *  - 用户主动“清除封面缓存”时统一 clearAll
 */

import { CacheManager } from '../CacheManager';

const CATEGORY = 'covers' as const;

export class CoverCacheStrategy {
  static buildKey(bookId: string): string {
    return `cover:${bookId}`;
  }

  /** 返回本地路径，可直接喂给 Image() 组件。 */
  static async getFileUrl(bookId: string): Promise<string | null> {
    return CacheManager.getFileUrl(CoverCacheStrategy.buildKey(bookId));
  }

  /** 拉取 + 保存为永久（pinned）。 */
  static async download(bookId: string, url: string): Promise<string> {
    return CacheManager.download(url, CoverCacheStrategy.buildKey(bookId), {
      category: CATEGORY,
      pinned: true,
    });
  }

  /** Library 加书时后台 prefetch；失败静默。 */
  static async prefetch(bookId: string, url: string): Promise<void> {
    return CacheManager.prefetch(url, CoverCacheStrategy.buildKey(bookId), {
      category: CATEGORY,
      pinned: true,
    });
  }

  static evict(bookId: string): void {
    CacheManager.evict(CoverCacheStrategy.buildKey(bookId));
  }

  static clearAll(): void {
    CacheManager.clear(CATEGORY);
  }
}
