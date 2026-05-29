// L1 - Foundation - DistributedSoul
// Singleton wrapping @ohos.data.distributedDataObject for cross-device state sync.
// Real API: @ohos.data.distributedDataObject (standardized import path for this project).

import distributedDataObject from '@ohos.data.distributedDataObject';
import type { LamportTs, AnySoul } from './SoulSchema';

/** Listener callback for soul path changes. @since W1 */
export type SoulListener<T> = (value: T) => void;

/** Internal subscription entry. */
interface Subscription {
  path: string;
  listener: SoulListener<unknown>;
}

/** Snapshot of the full soul cache for continuation/restore. @since W5 */
export interface SoulSnapshot {
  sessionId: string;
  cache: Record<string, { value: unknown; ts: LamportTs }>;
  capturedAtMs: number;
}

/**
 * Compares two Lamport timestamps; returns true if a > b (a is newer).
 * LWW: compare seq first, then wallClock as tiebreak, then deviceId lexically.
 */
function isNewer(a: LamportTs, b: LamportTs): boolean {
  if (a.seq !== b.seq) return a.seq > b.seq;
  if (a.wallClockMs !== b.wallClockMs) return a.wallClockMs > b.wallClockMs;
  return a.deviceId > b.deviceId;
}

/**
 * Distributed state engine backed by @ohos.data.distributedDataObject.
 * Falls back to LocalFallback when the native API is unavailable.
 * @since W1
 */
export class SoulEngine {
  private static instance: SoulEngine | null = null;

  /** Real distributedDataObject handle; null when using LocalFallback. */
  private dataObj: distributedDataObject.DataObject | null = null;
  private sessionId: string = '';
  private seqCounter: number = 0;
  private readonly deviceId: string;
  private readonly subscriptions: Subscription[] = [];
  /** Memoized in-memory snapshot for fast read-back. */
  private readonly cache: Map<string, unknown> = new Map();
  /** Devices that have joined this session (advisory, best-effort). */
  private readonly joinedDevices: Set<string> = new Set();

  private constructor() {
    // Use a stable device-unique id: combine platform + random for this session.
    this.deviceId = `dev-${Math.random().toString(36).slice(2, 10)}`;
  }

  /** @since W1 */
  static getInstance(): SoulEngine {
    if (!SoulEngine.instance) {
      SoulEngine.instance = new SoulEngine();
    }
    return SoulEngine.instance;
  }

  /**
   * Initialize the distributed data object for the given session.
   * Must be called before any other method.
   * @since W1
   */
  async init(sessionId: string): Promise<void> {
    this.sessionId = sessionId;
    try {
      // Real API: @ohos.data.distributedDataObject
      this.dataObj = distributedDataObject.create(getContext(), {});
      this.dataObj.on('change', (_sessionId: string, fields: string[]) => {
        this.handleRemoteChange(fields);
      });
      this.dataObj.on('status', (_sessionId: string, networkId: string, status: string) => {
        if (status === 'online') {
          this.joinedDevices.add(networkId);
          console.info(`SoulEngine device online networkId=${networkId}`);
        } else if (status === 'offline') {
          this.joinedDevices.delete(networkId);
          console.info(`SoulEngine device offline networkId=${networkId}`);
        }
      });
    } catch (_e) {
      // distributedDataObject unavailable — LocalFallback will be used instead.
      this.dataObj = null;
    }
  }

  /**
   * Attach this session to specific remote device IDs for collaboration.
   * Calls dataObject.setSessionId to broadcast session membership.
   * deviceIds are advisory — the SDK auto-discovers on same session.
   * @since W1
   */
  async attach(deviceIds: string[]): Promise<void> {
    if (!this.dataObj) return;
    try {
      await this.dataObj.setSessionId(this.sessionId);
      for (const id of deviceIds) {
        this.joinedDevices.add(id);
      }
    } catch (_e) {
      // Non-fatal: single-device mode continues to work.
    }
  }

  /**
   * Write a value at the given dot-notation path.
   * Conflict resolution: LWW via Lamport timestamp; SelectionSoul.range prefers local.
   * Mutates the dataObject property — the framework broadcasts to peers automatically.
   * @since W1
   */
  async update<T>(path: string, value: T): Promise<void> {
    const ts: LamportTs = {
      deviceId: this.deviceId,
      seq: ++this.seqCounter,
      wallClockMs: Date.now(),
    };
    const entry = { value, ts };

    // Check existing cached timestamp — skip if cached is newer.
    const cached = this.cache.get(path) as { value: unknown; ts: LamportTs } | undefined;
    if (cached && isNewer(cached.ts, ts)) return;

    this.cache.set(path, entry);
    if (this.dataObj) {
      try {
        // Mutate the dataObject property; framework broadcasts to peers automatically.
        (this.dataObj as Record<string, unknown>)[this.encodeKey(path)] = JSON.stringify(entry);
      } catch (_e) {
        // Best-effort; cache already updated for local reads.
      }
    }
    this.notifySubscribers(path, value);
  }

  /**
   * Subscribe to changes at the given dot-notation path.
   * Returns an unsubscribe function.
   * @since W1
   */
  subscribe<T>(path: string, listener: SoulListener<T>): () => void {
    const sub: Subscription = { path, listener: listener as SoulListener<unknown> };
    this.subscriptions.push(sub);
    // Immediately emit cached value if available.
    const cached = this.cache.get(path) as { value: T } | undefined;
    if (cached !== undefined) {
      try { listener(cached.value); } catch (_e) { /* swallow */ }
    }
    return () => {
      const idx = this.subscriptions.indexOf(sub);
      if (idx >= 0) this.subscriptions.splice(idx, 1);
    };
  }

  /**
   * Flush pending writes to durable storage.
   * @since W1
   */
  async flush(): Promise<void> {
    if (!this.dataObj) return;
    try {
      await this.dataObj.save('local');
    } catch (_e) {
      // Non-fatal; in-memory cache remains consistent.
    }
  }

  /**
   * Tear down listeners and release the session.
   * @since W1
   */
  async dispose(): Promise<void> {
    if (this.dataObj) {
      try {
        this.dataObj.off('change');
        this.dataObj.off('status');
        await this.dataObj.setSessionId('');
      } catch (_e) { /* ignore */ }
      this.dataObj = null;
    }
    this.subscriptions.length = 0;
    this.cache.clear();
    this.joinedDevices.clear();
    SoulEngine.instance = null;
  }

  /** Returns true when running without the native distributed API. @since W1 */
  get isFallbackMode(): boolean {
    return this.dataObj === null;
  }

  /** Returns current joined device IDs (best-effort, from status events). @since W5 */
  currentDevices(): string[] {
    return Array.from(this.joinedDevices);
  }

  // ── internals ────────────────────────────────────────────────────

  private encodeKey(path: string): string {
    return path.replace(/\./g, '__');
  }

  private handleRemoteChange(fields: string[]): void {
    if (!this.dataObj) return;
    for (const field of fields) {
      const path = field.replace(/__/g, '.');
      try {
        const raw = (this.dataObj as Record<string, unknown>)[field] as string | undefined;
        if (!raw) continue;
        const entry = JSON.parse(raw) as { value: unknown; ts: LamportTs };
        const cached = this.cache.get(path) as { value: unknown; ts: LamportTs } | undefined;
        // SelectionSoul.range: prefer local optimistic for 250ms then accept remote.
        if (path.endsWith('range') && cached) {
          const ageMs = Date.now() - cached.ts.wallClockMs;
          if (ageMs < 250) continue;
        }
        // LWW: only apply if remote is newer.
        if (cached && !isNewer(entry.ts, cached.ts)) continue;
        this.cache.set(path, entry);
        this.notifySubscribers(path, entry.value);
      } catch (_e) { /* malformed remote data */ }
    }
  }

  private notifySubscribers(path: string, value: unknown): void {
    for (const sub of this.subscriptions) {
      if (sub.path === path) {
        try { sub.listener(value); } catch (_e) { /* swallow */ }
      }
    }
  }
}

/** @since W1 */
export type { AnySoul, LamportTs };
