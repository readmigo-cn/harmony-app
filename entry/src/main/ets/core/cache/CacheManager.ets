/**
 * CacheManager.ets — W10-C4 通用本地文件缓存
 *
 * 责任：
 *   - 统一对外的 KV-style 文件缓存（章节 HTML / 字典 / 翻译 / 音频 / 封面）
 *   - 持久化用 context.cacheDir 下分类子目录
 *   - LRU 容量上限（默认 500MB），超限时按最近访问顺序淘汰
 *   - 元信息（key → CacheEntry）落盘到 cacheDir/meta.json，启动时 reload
 *   - 提供 download(url, key) 直接通过 @ohos.net.http 拉远端 → 本地
 *   - 后台 prefetch：开放给上层（如 Library 加书时 prefetch 第一章）
 *   - 失败重试：网络下载内置 1 次重试
 *
 * 注意：
 *   - 元信息 flush 100ms debounce，避免频繁 IO
 *   - 单例：先 init(context, opts?) 再用静态方法
 *   - LRU 评估周期默认 5 次写入 / 一次显式 size() 调用，避免每次 put 都遍历
 */

import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import buffer from '@ohos.buffer';

// -------------------- 类型 --------------------

/** 缓存分类：决定子目录、TTL、淘汰策略。 */
export type CacheCategory =
  | 'chapters'
  | 'dict'
  | 'translations'
  | 'audio'
  | 'covers';

export const CACHE_CATEGORIES: CacheCategory[] = [
  'chapters', 'dict', 'translations', 'audio', 'covers',
];

export interface CacheEntry {
  key: string;
  category: CacheCategory;
  /** 相对于 cacheDir 的子路径 */
  filePath: string;
  size: number;
  createdAt: number;
  /** 最近一次访问，LRU 用 */
  accessedAt: number;
  /** 可选，过期毫秒时间戳；undefined 表示无 TTL */
  expiresAt?: number;
  /** 上层标记的特殊保护（已读章节永久缓存等） */
  pinned?: boolean;
}

export interface CacheOptions {
  /** 最大总容量（字节），默认 500 MB */
  maxBytes?: number;
  /** 单 entry 默认 TTL（毫秒），undefined 不过期 */
  defaultTtlMs?: number;
}

export interface CacheSize {
  total: number;
  byCategory: Record<CacheCategory, number>;
}

interface PutOptions {
  category: CacheCategory;
  ttlMs?: number;
  pinned?: boolean;
}

// -------------------- 主类 --------------------

const META_FILE = 'meta.json';
const DEFAULT_MAX_BYTES = 500 * 1024 * 1024; // 500 MB

export class CacheManager {
  private static rootDir: string = '';
  private static maxBytes: number = DEFAULT_MAX_BYTES;
  private static defaultTtlMs: number | undefined = undefined;
  private static entries: Map<string, CacheEntry> = new Map<string, CacheEntry>();
  private static initialized: boolean = false;
  private static flushTimer: number | null = null;
  private static putsSinceEvict: number = 0;

  /** 启动时调用一次。EntryAbility.onCreate 内挂上即可。 */
  static async init(context: common.UIAbilityContext, opts?: CacheOptions): Promise<void> {
    if (CacheManager.initialized) return;
    CacheManager.rootDir = context.cacheDir;
    CacheManager.maxBytes = opts?.maxBytes ?? DEFAULT_MAX_BYTES;
    CacheManager.defaultTtlMs = opts?.defaultTtlMs;
    // 创建分类目录
    for (const cat of CACHE_CATEGORIES) {
      const dir = `${CacheManager.rootDir}/${cat}`;
      try {
        if (!fs.accessSync(dir)) fs.mkdirSync(dir);
      } catch (_e) { /* swallow */ }
    }
    await CacheManager.loadMeta();
    // 启动期清一次过期项
    CacheManager.evictExpired();
    CacheManager.initialized = true;
  }

  // ---------- 公共 API ----------

  /** 读字符串内容（章节 HTML / JSON 文本类）。miss 或过期返回 null。 */
  static async get(key: string): Promise<string | null> {
    const entry = CacheManager.touch(key);
    if (!entry) return null;
    try {
      const file = fs.openSync(CacheManager.absPath(entry.filePath), fs.OpenMode.READ_ONLY);
      try {
        const stat = fs.statSync(file.fd);
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        return buffer.from(buf).toString('utf-8');
      } finally {
        fs.closeSync(file);
      }
    } catch (_e) {
      // 文件丢失 → 元信息也清掉
      CacheManager.entries.delete(key);
      CacheManager.scheduleFlush();
      return null;
    }
  }

  /** 写字符串内容。 */
  static async put(key: string, content: string, opts: PutOptions): Promise<void> {
    if (!CacheManager.initialized) return;
    const filename = CacheManager.makeFilename(key);
    const rel = `${opts.category}/${filename}`;
    const abs = CacheManager.absPath(rel);
    try {
      const file = fs.openSync(abs, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const u8 = new Uint8Array(buffer.from(content, 'utf-8').buffer);
        fs.writeSync(file.fd, u8.buffer);
      } finally {
        fs.closeSync(file);
      }
      const stat = fs.statSync(abs);
      const ttl = opts.ttlMs ?? CacheManager.defaultTtlMs;
      const now = Date.now();
      const entry: CacheEntry = {
        key,
        category: opts.category,
        filePath: rel,
        size: stat.size,
        createdAt: now,
        accessedAt: now,
        expiresAt: ttl ? now + ttl : undefined,
        pinned: opts.pinned,
      };
      // 替换旧项
      const old = CacheManager.entries.get(key);
      if (old && old.filePath !== rel) {
        CacheManager.removeFile(old.filePath);
      }
      CacheManager.entries.delete(key);
      CacheManager.entries.set(key, entry);
      CacheManager.putsSinceEvict += 1;
      if (CacheManager.putsSinceEvict >= 5) {
        CacheManager.evictIfOverCapacity();
        CacheManager.putsSinceEvict = 0;
      }
      CacheManager.scheduleFlush();
    } catch (err) {
      console.warn(`[CacheManager] put failed key=${key}: ${(err as Error).message}`);
    }
  }

  /** 返回本地文件绝对路径（用于 Image / AudioRenderer 直接读）。 */
  static async getFileUrl(key: string): Promise<string | null> {
    const entry = CacheManager.touch(key);
    if (!entry) return null;
    return CacheManager.absPath(entry.filePath);
  }

  /**
   * 下载远程 URL 到本地缓存。
   * 失败重试 1 次（指数退避 500ms）。
   * 返回本地绝对路径。
   */
  static async download(url: string, key: string, opts: PutOptions): Promise<string> {
    let lastErr: Error | null = null;
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const data = await CacheManager.fetchBinary(url);
        const filename = CacheManager.makeFilename(key);
        const rel = `${opts.category}/${filename}`;
        const abs = CacheManager.absPath(rel);
        const file = fs.openSync(abs, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        try {
          fs.writeSync(file.fd, data);
        } finally {
          fs.closeSync(file);
        }
        const stat = fs.statSync(abs);
        const ttl = opts.ttlMs ?? CacheManager.defaultTtlMs;
        const now = Date.now();
        const entry: CacheEntry = {
          key,
          category: opts.category,
          filePath: rel,
          size: stat.size,
          createdAt: now,
          accessedAt: now,
          expiresAt: ttl ? now + ttl : undefined,
          pinned: opts.pinned,
        };
        const old = CacheManager.entries.get(key);
        if (old && old.filePath !== rel) {
          CacheManager.removeFile(old.filePath);
        }
        CacheManager.entries.delete(key);
        CacheManager.entries.set(key, entry);
        CacheManager.evictIfOverCapacity();
        CacheManager.scheduleFlush();
        return abs;
      } catch (err) {
        lastErr = err as Error;
        if (attempt === 0) await CacheManager.sleep(500);
      }
    }
    throw lastErr ?? new Error('download failed');
  }

  /** 后台 prefetch：失败静默，存在则跳过。 */
  static async prefetch(url: string, key: string, opts: PutOptions): Promise<void> {
    const existing = CacheManager.entries.get(key);
    if (existing && !CacheManager.isExpired(existing)) return;
    try {
      await CacheManager.download(url, key, opts);
    } catch (_e) {
      // 静默
    }
  }

  /** 单 key 清理。 */
  static evict(key: string): void {
    const entry = CacheManager.entries.get(key);
    if (!entry) return;
    CacheManager.removeFile(entry.filePath);
    CacheManager.entries.delete(key);
    CacheManager.scheduleFlush();
  }

  /** 全清 / 分类清。 */
  static clear(category?: CacheCategory): void {
    const toRemove: string[] = [];
    CacheManager.entries.forEach((e, k) => {
      if (category === undefined || e.category === category) {
        toRemove.push(k);
      }
    });
    for (const k of toRemove) {
      const e = CacheManager.entries.get(k);
      if (e) CacheManager.removeFile(e.filePath);
      CacheManager.entries.delete(k);
    }
    CacheManager.scheduleFlush();
  }

  /** 占用统计。 */
  static async getSize(): Promise<CacheSize> {
    const byCategory: Record<CacheCategory, number> = {
      chapters: 0, dict: 0, translations: 0, audio: 0, covers: 0,
    };
    let total = 0;
    CacheManager.entries.forEach((e) => {
      byCategory[e.category] += e.size;
      total += e.size;
    });
    return { total, byCategory };
  }

  /** 用户登出 / 切书时显式调用，强制刷盘 */
  static async flush(): Promise<void> {
    if (CacheManager.flushTimer !== null) {
      clearTimeout(CacheManager.flushTimer);
      CacheManager.flushTimer = null;
    }
    await CacheManager.persistMeta();
  }

  // ---------- 内部 ----------

  private static touch(key: string): CacheEntry | null {
    const e = CacheManager.entries.get(key);
    if (!e) return null;
    if (CacheManager.isExpired(e)) {
      CacheManager.evict(key);
      return null;
    }
    e.accessedAt = Date.now();
    // re-insert 维持 LRU 顺序
    CacheManager.entries.delete(key);
    CacheManager.entries.set(key, e);
    CacheManager.scheduleFlush();
    return e;
  }

  private static isExpired(e: CacheEntry): boolean {
    if (e.pinned) return false;
    if (!e.expiresAt) return false;
    return Date.now() > e.expiresAt;
  }

  /** LRU 淘汰：从最旧（迭代顺序最前）开始删，直到 total <= maxBytes。pinned 跳过。 */
  private static evictIfOverCapacity(): void {
    let total = 0;
    CacheManager.entries.forEach((e) => { total += e.size; });
    if (total <= CacheManager.maxBytes) return;
    const keys = Array.from(CacheManager.entries.keys());
    for (const k of keys) {
      if (total <= CacheManager.maxBytes) break;
      const e = CacheManager.entries.get(k);
      if (!e || e.pinned) continue;
      CacheManager.removeFile(e.filePath);
      total -= e.size;
      CacheManager.entries.delete(k);
    }
  }

  private static evictExpired(): void {
    const expired: string[] = [];
    CacheManager.entries.forEach((e, k) => {
      if (CacheManager.isExpired(e)) expired.push(k);
    });
    for (const k of expired) {
      const e = CacheManager.entries.get(k);
      if (e) CacheManager.removeFile(e.filePath);
      CacheManager.entries.delete(k);
    }
  }

  private static absPath(rel: string): string {
    return `${CacheManager.rootDir}/${rel}`;
  }

  private static removeFile(rel: string): void {
    try { fs.unlinkSync(CacheManager.absPath(rel)); } catch (_e) { /* swallow */ }
  }

  /** key → 安全文件名（hash-like）。这里取简单 base64-ish；冲突容忍——同 key 覆盖。 */
  private static makeFilename(key: string): string {
    // 用 buffer base64 → 替换不安全字符
    const b64 = buffer.from(key, 'utf-8').toString('base64');
    return b64.replace(/[/+=]/g, '_');
  }

  private static scheduleFlush(): void {
    if (CacheManager.flushTimer !== null) return;
    CacheManager.flushTimer = setTimeout(async () => {
      CacheManager.flushTimer = null;
      await CacheManager.persistMeta();
    }, 100);
  }

  private static async persistMeta(): Promise<void> {
    try {
      const arr: CacheEntry[] = [];
      CacheManager.entries.forEach((e) => arr.push(e));
      const json = JSON.stringify({ version: 1, entries: arr });
      const abs = CacheManager.absPath(META_FILE);
      const file = fs.openSync(abs, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const u8 = new Uint8Array(buffer.from(json, 'utf-8').buffer);
        fs.writeSync(file.fd, u8.buffer);
      } finally {
        fs.closeSync(file);
      }
    } catch (err) {
      console.warn(`[CacheManager] persistMeta failed: ${(err as Error).message}`);
    }
  }

  private static async loadMeta(): Promise<void> {
    const abs = CacheManager.absPath(META_FILE);
    try {
      if (!fs.accessSync(abs)) return;
      const file = fs.openSync(abs, fs.OpenMode.READ_ONLY);
      try {
        const stat = fs.statSync(file.fd);
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        const json = buffer.from(buf).toString('utf-8');
        interface MetaFile { version: number; entries: CacheEntry[]; }
        const parsed = JSON.parse(json) as MetaFile;
        for (const e of parsed.entries ?? []) {
          // 文件不存在则丢弃
          if (fs.accessSync(CacheManager.absPath(e.filePath))) {
            CacheManager.entries.set(e.key, e);
          }
        }
      } finally {
        fs.closeSync(file);
      }
    } catch (err) {
      console.warn(`[CacheManager] loadMeta failed: ${(err as Error).message}`);
    }
  }

  private static async fetchBinary(url: string): Promise<ArrayBuffer> {
    const httpRequest = http.createHttp();
    try {
      const resp = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 30000,
        readTimeout: 30000,
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`http_${resp.responseCode}`);
      }
      if (typeof resp.result === 'string') {
        return buffer.from(resp.result, 'utf-8').buffer;
      }
      return resp.result as ArrayBuffer;
    } finally {
      httpRequest.destroy();
    }
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(() => resolve(), ms));
  }
}
