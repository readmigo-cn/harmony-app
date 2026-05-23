/**
 * Badge Engine native bridge wrapper.
 *
 * 与 native 侧绑定关系：
 *   - C++ 静态库          https://gitee.com/readmigo/readmigo-badge-engine  (badge_engine.h / types.h)
 *   - NAPI 桥接            https://gitee.com/readmigo/readmigo-napi-bridge  (src/badge_engine_napi.cpp)
 *   - 链接产物             entry/libs/arm64-v8a/libreadmigo_native.so
 *
 * NAPI 暴露在 `libreadmigo_native.so` 上的子命名空间 `badge_engine`。
 * 渲染需要绑定一个 surface（HarmonyOS XComponent 的 native window）；ArkTS
 * 侧拿到的是 `surfaceId` 字符串，native 桥接把它解析为 `OHNativeWindow*`。
 *
 * 切换到真实 .so 步骤：与 typesetting.ets 一致 —— 把 NATIVE_AVAILABLE 改为 true。
 */

let NATIVE_AVAILABLE: boolean = false;

// ---------------------------------------------------------------------------
// 公共类型
// ---------------------------------------------------------------------------

/** 勋章面索引（与 types.h: BadgeFaceIndex 严格对应）。 */
export enum BadgeFace {
  Front = 0,   // GoldFront — 主前面
  Icon = 1,    // GoldIcon — 浮雕图标区
  Back = 2,    // GoldBack — 背面
  // 预留扩展（边缘 / 缎带），native 暂未实现。
  Edge = 3,
}

/** 仪式动画类型（与 types.h: BadgeCeremonyType 对应）。 */
export enum CeremonyType {
  /** 首次解锁勋章的开箱仪式。 */
  UnboxOpening = 0,
  /** 解锁完成后的闪烁。 */
  Sparkle = 1,
  /** 卡片翻转。 */
  Flip = 2,
}

/** 触摸事件类型（与 types.h: BadgeTouchType 对应）。 */
export enum BadgeTouchPhase {
  Down = 0,
  Move = 1,
  Up = 2,
  Cancel = 3,
}

/** 渲染模式（embedded = 30FPS preview / fullscreen = 60FPS detail）。 */
export type BadgeRenderMode = 'embedded' | 'fullscreen';

/** native 回调事件类型（与 types.h: BadgeEventType 对应）。 */
export enum BadgeEventKind {
  CeremonyPhase = 0,
  CeremonyDone = 1,
  FlipToBack = 2,
  FlipToFront = 3,
  Haptic = 4,
  Sound = 5,
  Ready = 6,
}

/** native 回调事件 payload。 */
export interface BadgeEvent {
  type: BadgeEventKind;
  data: number;       // 仪式 phase index / haptic style / 等
  dataStr?: string;   // sound asset name 等
}

/** 触摸事件（与 types.h: BadgeTouchEvent 对应）。 */
export interface BadgeTouchEvent {
  phase: BadgeTouchPhase;
  x: number;
  y: number;
  /** 1 = 单指，2 = 双指（捏合）。 */
  pointerCount: number;
  /** 第二指坐标（仅 pinch 用）。 */
  x2?: number;
  y2?: number;
}

/** 引擎初始化配置（与 types.h: BadgeEngineConfig 对应）。 */
export interface BadgeEngineConfig {
  /** 渲染目标宽（px）；XComponent.onLoad 时由 setSurface 覆写。 */
  width?: number;
  height?: number;
  renderMode?: BadgeRenderMode;
  /** presets 资源目录（rawfile/badges/ 解压后的本地路径）。 */
  presetsPath?: string;
}

/** 回调签名。 */
export type BadgeEventCallback = (event: BadgeEvent) => void;

// ---------------------------------------------------------------------------
// Native 模块加载
// ---------------------------------------------------------------------------

/** 与 https://gitee.com/readmigo/readmigo-napi-bridge (src/badge_engine_napi.cpp) 暴露的 C-side 函数对应。 */
interface NativeBadgeModule {
  create(config: BadgeEngineConfig): object;
  destroy(handle: object): void;
  setSurface(handle: object, surfaceId: string, width: number, height: number): number;
  loadModelData(handle: object, glbData: ArrayBuffer): number;
  setFaceTexture(handle: object, face: number, rgba: ArrayBuffer, width: number, height: number): number;
  setRenderMode(handle: object, mode: number): void;
  updateGyro(handle: object, x: number, y: number, z: number): void;
  onTouch(handle: object, phase: number, x: number, y: number, pointerCount: number, x2: number, y2: number): void;
  playCeremony(handle: object, type: number): void;
  setOrientation(handle: object, rx: number, ry: number, rz: number, scale: number): void;
  renderFrame(handle: object): void;
  snapshot(handle: object, width: number, height: number): ArrayBuffer;
  setCallback(handle: object, cb: (type: number, data: number, dataStr: string) => void): void;
}

let cachedNativeModule: NativeBadgeModule | null = null;

function tryLoadNative(): NativeBadgeModule | null {
  if (cachedNativeModule) return cachedNativeModule;
  if (!NATIVE_AVAILABLE) return null;
  try {
    // @ts-ignore — .so 尚未链接进 HAP 时此 import 会失败
    const top: { badge_engine?: NativeBadgeModule } | null =
      typeof globalThis['requireNapi'] === 'function'
        ? globalThis['requireNapi']('libreadmigo_native.so')
        : null;
    const mod = top?.badge_engine ?? null;
    if (mod && typeof mod.create === 'function') {
      cachedNativeModule = mod;
      return mod;
    }
  } catch (_e) {
    // fall through
  }
  NATIVE_AVAILABLE = false;
  return null;
}

// ---------------------------------------------------------------------------
// BadgeEngine —— 强类型封装
// ---------------------------------------------------------------------------

/**
 * 3D 勋章渲染引擎。生命周期：
 *   1. `new BadgeEngine(config)`
 *   2. XComponent.onLoad → `setSurface(surfaceId, w, h)`
 *   3. `loadBadgeModel(glb)` 装载模型
 *   4. RAF 循环里反复调 `renderFrame()`
 *   5. 退出时 `destroy()`
 *
 * .so 缺失时所有方法都是 no-op，方便 UI 层先写。
 */
export class BadgeEngine {
  private handle: object | null = null;
  private mod: NativeBadgeModule | null = null;
  private destroyed: boolean = false;
  private callback: BadgeEventCallback | null = null;
  private currentMode: BadgeRenderMode = 'embedded';

  /**
   * @param config 可选初始化配置；后续 setSurface 会覆盖 width/height。
   */
  constructor(config?: BadgeEngineConfig) {
    const native = tryLoadNative();
    if (native) {
      try {
        this.handle = native.create(config ?? {});
        this.mod = native;
        if (config?.renderMode) this.setRenderMode(config.renderMode);
      } catch (_e) {
        this.handle = null;
        this.mod = null;
      }
    }
  }

  /**
   * 绑定 XComponent surface。在 `XComponent.onLoad` 里拿到 surfaceId 后调用。
   * @param surfaceId  XComponentController.getXComponentSurfaceId() 返回的字符串
   * @param width      surface 宽（px）
   * @param height     surface 高（px）
   * @throws Error('set_surface_failed') 当 native 返回非 0
   */
  setSurface(surfaceId: string, width: number, height: number): void {
    this.assertAlive();
    if (!this.handle || !this.mod) return;
    const code = this.mod.setSurface(this.handle, surfaceId, width, height);
    if (code !== 0) throw new Error('set_surface_failed');
  }

  /**
   * 装载 GLB 模型（异步，避免阻塞 UI 线程）。
   * @param glbData GLB 文件二进制；可以从 rawfile / 远程下载得到
   * @throws Error('load_model_failed') 当 native 返回非 0
   */
  async loadBadgeModel(glbData: ArrayBuffer): Promise<void> {
    this.assertAlive();
    return new Promise<void>((resolve, reject) => {
      try {
        if (!this.handle || !this.mod) {
          resolve();
          return;
        }
        const code = this.mod.loadModelData(this.handle, glbData);
        if (code !== 0) reject(new Error('load_model_failed'));
        else resolve();
      } catch (e) {
        reject(e instanceof Error ? e : new Error(String(e)));
      }
    });
  }

  /**
   * 给指定面贴 RGBA8888 纹理（供个性化勋章用）。
   * @throws Error('set_texture_failed') 当 native 返回非 0
   */
  setFaceTexture(face: BadgeFace, rgbaData: ArrayBuffer, width: number, height: number): void {
    this.assertAlive();
    if (!this.handle || !this.mod) return;
    const code = this.mod.setFaceTexture(this.handle, face as number, rgbaData, width, height);
    if (code !== 0) throw new Error('set_texture_failed');
  }

  /** 切换渲染模式：embedded（30FPS）/ fullscreen（60FPS）。 */
  setRenderMode(mode: BadgeRenderMode): void {
    this.assertAlive();
    this.currentMode = mode;
    if (!this.handle || !this.mod) return;
    this.mod.setRenderMode(this.handle, mode === 'fullscreen' ? 1 : 0);
  }

  /** 当前渲染模式。 */
  getRenderMode(): BadgeRenderMode {
    return this.currentMode;
  }

  /** 推送陀螺仪数据；native 内部做平滑后驱动旋转。 */
  updateGyro(x: number, y: number, z: number): void {
    if (this.destroyed || !this.handle || !this.mod) return;
    this.mod.updateGyro(this.handle, x, y, z);
  }

  /** 推送触摸事件；native 内部做手势识别（drag / pinch）。 */
  onTouch(event: BadgeTouchEvent): void {
    if (this.destroyed || !this.handle || !this.mod) return;
    this.mod.onTouch(
      this.handle,
      event.phase as number,
      event.x,
      event.y,
      event.pointerCount,
      event.x2 ?? 0,
      event.y2 ?? 0,
    );
  }

  /** 播放仪式动画；通过回调推送 phase / done 事件。 */
  playCeremony(type: CeremonyType): void {
    this.assertAlive();
    if (!this.handle || !this.mod) return;
    this.mod.playCeremony(this.handle, type as number);
  }

  /** 直接设置朝向（用于动画 / 调试）；rx/ry/rz 为弧度，scale 均匀缩放。 */
  setOrientation(rx: number, ry: number, rz: number, scale: number): void {
    if (this.destroyed || !this.handle || !this.mod) return;
    this.mod.setOrientation(this.handle, rx, ry, rz, scale);
  }

  /** 渲染一帧；外层在 RAF / setInterval 里反复调。 */
  renderFrame(): void {
    if (this.destroyed || !this.handle || !this.mod) return;
    this.mod.renderFrame(this.handle);
  }

  /**
   * 截取当前帧到 RGBA buffer（异步，避免阻塞渲染线程）。
   * @returns 长度 = width * height * 4 的 RGBA8888 buffer
   */
  async snapshot(width: number, height: number): Promise<ArrayBuffer> {
    this.assertAlive();
    return new Promise<ArrayBuffer>((resolve, reject) => {
      try {
        if (!this.handle || !this.mod) {
          // mock：返回纯黑帧
          resolve(new ArrayBuffer(width * height * 4));
          return;
        }
        const buf = this.mod.snapshot(this.handle, width, height);
        resolve(buf);
      } catch (e) {
        reject(e instanceof Error ? e : new Error(String(e)));
      }
    });
  }

  /**
   * 注册回调；native 在仪式 phase / haptic / sound 等事件时触发。
   * 重复调用会覆盖之前的回调。
   */
  setEventCallback(callback: BadgeEventCallback): void {
    this.callback = callback;
    if (!this.handle || !this.mod) return;
    this.mod.setCallback(this.handle, (type: number, data: number, dataStr: string) => {
      if (this.callback) {
        this.callback({ type: type as BadgeEventKind, data, dataStr });
      }
    });
  }

  /** 释放 native 资源；调用后任何方法都将 no-op 或抛 'engine_destroyed'。 */
  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    if (this.handle && this.mod) {
      try {
        this.mod.destroy(this.handle);
      } catch (_e) {
        // ignore
      }
    }
    this.handle = null;
    this.mod = null;
    this.callback = null;
  }

  // ---------- 内部辅助 ------------------------------------------------------

  private assertAlive(): void {
    if (this.destroyed) throw new Error('engine_destroyed');
  }
}

/** 工厂函数（与 typesetting 风格一致）。 */
export function createBadgeEngine(config?: BadgeEngineConfig): BadgeEngine {
  return new BadgeEngine(config);
}
