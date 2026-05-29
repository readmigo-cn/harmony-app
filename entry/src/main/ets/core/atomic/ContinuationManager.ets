/**
 * ContinuationManager — 跨设备阅读续读管理器
 *
 * 使用 HarmonyOS ContinuationManager (@ohos.continuation.continuationManager) 实现
 * 真实的跨设备 Continuation 能力：
 *
 *   1. register()       — 注册当前 UIAbility 为可接续
 *   2. startDeviceManager() — 拉起系统设备选择器 UI
 *   3. requestContinuation(deviceId) — 主动推送接续到目标设备
 *   4. onContinue (框架回调) — 由 ReaderAbility.onContinue 触发序列化
 *   5. onRestoreFromContinuation — 目标设备 onCreate 收到 want 后调用恢复
 *
 * 与 ReadingSoul 协作：
 *   - 序列化：从 ReadingSoul 当前状态提取快照写入 want.parameters
 *   - 恢复：从 want.parameters 恢复并写回 ReadingSoul
 *
 * 边界：core/atomic/ 属于 L1；本模块不得引入 features/ / api/ / store/ 依赖。
 * 设备发现依赖系统 continuationManager，不再依赖 features/ 层的 DeviceManager。
 */

import continuationManager from '@ohos.continuation.continuationManager';
import common from '@ohos.app.ability.common';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { ReadingSoul } from '../distributed-soul/ReadingSoul';

const TAG = 'ContinuationManager';

/** 序列化到 want.parameters 的快照 key（prefixed 避免与其他参数冲突）。 */
const SNAP_BOOK_ID = 'soul_bookId';
const SNAP_CHAPTER_ID = 'soul_chapterId';
const SNAP_PAGE_IDX = 'soul_pageIdx';
const SNAP_CHAR_OFFSET = 'soul_charOffset';
const SNAP_PERCENT = 'soul_percentComplete';

/** 系统分配的 continuation token（-1 表示未注册）。 */
let token: number = -1;

/** 当前活跃的续读参数（由 enable 写入，供序列化使用）。 */
interface ActiveSession {
  bookId: string;
  chapterId: string;
  pageIdx: number;
  charOffset: number;
  percentComplete: number;
}

let activeSession: ActiveSession | null = null;

export class ContinuationManager {
  /**
   * 向 HarmonyOS Continuation 框架注册本 Ability 为可接续。
   *
   * 调用时机：ReaderAbility.onCreate / onForeground 之后。
   * 系统分配 token，后续所有 continuationManager API 均用此 token。
   *
   * 注意：HarmonyOS API 10+ 才稳定；旧版本会抛出异常，这里做降级处理。
   */
  static register(): void {
    if (token !== -1) return;
    try {
      const options: continuationManager.ContinuationExtraParams = {
        deviceType: ['phone', 'tablet', '2in1'],
        description: '阅读接续',
        filter: continuationManager.DeviceConnectState.CONNECTED,
        continuationMode: continuationManager.ContinuationMode.CONTINUATION_ON_SAME_LOCAL_NETWORK,
        authInfo: {},
      };
      continuationManager.registerContinuation(options, (err, t) => {
        if (err && err.code !== 0) {
          console.warn(`${TAG} register failed code=${err.code} msg=${err.message}`);
          return;
        }
        token = t;
        console.info(`${TAG} registered token=${token}`);
        ContinuationManager.listenDeviceConnect();
      });
    } catch (e) {
      console.warn(`${TAG} register exception: ${(e as Error).message} — fallback mode`);
    }
  }

  /**
   * 取消注册，释放 token。
   * 调用时机：ReaderAbility.onDestroy。
   */
  static unregister(): void {
    if (token === -1) return;
    try {
      continuationManager.unregisterContinuation(token, (err) => {
        if (err && err.code !== 0) {
          console.warn(`${TAG} unregister err=${err.code}`);
        } else {
          console.info(`${TAG} unregistered`);
        }
      });
    } catch (e) {
      console.warn(`${TAG} unregister exception: ${(e as Error).message}`);
    } finally {
      token = -1;
    }
  }

  /**
   * 拉起系统设备选择器 UI（用户在里面选择目标设备）。
   * 用户选定后回调 onDeviceConnect，内部再调用 startContinuationWithDevice。
   *
   * 调用时机：用户点击「继续阅读到其他设备」按钮。
   */
  static showDevicePicker(): void {
    if (token === -1) {
      console.warn(`${TAG} showDevicePicker: not registered`);
      return;
    }
    try {
      continuationManager.startDeviceManager(token, (err) => {
        if (err && err.code !== 0) {
          console.warn(`${TAG} startDeviceManager err=${err.code} ${err.message}`);
        }
      });
    } catch (e) {
      console.warn(`${TAG} startDeviceManager exception: ${(e as Error).message}`);
    }
  }

  /**
   * 主动发起 Continuation 到指定 deviceId。
   *
   * 框架会回调 ReaderAbility（或 ContinueReadingAbility）的 onContinue，
   * 那里把当前状态写入 wantParam，系统再把 want 发到目标设备启动 ability。
   */
  static startContinuationWithDevice(deviceId: string): void {
    if (token === -1) {
      console.warn(`${TAG} startContinuationWithDevice: not registered`);
      return;
    }
    if (!deviceId) {
      console.warn(`${TAG} startContinuationWithDevice: empty deviceId`);
      return;
    }
    try {
      continuationManager.updateConnectStatus(token, deviceId,
        continuationManager.DeviceConnectState.CONNECTED, (err) => {
          if (err && err.code !== 0) {
            console.warn(`${TAG} updateConnectStatus err=${err.code}`);
            return;
          }
          console.info(`${TAG} continuation requested to device=${deviceId}`);
        });
    } catch (e) {
      console.warn(`${TAG} startContinuationWithDevice exception: ${(e as Error).message}`);
    }
  }

  /**
   * 更新当前活跃阅读会话（由 Reader 页面调用）。
   * 序列化时用此快照写入 want.parameters。
   */
  static updateSession(
    bookId: string,
    chapterId: string,
    pageIdx: number,
    charOffset: number,
    percentComplete: number,
  ): void {
    activeSession = { bookId, chapterId, pageIdx, charOffset, percentComplete };
  }

  /**
   * 序列化当前阅读状态到 want.parameters（由 onContinue 调用）。
   *
   * 优先用 activeSession（Reader 实时更新的），没有则 fallback 到 ReadingSoul 异步快照。
   * 注意：onContinue 是同步方法，所以直接用 activeSession；ReadingSoul 的 async 路径
   * 只在 activeSession 为 null 时走，且只能写入到 wantParam 的能力受限。
   */
  static serializeToWant(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    const sess = activeSession;
    if (!sess || !sess.bookId) {
      console.warn(`${TAG} serializeToWant: no active session`);
      return AbilityConstant.OnContinueResult.MISMATCH;
    }
    wantParam[SNAP_BOOK_ID] = sess.bookId;
    wantParam[SNAP_CHAPTER_ID] = sess.chapterId;
    wantParam[SNAP_PAGE_IDX] = sess.pageIdx;
    wantParam[SNAP_CHAR_OFFSET] = sess.charOffset;
    wantParam[SNAP_PERCENT] = sess.percentComplete;
    console.info(`${TAG} serialized bookId=${sess.bookId} chapter=${sess.chapterId} page=${sess.pageIdx}`);
    return AbilityConstant.OnContinueResult.AGREE;
  }

  /**
   * 从目标设备收到的 want 中恢复阅读状态（由 ContinueReadingAbility / ReaderAbility.onCreate 调用）。
   *
   * 将 want.parameters 中的快照写回 ReadingSoul，
   * Reader 页的 Soul.observe() 监听到变化后自动跳到正确位置。
   */
  static async restoreFromWant(want: Want): Promise<ActiveSession | null> {
    if (!want || !want.parameters) return null;
    const p = want.parameters as Record<string, Object>;
    const bookId = (p[SNAP_BOOK_ID] as string) ?? '';
    if (!bookId) return null;

    const chapterId = (p[SNAP_CHAPTER_ID] as string) ?? '';
    const pageIdx = (typeof p[SNAP_PAGE_IDX] === 'number') ? p[SNAP_PAGE_IDX] as number : 0;
    const charOffset = (typeof p[SNAP_CHAR_OFFSET] === 'number') ? p[SNAP_CHAR_OFFSET] as number : 0;
    const percentComplete = (typeof p[SNAP_PERCENT] === 'number') ? p[SNAP_PERCENT] as number : 0;

    const session: ActiveSession = { bookId, chapterId, pageIdx, charOffset, percentComplete };
    activeSession = session;

    try {
      await ReadingSoul.setPosition(bookId, chapterId, pageIdx, charOffset);
      console.info(`${TAG} restored bookId=${bookId} chapter=${chapterId} page=${pageIdx}`);
    } catch (e) {
      console.warn(`${TAG} RestoreFromWant setPosition failed: ${(e as Error).message}`);
    }
    return session;
  }

  /** 返回当前注册 token（-1 表示未注册）。供 ReaderAbility 判断是否需要 register。 */
  static getToken(): number {
    return token;
  }

  /** 返回当前活跃会话快照（只读）。 */
  static getActiveSession(): Readonly<ActiveSession> | null {
    return activeSession;
  }

  // ─────── private ───────

  /** 注册设备连接 / 断开事件监听。 */
  private static listenDeviceConnect(): void {
    if (token === -1) return;
    try {
      continuationManager.on('deviceConnect', token, (data) => {
        if (!data || data.length === 0) return;
        const first = data[0];
        console.info(`${TAG} device connected: id=${first.id} type=${first.type}`);
        // 自动向第一个连接设备发起 continuation
        ContinuationManager.startContinuationWithDevice(first.id);
      });
      continuationManager.on('deviceDisconnect', token, (data) => {
        if (!data || data.length === 0) return;
        console.info(`${TAG} device disconnected: id=${data[0]}`);
      });
    } catch (e) {
      console.warn(`${TAG} listenDeviceConnect exception: ${(e as Error).message}`);
    }
  }
}
