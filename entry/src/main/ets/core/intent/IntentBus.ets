// L1 - Foundation - Intent
// Singleton publish/subscribe bus for typed intents.
// Implements: idempotency dedup (1000ms), source-stamping from SurfaceContext,
// Object.freeze at publish, backpressure queue (MAX=32 FIFO drop-oldest).

import type { AnyIntent, IntentKind } from './Intent';
import { SurfaceContext } from '../surface/SurfaceContext';

type HandlerFn = (intent: AnyIntent) => Promise<void>;
/** @since W1 */
export type Unsubscribe = () => void;

/** Debug-only observer hooks — stripped in release builds. */
type PublishObserver = (intent: AnyIntent) => void;
type DropObserver = (intent: AnyIntent, reason: 'idempotent' | 'queue_overflow') => void;

const MAX_QUEUE = 32;
/** Idempotency dedup window in milliseconds. */
const IDEM_WINDOW_MS = 1000;

interface QueueEntry {
  intent: AnyIntent;
}

/**
 * Central intent bus. L4 renderers publish; L3 ViewModels subscribe.
 * - source field is stamped from SurfaceContext at publish time.
 * - Intents are Object.freeze'd before dispatch.
 * - Idempotency: same idempotencyKey within 1000ms is dropped.
 * - No-subscriber queue: FIFO, max 32 per kind, drop-oldest on overflow.
 * @since W1
 */
export class IntentBus {
  private static instance: IntentBus | null = null;

  private readonly handlers: Map<string, HandlerFn[]> = new Map();
  private readonly queues: Map<string, QueueEntry[]> = new Map();
  /** idempotencyKey → expiry tsMs */
  private readonly dedup: Map<string, number> = new Map();

  // Debug-only hooks (no-op in release).
  private publishObservers: PublishObserver[] = [];
  private dropObservers: DropObserver[] = [];

  private constructor() {}

  /** @since W1 */
  static getInstance(): IntentBus {
    if (!IntentBus.instance) {
      IntentBus.instance = new IntentBus();
    }
    return IntentBus.instance;
  }

  /**
   * Publish an intent. Stamps source from SurfaceContext, freezes the intent,
   * checks idempotency window, then routes to handler or queues.
   * @since W1
   */
  async publish<I extends AnyIntent>(intent: I): Promise<void> {
    // Stamp source from SurfaceContext (renderers must not set it themselves).
    const stamped = Object.freeze({
      ...intent,
      source: SurfaceContext.current(),
      tsMs: intent.tsMs || Date.now(),
    }) as I;

    // Idempotency check.
    const now = Date.now();
    const expiry = this.dedup.get(stamped.idempotencyKey);
    if (expiry !== undefined && now < expiry) {
      this.notifyDrop(stamped, 'idempotent');
      return;
    }
    this.dedup.set(stamped.idempotencyKey, now + IDEM_WINDOW_MS);
    // Prune stale dedup entries periodically to avoid unbounded growth.
    if (this.dedup.size > 512) {
      for (const [k, exp] of this.dedup) {
        if (exp < now) this.dedup.delete(k);
      }
    }

    this.notifyPublish(stamped);

    const { kind } = stamped;
    const list = this.handlers.get(kind);
    if (list && list.length > 0) {
      // Drain any queued intents for this kind first.
      const queued = this.queues.get(kind);
      if (queued && queued.length > 0) {
        this.queues.set(kind, []);
        for (const entry of queued) {
          await IntentBus.invokeAll(list, entry.intent);
        }
      }
      await IntentBus.invokeAll(list, stamped);
    } else {
      // No handler — queue with backpressure.
      let q = this.queues.get(kind);
      if (!q) {
        q = [];
        this.queues.set(kind, q);
      }
      if (q.length >= MAX_QUEUE) {
        const dropped = q.shift()!;
        this.notifyDrop(dropped.intent as AnyIntent, 'queue_overflow');
        console.warn(`[IntentBus] queue overflow for kind="${kind}", dropping oldest`);
      }
      q.push({ intent: stamped });
    }
  }

  /**
   * Subscribe a handler for a specific intent kind.
   * Immediately replays any queued intents for this kind.
   * Returns an unsubscribe function — call from ViewModel.onDestroy().
   * @since W1
   */
  subscribe<I extends AnyIntent>(
    kind: IntentKind,
    handler: (intent: I) => Promise<void>,
  ): Unsubscribe {
    let list = this.handlers.get(kind);
    if (!list) {
      list = [];
      this.handlers.set(kind, list);
    }
    list.push(handler as HandlerFn);

    // Drain queue at subscribe time.
    const queued = this.queues.get(kind);
    if (queued && queued.length > 0) {
      this.queues.set(kind, []);
      const snapshot = queued.slice();
      Promise.resolve().then(async () => {
        const current = this.handlers.get(kind) ?? [];
        for (const entry of snapshot) {
          await IntentBus.invokeAll(current, entry.intent);
        }
      });
    }

    return () => {
      const arr = this.handlers.get(kind);
      if (!arr) return;
      const idx = arr.indexOf(handler as HandlerFn);
      if (idx >= 0) arr.splice(idx, 1);
    };
  }

  // ── Debug-only observability hooks ───────────────────────────────

  /**
   * Register a post-dedup publish observer (debug only; no-op in release).
   * @since W1
   */
  onPublish(observer: PublishObserver): Unsubscribe {
    this.publishObservers.push(observer);
    return () => {
      const idx = this.publishObservers.indexOf(observer);
      if (idx >= 0) this.publishObservers.splice(idx, 1);
    };
  }

  /**
   * Register a drop observer for idempotent dedup or queue overflow (debug only).
   * @since W1
   */
  onDrop(observer: DropObserver): Unsubscribe {
    this.dropObservers.push(observer);
    return () => {
      const idx = this.dropObservers.indexOf(observer);
      if (idx >= 0) this.dropObservers.splice(idx, 1);
    };
  }

  // ── internals ────────────────────────────────────────────────────

  private notifyPublish(intent: AnyIntent): void {
    for (const obs of this.publishObservers) {
      try { obs(intent); } catch (_e) { /* swallow */ }
    }
  }

  private notifyDrop(intent: AnyIntent, reason: 'idempotent' | 'queue_overflow'): void {
    for (const obs of this.dropObservers) {
      try { obs(intent, reason); } catch (_e) { /* swallow */ }
    }
  }

  private static async invokeAll(
    handlers: HandlerFn[],
    intent: AnyIntent,
  ): Promise<void> {
    for (const h of handlers) {
      try {
        await h(intent);
      } catch (e) {
        console.error(`[IntentBus] handler error for kind="${intent.kind}":`, e);
      }
    }
  }
}
