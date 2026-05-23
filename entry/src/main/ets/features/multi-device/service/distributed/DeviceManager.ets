/**
 * DeviceManager.ets — W13-C1 附近设备发现与信任管理
 *
 * 职责：
 *   - 调用 @ohos.distributedHardware.deviceManager 创建本应用的 deviceManager 实例
 *   - 扫描附近受信设备（同账号 / 已认证 HarmonyOS 设备）
 *   - 监听设备上下线事件，给 UI 推送变更
 *   - 提供同步获取本机信息 / 远端设备摘要
 *
 * 与上层组件协作：
 *   - DeviceSelectorSheet 通过 discoverDevices() 拉列表（首次加载）
 *   - ContinuationManager.pollNearbyDevices() 也走本类
 *
 * 占位策略：
 *   - 模拟器 / 单机：返回 mock 列表（local self + 1 mock peer）
 *   - 真机：TODO 标注，由 W14 真机调试阶段替换为真实 API 调用
 *
 * 真实 API 参考：
 *   import deviceManager from '@ohos.distributedHardware.deviceManager';
 *   deviceManager.createDeviceManager(bundleName, (err, dm) => {...});
 *   dm.getAvailableDeviceListSync();
 *   dm.on('deviceStateChange', cb);
 */

const TAG = 'DeviceManager';

/** 设备类型枚举（与 HarmonyOS device-type 对齐） */
export type DeviceType =
  | 'phone'
  | 'tablet'
  | 'watch'
  | 'pc'
  | 'tv'
  | 'car'
  | 'unknown';

/** 受信设备摘要：UI 列表 / 分布式同步使用。 */
export interface TrustedDevice {
  /** 设备唯一 ID（HarmonyOS deviceId，匿名 UUID） */
  deviceId: string;
  /** 用户可读名称（"Logan 的平板"） */
  deviceName: string;
  /** 设备类型 */
  deviceType: DeviceType;
  /** 软总线 networkId（startAbility / continuation 调用用） */
  networkId: string;
  /** 在线状态（false 表示已离线但仍在受信列表） */
  online: boolean;
  /** 是否本机 */
  isLocal: boolean;
}

/** 设备状态变更类型 */
export type DeviceChangeType = 'online' | 'offline' | 'change';

export interface DeviceChangeEvent {
  type: DeviceChangeType;
  device: TrustedDevice;
}

type DeviceChangeCallback = (e: DeviceChangeEvent) => void;

class DeviceManagerImpl {
  private bundleName: string = '';
  /** 真实 deviceManager 实例占位（真机替换为 deviceManager.DeviceManager） */
  private dmInstance: object | null = null;
  private inited: boolean = false;
  private listeners: DeviceChangeCallback[] = [];
  /** 缓存上一次扫描结果，避免短时多次调用真实 API */
  private cache: TrustedDevice[] = [];
  private cacheAt: number = 0;
  private static readonly CACHE_TTL_MS = 5_000;

  /**
   * 初始化 deviceManager。
   * 必须传 bundleName（与 module.json5 一致），HarmonyOS 框架据此做权限校验。
   */
  async init(bundleName: string): Promise<void> {
    if (this.inited) return;
    this.bundleName = bundleName;
    try {
      // TODO(W14 真机)：替换为真实 API
      // const deviceManager = require('@ohos.distributedHardware.deviceManager');
      // this.dmInstance = await new Promise((resolve, reject) => {
      //   deviceManager.createDeviceManager(bundleName, (err, dm) => {
      //     if (err) reject(err); else resolve(dm);
      //   });
      // });
      // this.dmInstance.on('deviceStateChange', (data) => this.onDeviceStateChange(data));
      this.dmInstance = null;
      this.inited = true;
      console.info(`${TAG} init bundleName=${bundleName} (mock)`);
    } catch (e) {
      console.warn(`${TAG} init failed: ${(e as Error).message}`);
    }
  }

  /**
   * 扫描附近受信设备。
   *
   * 模拟器：返回 mock 列表（self + 1 个 mock peer 'tablet-mock-001'）
   * 真机：调用 dmInstance.getAvailableDeviceListSync() + getTrustedDeviceListSync() 合并
   */
  async discoverDevices(): Promise<TrustedDevice[]> {
    const now = Date.now();
    if (now - this.cacheAt < DeviceManagerImpl.CACHE_TTL_MS && this.cache.length > 0) {
      return this.cache;
    }
    let list: TrustedDevice[] = [];
    try {
      // TODO(W14 真机)：替换为真实 API
      // const trusted = (this.dmInstance as DeviceManager).getTrustedDeviceListSync();
      // const available = (this.dmInstance as DeviceManager).getAvailableDeviceListSync();
      // list = mergeAndDedupe(trusted, available).map(toTrustedDevice);
      list = this.mockDevices();
    } catch (e) {
      console.warn(`${TAG} discoverDevices failed: ${(e as Error).message}`);
      list = this.mockDevices();
    }
    this.cache = list;
    this.cacheAt = now;
    console.info(`${TAG} discoverDevices count=${list.length} (mock)`);
    return list;
  }

  /**
   * 订阅设备上下线变更。
   *
   * 真机：dmInstance.on('deviceStateChange', cb) → 在 onDeviceStateChange 内分发
   * 占位：不会触发回调（mock 阶段无真实事件源）
   */
  subscribeDeviceChange(cb: DeviceChangeCallback): () => void {
    this.listeners.push(cb);
    return () => {
      const i = this.listeners.indexOf(cb);
      if (i >= 0) this.listeners.splice(i, 1);
    };
  }

  /** 取消订阅所有 listener；通常在 EntryAbility.onDestroy 调用。 */
  unsubscribeAll(): void {
    this.listeners = [];
    // TODO(W14 真机)：(this.dmInstance as DeviceManager).off('deviceStateChange', ...)
  }

  /** 同步查询单个设备信息（缓存命中），找不到返回 null。 */
  getDeviceInfo(deviceId: string): TrustedDevice | null {
    for (const d of this.cache) {
      if (d.deviceId === deviceId) return d;
    }
    return null;
  }

  /** 取本机设备 ID（占位）。真机：getLocalDeviceInfoSync().deviceId */
  getLocalDeviceId(): string {
    return 'local-device';
  }

  /** 取本机设备名（占位）。真机：getLocalDeviceInfoSync().deviceName */
  getLocalDeviceName(): string {
    return '本机';
  }

  // ─────────── private ───────────

  /**
   * 真机回调入口（W14 接入后启用）：把 deviceManager 推上来的事件转成 DeviceChangeEvent。
   *
   * @param data { action: 0|1|2, device: { deviceId, deviceName, deviceType, networkId } }
   */
  // private onDeviceStateChange(data: { action: number; device: object }): void {
  //   const type: DeviceChangeType = data.action === 0 ? 'online' : data.action === 1 ? 'offline' : 'change';
  //   const dev = this.toTrustedDevice(data.device);
  //   const evt: DeviceChangeEvent = { type, device: dev };
  //   this.cache = []; // 失效缓存
  //   for (const cb of this.listeners) {
  //     try { cb(evt); } catch (_) { /* ignore */ }
  //   }
  // }

  /** Mock 列表：模拟器 / 真机未授权时回退。 */
  private mockDevices(): TrustedDevice[] {
    return [
      {
        deviceId: 'local-device',
        deviceName: '本机',
        deviceType: 'phone',
        networkId: 'local-net',
        online: true,
        isLocal: true,
      },
      {
        deviceId: 'tablet-mock-001',
        deviceName: 'MatePad Pro（演示）',
        deviceType: 'tablet',
        networkId: 'mock-net-001',
        online: true,
        isLocal: false,
      },
    ];
  }
}

/** 单例导出 */
export const DeviceManager = new DeviceManagerImpl();
