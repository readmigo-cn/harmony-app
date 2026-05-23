/**
 * ContinuationManager — 阅读接续管理器（W11-C3 + W13-C3 增强）
 *
 * 职责：
 *   - 注册 / 注销当前阅读会话到 HarmonyOS 分布式 KV（让附近设备发现可接续）
 *   - 周期检测附近可接续的设备列表（手机/平板/手表/PC）via DeviceManager
 *   - 主动发起转移：把当前会话推到目标设备（context.startAbility ContinueReadingAbility）
 *   - 监听其它设备发起的接续请求 → 触发 onIncomingContinuation 回调（业务层弹 toast）
 *   - 与 EntryAbility lifecycle 集成（onForeground / onBackground 自动启停 polling）
 *
 * 与 ContinueReadingAbility 的协作：
 *   - Reader 页 aboutToAppear → enableContinuation
 *   - Reader 页 aboutToDisappear → disableContinuation
 *   - 用户在 DeviceSelectorSheet 选目标设备 → transferTo → 系统启动 ContinueReadingAbility
 *
 * 数据通道选择：
 *   - 短期：分布式 KV（@ohos.distributedKVStore）— 跨设备同步当前阅读会话
 *   - 长期：HarmonyOS Continuation 框架（系统级 onContinue/onCreate hook，已在
 *     ContinueReadingAbility.ets 实现）
 *
 * 占位策略：
 *   - 模拟器：所有 distributed API 用占位 mock；transferTo 仅打 console
 *   - 真机：TODO 标注，由 W14 真机阶段替换
 */

import common from '@ohos.app.ability.common';
import Want from '@ohos.app.ability.Want';
import { DeviceManager, TrustedDevice } from '../distributed/DeviceManager';

const TAG = 'ContinuationManager';

/** 跨设备同步的会话快照（写入分布式 KV 的 value 结构）。 */
export interface ContinuationSession {
  bookId: string;
  bookTitle: string;
  chapterIndex: number;
  pageIndex: number;
  percentComplete: number;
  /** 本地设备 ID（占位：实际由 deviceManager 提供）。 */
  sourceDeviceId: string;
  /** 写入时刻（ms），目标设备用此判断是否过期。 */
  updatedAt: number;
}

/** 附近可接续的设备摘要（用户面板展示用）。 */
export interface NearbyDevice {
  deviceId: string;
  deviceName: string;
  deviceType: 'phone' | 'tablet' | 'watch' | 'pc' | 'tv' | 'unknown';
  /** 该设备上是否已有同账号且可接收接续。 */
  trusted: boolean;
}

/** 接收方收到的接续请求。 */
export interface IncomingContinuationRequest {
  /** 来源设备 ID */
  sourceDeviceId: string;
  /** 来源设备名（用户可读，"Logan 的平板"） */
  sourceDeviceName: string;
  /** 对端推过来的 session 快照（章节 / 页码 / 进度） */
  session: ContinuationSession;
}

type IncomingCallback = (req: IncomingContinuationRequest) => void;

const KV_STORE_ID = 'readmigo_continuation';
const KV_KEY_PREFIX = 'reading_session_';
const POLL_INTERVAL_MS = 30_000;

class ContinuationManagerImpl {
  /** 当前已注册的接续会话。null 表示未启用。 */
  private session: ContinuationSession | null = null;
  /** 周期检测附近设备的 timer。 */
  private pollTimer: number = -1;
  /** 缓存最近一次 pollNearbyDevices 的结果。 */
  private lastNearby: NearbyDevice[] = [];
  /** 来电回调 */
  private incomingListeners: IncomingCallback[] = [];
  /** EntryAbility 是否处于前台（控制 polling 是否真正发起 IO） */
  private foreground: boolean = true;

  /**
   * 启用接续：注册当前阅读会话到分布式 KV。
   *
   * 调用时机：Reader 页 aboutToAppear / 章节切换。
   * 同 bookId 重复调用会覆盖之前的快照（更新 chapterIndex / pageIndex）。
   */
  enableContinuation(
    bookId: string,
    bookTitle: string,
    chapterIndex: number,
    pageIndex: number,
    percentComplete: number,
  ): void {
    if (!bookId) return;
    this.session = {
      bookId,
      bookTitle,
      chapterIndex,
      pageIndex,
      percentComplete,
      sourceDeviceId: this.getLocalDeviceId(),
      updatedAt: Date.now(),
    };
    this.writeToKvStore(this.session);
    this.startPolling();
    console.info(`${TAG} enableContinuation bookId=${bookId} chapter=${chapterIndex}`);
  }

  /**
   * 增量更新当前会话（不重置 timer）。
   * Reader 翻页 / 章节切换可频繁调用。
   */
  updateProgress(chapterIndex: number, pageIndex: number, percentComplete: number): void {
    if (!this.session) return;
    this.session.chapterIndex = chapterIndex;
    this.session.pageIndex = pageIndex;
    this.session.percentComplete = percentComplete;
    this.session.updatedAt = Date.now();
    this.writeToKvStore(this.session);
  }

  /**
   * 关闭接续：从分布式 KV 中删除会话条目，停止 polling。
   *
   * 调用时机：Reader 页 aboutToDisappear / 用户切换书籍。
   */
  disableContinuation(bookId: string): void {
    if (!this.session || this.session.bookId !== bookId) {
      this.stopPolling();
      this.session = null;
      return;
    }
    this.deleteFromKvStore(bookId);
    this.session = null;
    this.stopPolling();
    console.info(`${TAG} disableContinuation bookId=${bookId}`);
  }

  /**
   * 检测附近可接续的设备。
   *
   * 真实实现：DeviceManager.discoverDevices() → 过滤 trusted + 在线 + 非本机
   * 同账号设备发现（W13-C3 增强）：发现后若有非本机设备活跃 → emit incoming candidate
   *
   * 周期内反复调用会去重（lastNearby cache）。
   */
  async pollNearbyDevices(): Promise<NearbyDevice[]> {
    if (!this.foreground) return this.lastNearby;
    try {
      const all: TrustedDevice[] = await DeviceManager.discoverDevices();
      const nearby: NearbyDevice[] = all
        .filter((d) => !d.isLocal && d.online)
        .map((d) => ({
          deviceId: d.deviceId,
          deviceName: d.deviceName,
          deviceType: d.deviceType === 'car' ? 'unknown' : d.deviceType,
          trusted: true,
        }));
      this.lastNearby = nearby;
      console.info(`${TAG} pollNearbyDevices found=${nearby.length}`);
      return nearby;
    } catch (e) {
      console.warn(`${TAG} pollNearbyDevices failed: ${(e as Error).message}`);
      return this.lastNearby;
    }
  }

  /** 同步获取最近一次缓存的设备列表（无 IO）。 */
  getCachedNearbyDevices(): NearbyDevice[] {
    return this.lastNearby;
  }

  /**
   * 主动转移到目标设备。
   *
   * 真机实现：context.startAbility(want) 带 deviceId + ContinueReadingAbility 名
   *   want = {
   *     deviceId: targetDeviceId,
   *     bundleName, abilityName: 'ContinueReadingAbility',
   *     parameters: { bookId, chapterIndex, pageIndex, percentComplete }
   *   }
   * 占位：把目标 deviceId 写到日志，业务层用 toast 反馈。
   *
   * @param deviceId 目标设备 ID（DeviceManager 中的 deviceId / networkId）
   * @param ctx UIAbilityContext，调用方持有
   */
  async transferTo(deviceId: string, ctx?: common.UIAbilityContext): Promise<boolean> {
    if (!this.session) {
      console.warn(`${TAG} transferTo no active session`);
      return false;
    }
    if (!deviceId) {
      console.warn(`${TAG} transferTo empty deviceId`);
      return false;
    }
    try {
      // TODO(W14 真机)：替换为真实 startAbility 调用
      // const want: Want = {
      //   deviceId,
      //   bundleName: 'cn.readmigo.app',
      //   abilityName: 'ContinueReadingAbility',
      //   parameters: {
      //     bookId: this.session.bookId,
      //     chapterIndex: this.session.chapterIndex,
      //     pageIndex: this.session.pageIndex,
      //     percentComplete: this.session.percentComplete,
      //     sourceDeviceId: this.session.sourceDeviceId,
      //   },
      // };
      // await ctx?.startAbility(want);
      const _placeholderWant: Want = {
        bundleName: 'cn.readmigo.app',
        abilityName: 'ContinueReadingAbility',
        parameters: {
          bookId: this.session.bookId,
          chapterIndex: this.session.chapterIndex,
        },
      };
      console.info(
        `${TAG} transferTo (mock) targetDevice=${deviceId} bookId=${this.session.bookId} hasCtx=${ctx !== undefined}`,
      );
      return true;
    } catch (e) {
      console.warn(`${TAG} transferTo failed: ${(e as Error).message}`);
      return false;
    }
  }

  /**
   * 注册「收到来自其它设备的接续请求」回调。
   *
   * 真实场景：分布式 KV.on('dataChange') 监听到 KV_KEY_PREFIX/* 由对端写入 →
   *   解析 ContinuationSession + 查 sourceDeviceName → 走 incomingListeners
   * 占位：在模拟器永不触发，仅注册 listener 以保证 API 完整。
   *
   * UI 侧典型用法（Reader / Index）：
   *   ContinuationManager.onIncomingContinuation((req) => {
   *     ToastManager.info(`平板上正在读到第 ${req.session.chapterIndex+1} 章，是否接续？`);
   *   });
   */
  onIncomingContinuation(cb: IncomingCallback): () => void {
    this.incomingListeners.push(cb);
    return () => {
      const i = this.incomingListeners.indexOf(cb);
      if (i >= 0) this.incomingListeners.splice(i, 1);
    };
  }

  /** 内部 / 测试用：手动模拟一次 incoming 请求。 */
  emitIncomingForTest(req: IncomingContinuationRequest): void {
    for (const cb of this.incomingListeners) {
      try { cb(req); } catch (_) { /* ignore */ }
    }
  }

  // ─── EntryAbility lifecycle 集成（W13-C3 增强） ───

  /**
   * 应用回到前台：恢复 polling（如果已有 active session）。
   * EntryAbility.onForeground 调用。
   */
  onAppForeground(): void {
    this.foreground = true;
    if (this.session) {
      this.startPolling();
    }
    console.info(`${TAG} onAppForeground hasSession=${this.session !== null}`);
  }

  /**
   * 应用进入后台：暂停 polling 节省电量；session 仍在 KV 中保留 30 分钟。
   * EntryAbility.onBackground 调用。
   */
  onAppBackground(): void {
    this.foreground = false;
    this.stopPolling();
    console.info(`${TAG} onAppBackground`);
  }

  /** 当前是否有活跃的接续会话。 */
  hasActiveSession(): boolean {
    return this.session !== null;
  }

  getActiveSession(): ContinuationSession | null {
    return this.session;
  }

  // ─────────── private ───────────

  private startPolling(): void {
    if (this.pollTimer !== -1) return;
    if (!this.foreground) return;
    this.pollTimer = setInterval(() => {
      this.pollNearbyDevices().catch(() => {});
    }, POLL_INTERVAL_MS) as unknown as number;
  }

  private stopPolling(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  /**
   * 占位：写入分布式 KV。
   *
   * 真实实现：
   *   const kvManager = distributedKVStore.createKVManager({ context, bundleName });
   *   const store = kvManager.getKVStore(KV_STORE_ID, options);
   *   store.put(KV_KEY_PREFIX + session.bookId, JSON.stringify(session));
   */
  private writeToKvStore(session: ContinuationSession): void {
    const key = KV_KEY_PREFIX + session.bookId;
    console.info(`${TAG} kv.put (mock) ${key} chapter=${session.chapterIndex}`);
  }

  /** 占位：从分布式 KV 删除条目。 */
  private deleteFromKvStore(bookId: string): void {
    const key = KV_KEY_PREFIX + bookId;
    console.info(`${TAG} kv.delete (mock) ${key}`);
  }

  /** 占位：获取本地设备 ID。 */
  private getLocalDeviceId(): string {
    // 真实：DeviceManager.getLocalDeviceId() / deviceManager.getLocalDeviceInfoSync().deviceId
    return DeviceManager.getLocalDeviceId();
  }
}

/** 单例导出 */
export const ContinuationManager = new ContinuationManagerImpl();
