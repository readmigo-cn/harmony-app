/**
 * ObsClient.ets — W10-C6 华为云 OBS 客户端封装（Mock 版）
 *
 * Phase 4 接 @hms.cloud.obs SDK；当前为 Mock：
 *   - 上传：写到 context.cacheDir/_obs_mock/<bucket>/<key>
 *   - 下载：从 mock 路径 readSync
 *   - 预签名 URL：生成 obsmock://<bucket>/<key>?expiresAt=<ts> 形式的字符串
 *   - head/list/delete：操作元信息 JSON 文件
 *
 * 配置来源：
 *   先读 AppStorage / ApiConfig，缺失则用占位（dev/test 环境）。
 *   生产构建 (Phase 4) 替换 SDK 部分时不影响调用方接口。
 *
 * 设计要点：
 *   - 单例 + 显式 init(context, cfg?)
 *   - 所有方法都返回 Promise，便于将来切真实 SDK
 *   - 同步 IO 用 fs.*Sync 包装在 Promise 内（与 CacheManager 一致）
 */

import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import buffer from '@ohos.buffer';

// -------------------- 类型 --------------------

export interface ObsConfig {
  endpoint: string;
  bucket: string;
  accessKey: string;
  secretKey: string;
  region?: string;
}

export interface UploadOptions {
  contentType?: string;
  /** 自定义 metadata 透传 */
  metadata?: Record<string, string>;
}

export interface UploadResult {
  key: string;
  etag: string;
  size: number;
  versionId?: string;
}

export interface ObjectMeta {
  key: string;
  size: number;
  etag: string;
  contentType?: string;
  lastModified: number; // ms
  metadata?: Record<string, string>;
}

const DEFAULT_CFG: ObsConfig = {
  endpoint: 'https://obs.cn-north-4.myhuaweicloud.com',
  bucket: 'readmigo-cn-mock',
  accessKey: 'ak-placeholder',
  secretKey: 'sk-placeholder',
  region: 'cn-north-4',
};

const META_FILE = '_obs_meta.json';
const MOCK_DIR = '_obs_mock';

interface MockMetaIndex {
  version: number;
  objects: Record<string, ObjectMeta>;
}

// -------------------- 主类 --------------------

export class ObsClient {
  private static rootDir: string = '';
  private static cfg: ObsConfig = DEFAULT_CFG;
  private static metaIndex: MockMetaIndex = { version: 1, objects: {} };
  private static initialized: boolean = false;

  // ---------- lifecycle ----------

  static async init(context: common.UIAbilityContext, cfg?: Partial<ObsConfig>): Promise<void> {
    if (ObsClient.initialized) return;
    ObsClient.cfg = { ...DEFAULT_CFG, ...(cfg ?? {}) } as ObsConfig;
    ObsClient.rootDir = `${context.cacheDir}/${MOCK_DIR}/${ObsClient.cfg.bucket}`;
    try {
      if (!fs.accessSync(ObsClient.rootDir)) {
        // 递归建：cacheDir/MOCK_DIR + bucket
        const parent = `${context.cacheDir}/${MOCK_DIR}`;
        if (!fs.accessSync(parent)) fs.mkdirSync(parent);
        fs.mkdirSync(ObsClient.rootDir);
      }
    } catch (err) {
      console.warn(`[ObsClient] init mkdir failed: ${(err as Error).message}`);
    }
    await ObsClient.loadMeta();
    ObsClient.initialized = true;
  }

  static getConfig(): ObsConfig {
    return ObsClient.cfg;
  }

  // ---------- 公共 API ----------

  /** 上传对象。file 既支持 ArrayBuffer，也支持 string。 */
  static async upload(
    key: string,
    file: ArrayBuffer | string,
    opts?: UploadOptions,
  ): Promise<UploadResult> {
    ObsClient.assertInit();
    const abs = ObsClient.objectPath(key);
    ObsClient.ensureParent(abs);
    const fd = fs.openSync(abs, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const data = typeof file === 'string'
        ? buffer.from(file, 'utf-8').buffer
        : file;
      fs.writeSync(fd.fd, data);
    } finally {
      fs.closeSync(fd);
    }
    const stat = fs.statSync(abs);
    const meta: ObjectMeta = {
      key,
      size: stat.size,
      etag: ObsClient.fakeEtag(key, stat.size),
      contentType: opts?.contentType,
      lastModified: Date.now(),
      metadata: opts?.metadata,
    };
    ObsClient.metaIndex.objects[key] = meta;
    await ObsClient.persistMeta();
    return {
      key,
      etag: meta.etag,
      size: meta.size,
      versionId: undefined,
    };
  }

  /** 下载到 ArrayBuffer。 */
  static async download(key: string): Promise<ArrayBuffer> {
    ObsClient.assertInit();
    const abs = ObsClient.objectPath(key);
    if (!fs.accessSync(abs)) {
      throw new Error(`obs_object_not_found: ${key}`);
    }
    const fd = fs.openSync(abs, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(fd.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(fd.fd, buf);
      return buf;
    } finally {
      fs.closeSync(fd);
    }
  }

  /**
   * 预签名 URL。Mock 实现仅生成 obsmock:// URL。
   * Phase 4 真实 SDK 时返回带 SignatureV2/V4 query 的 https URL。
   */
  static async getSignedUrl(key: string, expirySec: number = 3600): Promise<string> {
    ObsClient.assertInit();
    const expiresAt = Math.floor(Date.now() / 1000) + Math.max(60, expirySec);
    const sig = ObsClient.fakeEtag(key, expiresAt).slice(0, 16);
    return `obsmock://${ObsClient.cfg.bucket}/${encodeURIComponent(key)}?expiresAt=${expiresAt}&sig=${sig}`;
  }

  /** 元信息查询。 */
  static async head(key: string): Promise<ObjectMeta> {
    ObsClient.assertInit();
    const meta = ObsClient.metaIndex.objects[key];
    if (!meta) {
      throw new Error(`obs_object_not_found: ${key}`);
    }
    return meta;
  }

  /** 前缀列表，按 lastModified desc 排序。 */
  static async list(prefix: string, limit: number = 100): Promise<ObjectMeta[]> {
    ObsClient.assertInit();
    const all: ObjectMeta[] = [];
    const objects = ObsClient.metaIndex.objects;
    for (const k of Object.keys(objects)) {
      if (k.startsWith(prefix)) {
        all.push(objects[k]);
      }
    }
    all.sort((a, b) => b.lastModified - a.lastModified);
    return all.slice(0, Math.max(0, limit));
  }

  /** 删除对象。 */
  static async delete(key: string): Promise<void> {
    ObsClient.assertInit();
    const abs = ObsClient.objectPath(key);
    try {
      if (fs.accessSync(abs)) fs.unlinkSync(abs);
    } catch (_e) { /* swallow */ }
    delete ObsClient.metaIndex.objects[key];
    await ObsClient.persistMeta();
  }

  // ---------- 内部 ----------

  private static assertInit(): void {
    if (!ObsClient.initialized) {
      throw new Error('ObsClient not initialized. Call ObsClient.init() in EntryAbility first.');
    }
  }

  private static objectPath(key: string): string {
    // 防越界：把 key 中的 / 全部转 __；mock 不实现真正的目录树
    const safe = key.replace(/\\/g, '_').replace(/\//g, '__');
    return `${ObsClient.rootDir}/${safe}`;
  }

  private static ensureParent(absFile: string): void {
    const idx = absFile.lastIndexOf('/');
    if (idx < 0) return;
    const parent = absFile.slice(0, idx);
    try {
      if (!fs.accessSync(parent)) fs.mkdirSync(parent);
    } catch (_e) { /* swallow */ }
  }

  private static fakeEtag(key: string, sizeOrExpiry: number): string {
    // 不引入 crypto 依赖；只是 mock 用于测试
    let h = 0;
    const s = `${key}:${sizeOrExpiry}`;
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) - h) + s.charCodeAt(i);
      h |= 0;
    }
    const hex = (h >>> 0).toString(16).padStart(8, '0');
    return `mock-${hex}`;
  }

  private static async persistMeta(): Promise<void> {
    try {
      const abs = `${ObsClient.rootDir}/${META_FILE}`;
      const json = JSON.stringify(ObsClient.metaIndex);
      const fd = fs.openSync(abs, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const u8 = new Uint8Array(buffer.from(json, 'utf-8').buffer);
        fs.writeSync(fd.fd, u8.buffer);
      } finally {
        fs.closeSync(fd);
      }
    } catch (err) {
      console.warn(`[ObsClient] persistMeta failed: ${(err as Error).message}`);
    }
  }

  private static async loadMeta(): Promise<void> {
    const abs = `${ObsClient.rootDir}/${META_FILE}`;
    try {
      if (!fs.accessSync(abs)) return;
      const fd = fs.openSync(abs, fs.OpenMode.READ_ONLY);
      try {
        const stat = fs.statSync(fd.fd);
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(fd.fd, buf);
        const text = buffer.from(buf).toString('utf-8');
        ObsClient.metaIndex = JSON.parse(text) as MockMetaIndex;
        if (!ObsClient.metaIndex.objects) ObsClient.metaIndex.objects = {};
      } finally {
        fs.closeSync(fd);
      }
    } catch (err) {
      console.warn(`[ObsClient] loadMeta failed, reset: ${(err as Error).message}`);
      ObsClient.metaIndex = { version: 1, objects: {} };
    }
  }
}
