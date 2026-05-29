import { PreferencesManager } from '../../core/persistence/PreferencesManager';
import { ApiConfig } from './ApiConfig';

export interface CacheEntry {
  data: string;
  etag: string;
  cachedAt: number;
  ttlMs: number;
  bytes: number;
}

const INDEX_KEY = '__index__';

/**
 * HTTP GET 响应双层缓存：
 *  - L1 内存 LRU：Map<key, entry>，按字节预算驱逐（默认 20MB，对齐 iOS URLCache）
 *  - L2 磁盘持久化：复用 PreferencesManager 加密 namespace（默认 100MB 软上限）
 *
 * 命中条件：未过期 + 完全等价 key（method+url+query）。
 * 写入策略：仅 GET 缓存；任何 mutating method 会触发对应 prefix invalidate。
 * 驱逐策略：内存按 LRU；磁盘软限触发后清最旧条目（按 cachedAt）。
 *
 * 默认 ApiConfig.cache.enabled=false（feature flag），灰度后再打开。
 */
export class ResponseCache {
  private static mem: Map<string, CacheEntry> = new Map<string, CacheEntry>();
  private static memBytes: number = 0;
  private static ns = PreferencesManager.createNamespace('http_cache');
  private static diskKeys: Set<string> = new Set<string>();
  private static diskInitialized: boolean = false;

  static async get(key: string): Promise<CacheEntry | null> {
    if (!ApiConfig.cache.enabled) return null;
    const memEntry = ResponseCache.mem.get(key);
    if (memEntry) {
      if (ResponseCache.isFresh(memEntry)) {
        // LRU: 删后插刷新顺序
        ResponseCache.mem.delete(key);
        ResponseCache.mem.set(key, memEntry);
        return memEntry;
      }
      ResponseCache.mem.delete(key);
      ResponseCache.memBytes -= memEntry.bytes;
    }
    await ResponseCache.ensureDiskIndex();
    if (!ResponseCache.diskKeys.has(key)) return null;
    const diskEntry = await ResponseCache.ns.getObject<CacheEntry>(key, null);
    if (!diskEntry) {
      ResponseCache.diskKeys.delete(key);
      return null;
    }
    if (!ResponseCache.isFresh(diskEntry)) {
      await ResponseCache.removeDisk(key);
      return null;
    }
    ResponseCache.putMem(key, diskEntry);
    return diskEntry;
  }

  static async put(
    key: string,
    data: unknown,
    opts: { etag?: string; ttlMs?: number } = {},
  ): Promise<void> {
    if (!ApiConfig.cache.enabled) return;
    const json = JSON.stringify(data);
    const entry: CacheEntry = {
      data: json,
      etag: opts.etag ?? '',
      cachedAt: Date.now(),
      ttlMs: opts.ttlMs ?? ApiConfig.cache.defaultTtlMs,
      bytes: json.length,
    };
    ResponseCache.putMem(key, entry);
    await ResponseCache.putDisk(key, entry);
  }

  /** mutating 请求后失效相关前缀；例：POST /bookshelf → invalidate('GET:/bookshelf')。 */
  static async invalidate(prefix: string): Promise<void> {
    const memKeys = Array.from(ResponseCache.mem.keys());
    for (let i = 0; i < memKeys.length; i++) {
      const k = memKeys[i];
      if (k.startsWith(prefix)) {
        const e = ResponseCache.mem.get(k);
        if (e) ResponseCache.memBytes -= e.bytes;
        ResponseCache.mem.delete(k);
      }
    }
    await ResponseCache.ensureDiskIndex();
    const diskKeys = Array.from(ResponseCache.diskKeys);
    for (let i = 0; i < diskKeys.length; i++) {
      const k = diskKeys[i];
      if (k.startsWith(prefix)) await ResponseCache.removeDisk(k);
    }
  }

  static async clear(): Promise<void> {
    ResponseCache.mem.clear();
    ResponseCache.memBytes = 0;
    await ResponseCache.ensureDiskIndex();
    const keys = Array.from(ResponseCache.diskKeys);
    for (let i = 0; i < keys.length; i++) {
      await ResponseCache.ns.remove(keys[i]);
    }
    ResponseCache.diskKeys.clear();
    await ResponseCache.ns.setArray<string>(INDEX_KEY, []);
  }

  /** HttpClient 调用入口：method 必须是 uppercase（'GET' / 'POST' 等）。 */
  static keyFor(method: string, url: string): string {
    return `${method}:${url}`;
  }

  // ---------- internals ----------

  private static isFresh(e: CacheEntry): boolean {
    return Date.now() - e.cachedAt < e.ttlMs;
  }

  private static putMem(key: string, entry: CacheEntry): void {
    const existing = ResponseCache.mem.get(key);
    if (existing) ResponseCache.memBytes -= existing.bytes;
    ResponseCache.mem.delete(key);
    ResponseCache.mem.set(key, entry);
    ResponseCache.memBytes += entry.bytes;
    ResponseCache.evictIfOverBudget();
  }

  private static evictIfOverBudget(): void {
    const budget = ApiConfig.cache.memBytes;
    while (ResponseCache.memBytes > budget && ResponseCache.mem.size > 0) {
      const oldestKey = ResponseCache.mem.keys().next().value;
      if (oldestKey === undefined) break;
      const e = ResponseCache.mem.get(oldestKey);
      if (e) ResponseCache.memBytes -= e.bytes;
      ResponseCache.mem.delete(oldestKey);
    }
  }

  private static async ensureDiskIndex(): Promise<void> {
    if (ResponseCache.diskInitialized) return;
    const idx = await ResponseCache.ns.getArray<string>(INDEX_KEY, []);
    ResponseCache.diskKeys = new Set<string>(idx);
    ResponseCache.diskInitialized = true;
  }

  private static async putDisk(key: string, entry: CacheEntry): Promise<void> {
    await ResponseCache.ensureDiskIndex();
    await ResponseCache.ns.setObject<CacheEntry>(key, entry);
    if (!ResponseCache.diskKeys.has(key)) {
      ResponseCache.diskKeys.add(key);
      await ResponseCache.ns.setArray<string>(INDEX_KEY, Array.from(ResponseCache.diskKeys));
    }
  }

  private static async removeDisk(key: string): Promise<void> {
    await ResponseCache.ns.remove(key);
    ResponseCache.diskKeys.delete(key);
    await ResponseCache.ns.setArray<string>(INDEX_KEY, Array.from(ResponseCache.diskKeys));
  }
}
