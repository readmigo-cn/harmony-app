/**
 * DistributedBookshelfStore.ets — W13-C1 跨端书架同步
 *
 * 职责：
 *   - 用 @ohos.data.distributedDataObject 在同账号设备间同步书架（want-to-read /
 *     reading / finished + isFavorite）
 *   - 同步范围：单一 ShelfState 对象，包含全部 BookshelfItem 数组
 *   - 冲突解决：addedAt timestamp 比较（最新写入胜，per-item LWW）
 *   - 持久化最近一次成功同步时间到 Preferences（startupGuard）
 *
 * 与 BookshelfItemSyncer (W10) 的关系：
 *   - W10 BookshelfItemSyncer 走 server-cn /api/v1/sync —— 跨账号 / 单设备情形
 *   - 本类走 distributedDataObject —— 同账号同局域网多端实时镜像（< 1s 延迟）
 *   - 两者并存：本地修改后同时 enqueue 到 SyncEngine + setShelfState 到分布式 object
 *
 * 服务端协议：
 *   - distributedDataObject 是端到端：对端通过 sessionId 加入同一会话即可镜像
 *   - sessionId = base64(userId)：同账号设备生成相同 sessionId 自动配对
 *   - 不需要走 server-cn
 *
 * 占位策略：
 *   - 模拟器：不连接真实分布式 object，只在内存维护 state；订阅永不触发
 *   - 真机：TODO 标注，由 W14 真机阶段接入 distributedDataObject 真实 API
 *
 * 真实 API 参考：
 *   import distributedObject from '@ohos.data.distributedDataObject';
 *   const dataObj = distributedObject.createDistributedObject(initialState);
 *   dataObj.setSessionId(sessionId);
 *   dataObj.on('change', cb);
 */

import { PreferencesManager } from '../../../../core/persistence/PreferencesManager';
import { BookStatus } from '../../../../model/Book';

const TAG = 'DistributedBookshelfStore';

/** 分布式同步的 shelf item（精简版，去掉 server-only 字段） */
export interface DistributedShelfItem {
  bookId: string;
  status: BookStatus;
  isFavorite: boolean;
  /** ISO 8601；冲突解决用 */
  addedAt: string;
  /** 最近一次本地修改时间；细粒度冲突解决用 */
  updatedAt: string;
  /** 来源设备 ID（埋点 / 调试） */
  sourceDeviceId: string;
}

/** 分布式 object 顶层结构。 */
export interface ShelfState {
  /** 拥有者 user id */
  userId: string;
  /** 全部 item，map 序列化 */
  items: DistributedShelfItem[];
  /** 服务端最后同步时刻（不等于 P2P sync 时刻） */
  serverSyncedAt: string;
  /** 协议版本，用于跨版本兼容 */
  schemaVersion: number;
}

const SCHEMA_VERSION = 1;
const PREF_KEY_LAST_P2P_SYNC = 'distributed_shelf_last_p2p_sync_at';

type ChangeCallback = (state: ShelfState, sourceDeviceId: string) => void;

/**
 * Base64 简易实现（HarmonyOS @ohos.util.Base64Helper 也可，避免额外 import 这里手写）。
 * sessionId 长度限制 ≤ 64，中文 userId 走 base64 后通常 < 50。
 */
function base64Encode(s: string): string {
  // ArkTS：String → utf-8 bytes → base64
  const utf8: number[] = [];
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x80) {
      utf8.push(c);
    } else if (c < 0x800) {
      utf8.push(0xc0 | (c >> 6));
      utf8.push(0x80 | (c & 0x3f));
    } else {
      utf8.push(0xe0 | (c >> 12));
      utf8.push(0x80 | ((c >> 6) & 0x3f));
      utf8.push(0x80 | (c & 0x3f));
    }
  }
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let out = '';
  for (let i = 0; i < utf8.length; i += 3) {
    const b1 = utf8[i];
    const b2 = i + 1 < utf8.length ? utf8[i + 1] : 0;
    const b3 = i + 2 < utf8.length ? utf8[i + 2] : 0;
    const t = (b1 << 16) | (b2 << 8) | b3;
    out += chars[(t >> 18) & 0x3f];
    out += chars[(t >> 12) & 0x3f];
    out += i + 1 < utf8.length ? chars[(t >> 6) & 0x3f] : '=';
    out += i + 2 < utf8.length ? chars[t & 0x3f] : '=';
  }
  // sessionId 必须是字母数字 +／_，把 + / = 替换成 url-safe
  return out.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

class DistributedBookshelfStoreImpl {
  /** 真实 distributedObject 实例占位 */
  private dataObj: object | null = null;
  private sessionId: string = '';
  private currentUserId: string = '';
  /** 内存缓存的 state（mock 阶段是唯一来源） */
  private state: ShelfState = {
    userId: '',
    items: [],
    serverSyncedAt: '',
    schemaVersion: SCHEMA_VERSION,
  };
  private inited: boolean = false;
  private listeners: ChangeCallback[] = [];

  /**
   * 初始化分布式 shelf object。
   *
   * 调用时机：用户登录后 EntryAbility 触发；切账号需先 leaveSession() 再 init()。
   */
  async init(userId: string): Promise<void> {
    if (this.inited && this.currentUserId === userId) return;
    if (this.inited) {
      // 切账号：清旧 session
      await this.leaveSession();
    }
    this.currentUserId = userId;
    this.sessionId = base64Encode(`shelf-${userId}`);
    this.state = {
      userId,
      items: [],
      serverSyncedAt: '',
      schemaVersion: SCHEMA_VERSION,
    };

    try {
      // TODO(W14 真机)：替换为真实 API
      // const distributedObject = require('@ohos.data.distributedDataObject');
      // this.dataObj = distributedObject.createDistributedObject(this.state);
      // this.dataObj.setSessionId(this.sessionId);
      // this.dataObj.on('change', (sessionId, fields) => this.onRemoteChange(sessionId, fields));
      // this.dataObj.on('status', (sessionId, networkId, status) => {
      //   console.info(`${TAG} status sessionId=${sessionId} networkId=${networkId} status=${status}`);
      // });
      this.dataObj = null;
      this.inited = true;
      console.info(`${TAG} init userId=${userId} sessionId=${this.sessionId} (mock)`);
    } catch (e) {
      console.warn(`${TAG} init failed: ${(e as Error).message}`);
    }
  }

  /**
   * 写入新的书架快照（覆盖式）。
   *
   * 调用时机：本地 ReadingApi.addToShelf / updateShelfStatus 成功后
   */
  setShelfState(items: DistributedShelfItem[]): void {
    if (!this.inited) {
      console.warn(`${TAG} setShelfState before init`);
      return;
    }
    this.state.items = items;
    this.state.serverSyncedAt = new Date().toISOString();
    this.writeToObject();
    PreferencesManager.setString(PREF_KEY_LAST_P2P_SYNC, String(Date.now()));
  }

  /**
   * 增量更新单个 item（merge by bookId，addedAt 大者胜）。
   *
   * 用于 UI 收藏切换 / 状态切换的高频路径。
   */
  upsertItem(item: DistributedShelfItem): void {
    if (!this.inited) return;
    const idx = this.state.items.findIndex((x) => x.bookId === item.bookId);
    if (idx === -1) {
      this.state.items.push(item);
    } else {
      const existing = this.state.items[idx];
      const winner = this.resolveItemConflict(existing, item);
      this.state.items[idx] = winner;
    }
    this.writeToObject();
  }

  /** 软删除：从 items 移除（业务侧 = move to archived，但 distributed 层简化） */
  removeItem(bookId: string): void {
    if (!this.inited) return;
    this.state.items = this.state.items.filter((x) => x.bookId !== bookId);
    this.writeToObject();
  }

  /** 同步读：拿当前 state 内存快照（不触发网络）。 */
  getShelfState(): DistributedShelfItem[] {
    return this.state.items.slice();
  }

  /** 拿完整 state（含 metadata）。 */
  getFullState(): ShelfState {
    return {
      userId: this.state.userId,
      items: this.state.items.slice(),
      serverSyncedAt: this.state.serverSyncedAt,
      schemaVersion: this.state.schemaVersion,
    };
  }

  /** 持久化的最近一次 P2P sync 时间（ms）。 */
  async getLastP2PSyncedAt(): Promise<number> {
    const raw = await PreferencesManager.getString(PREF_KEY_LAST_P2P_SYNC, '');
    return raw ? parseInt(raw, 10) : 0;
  }

  /**
   * 监听其它设备发起的变更。
   * 模拟器：listener 永不触发（无真实事件源）
   * 真机：dataObj.on('change') → onRemoteChange → 分发给所有 listener
   */
  subscribeChange(cb: ChangeCallback): () => void {
    this.listeners.push(cb);
    return () => {
      const i = this.listeners.indexOf(cb);
      if (i >= 0) this.listeners.splice(i, 1);
    };
  }

  /**
   * 主动加入会话（默认 init 已加入；用于 reset / 切账号后重连）。
   * sessionId 为空时使用当前 userId 派生的 sessionId。
   */
  async joinSession(sessionId?: string): Promise<void> {
    if (!this.inited) {
      console.warn(`${TAG} joinSession before init`);
      return;
    }
    const sid = sessionId ?? this.sessionId;
    try {
      // TODO(W14 真机)：(this.dataObj as DistributedObject).setSessionId(sid);
      this.sessionId = sid;
      console.info(`${TAG} joinSession ${sid} (mock)`);
    } catch (e) {
      console.warn(`${TAG} joinSession failed: ${(e as Error).message}`);
    }
  }

  /** 离开会话：清空 sessionId，停止接收变更。 */
  async leaveSession(): Promise<void> {
    try {
      // TODO(W14 真机)：(this.dataObj as DistributedObject).setSessionId('')
      this.sessionId = '';
      this.listeners = [];
      this.inited = false;
      this.dataObj = null;
      console.info(`${TAG} leaveSession (mock)`);
    } catch (e) {
      console.warn(`${TAG} leaveSession failed: ${(e as Error).message}`);
    }
  }

  // ─────────── private ───────────

  /**
   * 把当前 state 写到 distributedDataObject。
   * 模拟器：no-op；真机：直接给 dataObj.items / serverSyncedAt 字段赋值即可（框架自动同步）
   */
  private writeToObject(): void {
    // TODO(W14 真机)：
    // if (this.dataObj) {
    //   (this.dataObj as { items: DistributedShelfItem[]; serverSyncedAt: string }).items = this.state.items;
    //   (this.dataObj as { items: DistributedShelfItem[]; serverSyncedAt: string }).serverSyncedAt = this.state.serverSyncedAt;
    // }
    console.info(`${TAG} writeToObject items=${this.state.items.length} (mock)`);
  }

  /**
   * 真机回调：对端设备改了 dataObj，框架推送 change 事件。
   *
   * @param _sessionId 同 this.sessionId（多 session 场景可作 router）
   * @param fields 变化的字段名列表 ['items', 'serverSyncedAt'] 等
   */
  // private onRemoteChange(_sessionId: string, fields: string[]): void {
  //   if (!this.dataObj) return;
  //   // 把 dataObj 的最新状态读回 state
  //   const next = this.dataObj as ShelfState;
  //   this.state.items = next.items ?? [];
  //   this.state.serverSyncedAt = next.serverSyncedAt ?? '';
  //   const sourceDeviceId = this.state.items.length > 0
  //     ? this.state.items[0].sourceDeviceId
  //     : '';
  //   for (const cb of this.listeners) {
  //     try { cb(this.getFullState(), sourceDeviceId); } catch (_) { /* ignore */ }
  //   }
  //   PreferencesManager.setString(PREF_KEY_LAST_P2P_SYNC, String(Date.now()));
  //   console.info(`${TAG} onRemoteChange fields=${fields.join(',')}`);
  // }

  /**
   * 单 item 冲突解决：
   *   1) updatedAt 大者胜（毫秒级精度比较）
   *   2) updatedAt 相同时，addedAt 大者胜（保留新加的）
   *   3) 全部相同时，保留 local（避免无效写）
   */
  private resolveItemConflict(
    local: DistributedShelfItem,
    incoming: DistributedShelfItem,
  ): DistributedShelfItem {
    const lu = Date.parse(local.updatedAt) || 0;
    const iu = Date.parse(incoming.updatedAt) || 0;
    if (iu > lu) return incoming;
    if (iu < lu) return local;
    const la = Date.parse(local.addedAt) || 0;
    const ia = Date.parse(incoming.addedAt) || 0;
    return ia > la ? incoming : local;
  }
}

/** 单例 */
export const DistributedBookshelfStore = new DistributedBookshelfStoreImpl();
