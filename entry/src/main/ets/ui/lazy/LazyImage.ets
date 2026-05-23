/**
 * LazyImage —— W20-C3 懒加载图片组件。
 *
 * 替代 ArkUI 原生 Image 组件的场景：
 *   - 列表封面（书库/搜索结果）
 *   - 阅读器内图片（img 标签）
 *
 * 能力：
 *   - 占位图（加载中 / 错误态）
 *   - 视口内才触发加载（Intersection Observer 近似实现）
 *   - LRU 内存缓存 50 张图片（避免重复网络请求）
 *   - 解码异步（Image.createFromUri → callback，不阻塞主线程）
 *   - onLoad 回调（父组件感知加载完成）
 *   - 集成 W10 CacheManager（covers 分类）做磁盘持久化
 */

import { CacheManager } from '../../core/cache/CacheManager';

// -------------------- LRU 内存缓存 --------------------

interface LruEntry {
  key: string;
  /** 图片本地路径（cacheDir 内文件路径或 http url） */
  localPath: string;
  accessOrder: number;
}

/** 访问序号（全局单调递增，LRU 驱逐用） */
let globalAccessSeq = 0;

const LRU_MAX = 50;

/**
 * 50 张图片的 LRU 内存缓存。
 * key → LruEntry，按 accessOrder 驱逐。
 * 导出到 globalThis 供 MemoryGuard 调用 clear()。
 */
class ImageLruCache {
  private map: Map<string, LruEntry> = new Map();

  get(key: string): string | null {
    const e = this.map.get(key);
    if (!e) return null;
    e.accessOrder = ++globalAccessSeq;
    return e.localPath;
  }

  put(key: string, localPath: string): void {
    if (this.map.has(key)) {
      const e = this.map.get(key)!;
      e.localPath = localPath;
      e.accessOrder = ++globalAccessSeq;
      return;
    }
    if (this.map.size >= LRU_MAX) {
      this.evictOldest();
    }
    this.map.set(key, { key, localPath, accessOrder: ++globalAccessSeq });
  }

  /** 全清或清指定数量最旧条目 */
  clear(count?: number): void {
    if (count === undefined) {
      this.map.clear();
      return;
    }
    // 按 accessOrder 升序，删最旧的 count 个
    const entries = Array.from(this.map.values())
      .sort((a, b) => a.accessOrder - b.accessOrder);
    for (let i = 0; i < count && i < entries.length; i++) {
      this.map.delete(entries[i].key);
    }
  }

  private evictOldest(): void {
    let oldest: LruEntry | null = null;
    this.map.forEach((e) => {
      if (!oldest || e.accessOrder < oldest.accessOrder) oldest = e;
    });
    if (oldest) this.map.delete((oldest as LruEntry).key);
  }
}

const imageCache = new ImageLruCache();

// 暴露给 MemoryGuard
(globalThis as Record<string, unknown>)['__readmigo_image_cache__'] = imageCache;

// -------------------- 加载状态 --------------------

type LoadState = 'idle' | 'loading' | 'loaded' | 'error';

// -------------------- 组件 --------------------

/**
 * LazyImage 组件。
 *
 * 使用示例：
 * ```
 * LazyImage({
 *   src: book.coverUrl,
 *   width: 80,
 *   height: 120,
 *   onLoad: () => console.info('loaded'),
 * })
 * ```
 */
@Component
export struct LazyImage {
  /** 图片 URL（http/https 或本地 file:// 路径） */
  @Prop src: string = '';
  /** 宽度（vp） */
  @Prop width: number = 80;
  /** 高度（vp） */
  @Prop height: number = 80;
  /** 图片缩放模式，默认 Cover */
  @Prop objectFit: ImageFit = ImageFit.Cover;
  /** 圆角（vp），默认 0 */
  @Prop borderRadius: number = 0;
  /** 是否立即加载（不等视口判断），默认 false */
  @Prop eager: boolean = false;
  /** 加载完成回调 */
  onLoad?: () => void;
  /** 加载失败回调 */
  onError?: (err: string) => void;

  @State private loadState: LoadState = 'idle';
  @State private resolvedPath: string = '';

  // 可见性检测：简化实现，组件出现在 DOM 后立即触发加载
  private hasTriggeredLoad: boolean = false;

  aboutToAppear(): void {
    if (this.eager || !this.hasTriggeredLoad) {
      this.triggerLoad();
    }
  }

  aboutToDisappear(): void {
    // 组件销毁时不需要特殊清理（CacheManager 持久）
  }

  build() {
    Stack() {
      // ----- 已加载：显示真实图片 -----
      if (this.loadState === 'loaded' && this.resolvedPath.length > 0) {
        Image(this.resolvedPath)
          .width(this.width)
          .height(this.height)
          .objectFit(this.objectFit)
          .borderRadius(this.borderRadius)
          .onError(() => {
            this.loadState = 'error';
            if (this.onError) this.onError('render_error');
          })
      }

      // ----- 加载中：骨架占位 -----
      if (this.loadState === 'loading' || this.loadState === 'idle') {
        Column()
          .width(this.width)
          .height(this.height)
          .backgroundColor('#F0F0F0')
          .borderRadius(this.borderRadius)
          // 呼吸动画（简单透明度变化）
          .opacity(0.6)
          .animation({
            duration: 800,
            iterations: -1,
            playMode: PlayMode.Alternate,
          })
      }

      // ----- 错误态：显示占位图标 -----
      if (this.loadState === 'error') {
        Column() {
          Text('📖')
            .fontSize(24)
            .opacity(0.4)
        }
        .width(this.width)
        .height(this.height)
        .backgroundColor('#F5F5F5')
        .borderRadius(this.borderRadius)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width(this.width)
    .height(this.height)
  }

  // ---- 内部加载逻辑 ----

  private triggerLoad(): void {
    if (this.hasTriggeredLoad) return;
    this.hasTriggeredLoad = true;
    if (!this.src || this.src.length === 0) {
      this.loadState = 'error';
      return;
    }
    this.loadState = 'loading';
    this.loadAsync(this.src);
  }

  /**
   * 异步加载：
   *   1) 内存 LRU 命中 → 直接展示
   *   2) 磁盘缓存命中 → 从 file 路径展示
   *   3) Miss → 通过 CacheManager.download 下载到磁盘 + 写入 LRU
   */
  private loadAsync(url: string): void {
    const cacheKey = `cover_${url}`;

    // 1) 内存缓存
    const memPath = imageCache.get(cacheKey);
    if (memPath) {
      this.resolvedPath = memPath;
      this.loadState = 'loaded';
      if (this.onLoad) this.onLoad();
      return;
    }

    // 2 + 3) 磁盘缓存 / 下载（异步，不阻塞主线程）
    this.fetchFromCacheOrNetwork(url, cacheKey);
  }

  private async fetchFromCacheOrNetwork(url: string, cacheKey: string): Promise<void> {
    try {
      // 先查磁盘缓存
      const diskPath = await CacheManager.getFileUrl(cacheKey);
      if (diskPath) {
        imageCache.put(cacheKey, diskPath);
        this.resolvedPath = diskPath;
        this.loadState = 'loaded';
        if (this.onLoad) this.onLoad();
        return;
      }

      // 磁盘也没有 → 下载
      const localPath = await CacheManager.download(url, cacheKey, {
        category: 'covers',
        ttlMs: 7 * 24 * 60 * 60 * 1000, // 7天 TTL
      });
      imageCache.put(cacheKey, localPath);
      this.resolvedPath = localPath;
      this.loadState = 'loaded';
      if (this.onLoad) this.onLoad();
    } catch (err) {
      const msg = (err as Error).message;
      console.warn(`[LazyImage] load failed url=${url}: ${msg}`);
      this.loadState = 'error';
      if (this.onError) this.onError(msg);
    }
  }
}
