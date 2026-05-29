/**
 * Syncfusion barrel：统一对外暴露 Coordinator + 类型。
 *
 * 调用方：
 *   import { SyncCoordinator } from '../../core/sync';
 *   import type { PositionPayload, PersistentConflict } from '../../core/sync';
 */

export { SyncCoordinator } from './SyncCoordinator';
export { RealtimeChannel } from './RealtimeChannel';
export { PersistentChannel } from './PersistentChannel';
export { SyncQueue, NetMonitor } from './SyncQueue';
export {
  DOMAIN_CHANNEL,
} from './SyncDomain';
export type {
  ChannelKind,
  RealtimeDomainKey,
  PersistentDomainKey,
  DomainKey,
  PositionPayload,
  SelectionPayload,
  DevicePayload,
  RealtimePayloads,
  PersistentOp,
} from './SyncDomain';
export type {
  DomainAdapter,
  PersistentConflict,
  ConflictListener,
} from './PersistentChannel';
