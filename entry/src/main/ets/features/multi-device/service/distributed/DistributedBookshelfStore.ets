/**
 * DistributedBookshelfStore.ets — W5 跨端书架同步（真实 distributedDataObject）
 *
 * 使用 SoulEngine（L1）作为唯一分布式通道，遵守 RULE-L1-Soul-exclusive：
 * L2 层不直接 import @ohos.data.distributedDataObject。
 *
 * 与 BookshelfItemSyncer (W10) 的关系：
 *   - W10 走 server-cn /api/v1/sync —— 跨账号 / 单设备情形
 *   - 本类走 SoulEngine —— 同账号同局域网多端实时镜像（< 1s 延迟）
 *   - 两者并存：本地修改后同时 enqueue 到 SyncEngine + 更新 ShelfState
 */

import { SoulEngine } from '../../../../core/distributed-soul/SoulEngine';
import { PreferencesManager } from '../../../../core/persistence/PreferencesManager';
import { BookStatus } from '../../../../model/Book';

const TAG = 'DistributedBookshelfStore';
const SOUL_PATH_SHELF = 'shelf.state';
const PREF_KEY_LAST_P2P_SYNC = 'distributed_shelf_last_p2p_sync_at';
const SCHEMA_VERSION = 1;

/** 分布式同步的 shelf item（精简版，去掉 server-only 字段） */
export interface DistributedShelfItem {
  bookId: string;
  status: BookStatus;
  isFavorite: boolean;
  addedAt: string;
  updatedAt: string;
  sourceDeviceId: string;
}

/** 分布式 object 顶层结构。 */
export interface ShelfState {
  userId: string;
  items: DistributedShelfItem[];
  serverSyncedAt: string;
  schemaVersion: number;
}

type ChangeCallback = (state: ShelfState, sourceDeviceId: string) => void;

function base64Encode(s: string): string {
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
  return out.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

class DistributedBookshelfStoreImpl {
  private sessionId: string = '';
  private currentUserId: string = '';
  private state: ShelfState = {
    userId: '',
    items: [],
    serverSyncedAt: '',
    schemaVersion: SCHEMA_VERSION,
  };
  private inited: boolean = false;
  private listeners: ChangeCallback[] = [];
  private unsub: (() => void) | null = null;

  async init(userId: string): Promise<void> {
    if (this.inited && this.currentUserId === userId) return;
    if (this.inited) {
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

    const engine = SoulEngine.getInstance();
    // SoulEngine.init uses the soul-level sessionId; shelf uses its own key within the soul.
    if (!engine.isFallbackMode) {
      // Subscribe to remote shelf state changes via SoulEngine.
      this.unsub = engine.subscribe<ShelfState>(SOUL_PATH_SHELF, (remote) => {
        if (!remote || typeof remote !== 'object') return;
        const typed = remote as ShelfState;
        this.state.items = typed.items ?? [];
        this.state.serverSyncedAt = typed.serverSyncedAt ?? '';
        const sourceDeviceId = this.state.items.length > 0
          ? this.state.items[0].sourceDeviceId
          : '';
        for (const cb of this.listeners) {
          try { cb(this.getFullState(), sourceDeviceId); } catch (_e) { /* ignore */ }
        }
        PreferencesManager.setString(PREF_KEY_LAST_P2P_SYNC, String(Date.now()));
      });
    }

    this.inited = true;
    console.info(`${TAG} init userId=${userId} sessionId=${this.sessionId}`);
  }

  setShelfState(items: DistributedShelfItem[]): void {
    if (!this.inited) {
      console.warn(`${TAG} setShelfState before init`);
      return;
    }
    this.state.items = items;
    this.state.serverSyncedAt = new Date().toISOString();
    this.writeToSoul();
    PreferencesManager.setString(PREF_KEY_LAST_P2P_SYNC, String(Date.now()));
  }

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
    this.writeToSoul();
  }

  removeItem(bookId: string): void {
    if (!this.inited) return;
    this.state.items = this.state.items.filter((x) => x.bookId !== bookId);
    this.writeToSoul();
  }

  getShelfState(): DistributedShelfItem[] {
    return this.state.items.slice();
  }

  getFullState(): ShelfState {
    return {
      userId: this.state.userId,
      items: this.state.items.slice(),
      serverSyncedAt: this.state.serverSyncedAt,
      schemaVersion: this.state.schemaVersion,
    };
  }

  async getLastP2PSyncedAt(): Promise<number> {
    const raw = await PreferencesManager.getString(PREF_KEY_LAST_P2P_SYNC, '');
    return raw ? parseInt(raw, 10) : 0;
  }

  subscribeChange(cb: ChangeCallback): () => void {
    this.listeners.push(cb);
    return () => {
      const i = this.listeners.indexOf(cb);
      if (i >= 0) this.listeners.splice(i, 1);
    };
  }

  async joinSession(sessionId?: string): Promise<void> {
    if (!this.inited) {
      console.warn(`${TAG} joinSession before init`);
      return;
    }
    this.sessionId = sessionId ?? this.sessionId;
    console.info(`${TAG} joinSession ${this.sessionId}`);
  }

  async leaveSession(): Promise<void> {
    if (this.unsub) {
      this.unsub();
      this.unsub = null;
    }
    this.sessionId = '';
    this.listeners = [];
    this.inited = false;
    console.info(`${TAG} leaveSession`);
  }

  // ─────────── private ───────────

  /** Write current state to SoulEngine so peers receive it automatically. */
  private writeToSoul(): void {
    const engine = SoulEngine.getInstance();
    if (!engine.isFallbackMode) {
      engine.update(SOUL_PATH_SHELF, this.getFullState()).catch((e: Error) => {
        console.warn(`${TAG} writeToSoul failed: ${e.message}`);
      });
    }
  }

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

export const DistributedBookshelfStore = new DistributedBookshelfStoreImpl();

// Re-export for convenience
export { BookStatus };
