/**
 * DeviceManager.ets — W5 真机设备发现与信任管理
 *
 * 使用 @ohos.distributedDeviceManager（API 11+，@kit.DistributedServiceKit）
 * 实现真实设备发现、上下线监听、本机信息获取。
 *
 * 降级策略：
 *   - 若 createDeviceManager 失败（模拟器 / 权限未授权），自动回退到 mock 列表
 *   - mock 列表仅作为占位，true device session 不受影响
 *
 * 权限要求（module.json5 需声明）：
 *   ohos.permission.DISTRIBUTED_DATASYNC
 *   ohos.permission.ACCESS_BLUETOOTH（部分设备发现场景需要）
 */

import distributedDeviceManager from '@ohos.distributedDeviceManager';

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

/** Maps HarmonyOS numeric deviceType to our enum. */
function toDeviceType(t: number): DeviceType {
  switch (t) {
    case 0x0E: return 'phone';
    case 0x11: return 'tablet';
    case 0x6D: return 'watch';
    case 0x0C: return 'pc';
    case 0x9C: return 'tv';
    case 0x83: return 'car';
    default: return 'unknown';
  }
}

function toTrustedDevice(d: distributedDeviceManager.DeviceBasicInfo, online: boolean): TrustedDevice {
  return {
    deviceId: d.deviceId ?? '',
    deviceName: d.deviceName ?? '',
    deviceType: toDeviceType(d.deviceType ?? 0),
    networkId: d.networkId ?? '',
    online,
    isLocal: false,
  };
}

class DeviceManagerImpl {
  private bundleName: string = '';
  private dmInstance: distributedDeviceManager.DeviceManager | null = null;
  private inited: boolean = false;
  private listeners: DeviceChangeCallback[] = [];
  private cache: TrustedDevice[] = [];
  private cacheAt: number = 0;
  private static readonly CACHE_TTL_MS = 5_000;
  private useMock: boolean = false;

  /**
   * Initialize deviceManager.
   * bundleName must match module.json5. HarmonyOS framework does permission check.
   */
  async init(bundleName: string): Promise<void> {
    if (this.inited) return;
    this.bundleName = bundleName;
    try {
      this.dmInstance = distributedDeviceManager.createDeviceManager(bundleName);
      this.dmInstance.on('deviceStateChange', (data: distributedDeviceManager.DeviceStateChange) => {
        this.onDeviceStateChange(data);
      });
      this.useMock = false;
      this.inited = true;
      console.info(`${TAG} init bundleName=${bundleName} (real API)`);
    } catch (e) {
      // Fallback: simulator / permission not granted
      this.dmInstance = null;
      this.useMock = true;
      this.inited = true;
      console.warn(`${TAG} init failed, using mock: ${(e as Error).message}`);
    }
  }

  /**
   * Discover nearby trusted devices (same HarmonyOS account).
   * Returns cached result within CACHE_TTL_MS.
   */
  async discoverDevices(): Promise<TrustedDevice[]> {
    const now = Date.now();
    if (now - this.cacheAt < DeviceManagerImpl.CACHE_TTL_MS && this.cache.length > 0) {
      return this.cache;
    }
    let list: TrustedDevice[] = [];
    if (this.useMock || !this.dmInstance) {
      list = this.mockDevices();
    } else {
      try {
        const available = this.dmInstance.getAvailableDeviceListSync();
        list = (available ?? []).map((d) => toTrustedDevice(d, true));
        // Prepend local device
        const local = this.buildLocalDevice();
        if (local) list.unshift(local);
      } catch (e) {
        console.warn(`${TAG} discoverDevices failed: ${(e as Error).message}`);
        list = this.mockDevices();
      }
    }
    this.cache = list;
    this.cacheAt = now;
    return list;
  }

  /**
   * Subscribe to device online/offline changes.
   * Returns unsubscribe handle.
   */
  subscribeDeviceChange(cb: DeviceChangeCallback): () => void {
    this.listeners.push(cb);
    return () => {
      const i = this.listeners.indexOf(cb);
      if (i >= 0) this.listeners.splice(i, 1);
    };
  }

  /** Emit device online event from SoulEngine status callback. @since W5 */
  onDeviceOnline(cb: (device: TrustedDevice) => void): () => void {
    return this.subscribeDeviceChange((e) => {
      if (e.type === 'online') cb(e.device);
    });
  }

  /** Emit device offline event from SoulEngine status callback. @since W5 */
  onDeviceOffline(cb: (device: TrustedDevice) => void): () => void {
    return this.subscribeDeviceChange((e) => {
      if (e.type === 'offline') cb(e.device);
    });
  }

  /**
   * Returns current known devices (stable list for SurfaceContext / continuation-dev).
   * Includes local device as first entry. @since W5
   */
  currentDevices(): TrustedDevice[] {
    if (this.cache.length > 0) return this.cache.slice();
    return this.mockDevices();
  }

  /** Unsubscribe all listeners; call in EntryAbility.onDestroy. */
  unsubscribeAll(): void {
    this.listeners = [];
    if (this.dmInstance) {
      try {
        this.dmInstance.off('deviceStateChange');
      } catch (_e) { /* ignore */ }
    }
  }

  /** Synchronously look up a single device from cache. Returns null if not found. */
  getDeviceInfo(deviceId: string): TrustedDevice | null {
    for (const d of this.cache) {
      if (d.deviceId === deviceId) return d;
    }
    return null;
  }

  /** Returns local device ID via real API or fallback string. */
  getLocalDeviceId(): string {
    if (this.dmInstance) {
      try {
        return this.dmInstance.getLocalDeviceId();
      } catch (_e) { /* fall through */ }
    }
    return 'local-device';
  }

  /** Returns local device name via real API or fallback string. */
  getLocalDeviceName(): string {
    if (this.dmInstance) {
      try {
        return this.dmInstance.getLocalDeviceName();
      } catch (_e) { /* fall through */ }
    }
    return '本机';
  }

  // ─────────── private ───────────

  private onDeviceStateChange(data: distributedDeviceManager.DeviceStateChange): void {
    const actionMap: Record<number, DeviceChangeType> = { 0: 'online', 1: 'offline', 2: 'change' };
    const type: DeviceChangeType = actionMap[data.action] ?? 'change';
    const dev = toTrustedDevice(data.device, type === 'online');
    const evt: DeviceChangeEvent = { type, device: dev };
    // Invalidate cache on state change
    this.cache = [];
    this.cacheAt = 0;
    for (const cb of this.listeners) {
      try { cb(evt); } catch (_e) { /* ignore */ }
    }
  }

  private buildLocalDevice(): TrustedDevice | null {
    if (!this.dmInstance) return null;
    try {
      return {
        deviceId: this.dmInstance.getLocalDeviceId(),
        deviceName: this.dmInstance.getLocalDeviceName(),
        deviceType: 'phone',
        networkId: 'local',
        online: true,
        isLocal: true,
      };
    } catch (_e) {
      return null;
    }
  }

  /** Mock list: used on simulator or when permission is not granted. */
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
