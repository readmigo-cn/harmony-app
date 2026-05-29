// L1 - Foundation - DistributedSoul
// Single-device fallback: proxies SoulEngine API to PreferencesManager when
// distributedDataObject is unavailable (simulator / single-device run).

import { PreferencesManager } from '../persistence/PreferencesManager';
import type { SoulListener } from './SoulEngine';

const PREFS_NS = 'soul';

/**
 * Preferences-backed soul storage with an identical subscription contract to SoulEngine.
 * Consumers should never instantiate directly — use ReadingSoul facade which
 * calls SoulEngine.getInstance() which auto-detects availability.
 * @since W1
 */
export class LocalFallback {
  private static readonly watchers: Map<string, SoulListener<unknown>[]> = new Map();

  /**
   * Read a value from preferences by path.
   * @since W1
   */
  static async get<T>(path: string, def: T): Promise<T> {
    const result = await PreferencesManager.getObject<T>(PREFS_NS + ':' + path, def);
    return result ?? def;
  }

  /**
   * Write a value to preferences and notify local subscribers.
   * @since W1
   */
  static async set<T>(path: string, value: T): Promise<void> {
    await PreferencesManager.setObject<T>(PREFS_NS + ':' + path, value);
    LocalFallback.notify(path, value);
  }

  /**
   * Subscribe to local path changes. Returns unsubscribe fn.
   * @since W1
   */
  static subscribe<T>(path: string, listener: SoulListener<T>): () => void {
    let list = LocalFallback.watchers.get(path);
    if (!list) {
      list = [];
      LocalFallback.watchers.set(path, list);
    }
    list.push(listener as SoulListener<unknown>);
    // Emit cached value immediately.
    LocalFallback.get<T>(path, undefined as unknown as T).then((v) => {
      if (v !== undefined) {
        try { listener(v); } catch (_e) { /* swallow */ }
      }
    });
    return () => {
      const arr = LocalFallback.watchers.get(path);
      if (!arr) return;
      const idx = arr.indexOf(listener as SoulListener<unknown>);
      if (idx >= 0) arr.splice(idx, 1);
    };
  }

  /** Flush all pending preferences writes. @since W1 */
  static async flush(): Promise<void> {
    // PreferencesManager debounces internally; calling setObject already schedules flush.
  }

  private static notify(path: string, value: unknown): void {
    const list = LocalFallback.watchers.get(path);
    if (!list) return;
    for (const cb of list) {
      try { cb(value); } catch (_e) { /* swallow */ }
    }
  }
}
