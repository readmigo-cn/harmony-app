/**
 * Syncfusion 类型定义。
 *
 * 同步分两类通道：
 *  - Realtime（实时）：毫秒级跨设备 LWW；仅存最新值；用 SoulEngine 底层
 *  - Persistent（持久）：秒级 + 离线兜底；collection CRUD；用 SyncQueue 底层（P0-B.2）
 *
 * 调用方通过 SyncCoordinator 按 domain 名称访问，不关心底层 channel。
 */

/** 同步通道类型。 */
export type ChannelKind = 'realtime' | 'persistent';

/** Realtime 通道域键：每个域单值，最新者胜。 */
export type RealtimeDomainKey = 'position' | 'selection' | 'device';

/** Persistent 通道域键：每个域是 collection，独立 CRUD。 */
export type PersistentDomainKey =
  | 'progress'
  | 'bookmark'
  | 'highlight'
  | 'bookshelf'
  | 'history'
  | 'session';

/** 全部域键联合。 */
export type DomainKey = RealtimeDomainKey | PersistentDomainKey;

/** 编译期域 → channel 静态映射；SyncCoordinator 内部路由用。 */
export const DOMAIN_CHANNEL: Readonly<Record<DomainKey, ChannelKind>> = {
  position: 'realtime',
  selection: 'realtime',
  device: 'realtime',
  progress: 'persistent',
  bookmark: 'persistent',
  highlight: 'persistent',
  bookshelf: 'persistent',
  history: 'persistent',
  session: 'persistent',
};

// ---------- Realtime payload shapes（强类型） ----------

export interface PositionPayload {
  bookId: string;
  chapterId: string;
  pageIdx: number;
  charOffset: number;
}

export interface SelectionPayload {
  sessionId: string;
  chapterId: string;
  startCharOffset: number;
  endCharOffset: number;
}

export interface DevicePayload {
  deviceId: string;
  deviceName: string;
  platform: string;
  lastActiveMs: number;
}

/** Realtime domain → payload type 映射，供泛型约束用。 */
export interface RealtimePayloads {
  position: PositionPayload;
  selection: SelectionPayload;
  device: DevicePayload;
}

// ---------- Persistent op（B.2 详细化） ----------

/** Persistent 通道写操作的统一抽象（CRUD）。 */
export interface PersistentOp<TKey extends PersistentDomainKey, TPayload> {
  domain: TKey;
  kind: 'upsert' | 'delete';
  id: string;
  payload?: TPayload;
  /** 本地写入时间（ms，单调递增） */
  localTs: number;
}
