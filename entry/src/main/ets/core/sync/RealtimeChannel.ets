import { SoulEngine } from '../distributed-soul/SoulEngine';
import { LocalFallback } from '../distributed-soul/LocalFallback';
import type { RealtimeDomainKey, RealtimePayloads } from './SyncDomain';

/**
 * 实时同步通道（毫秒级跨设备 LWW）。
 *
 * 内部封装 SoulEngine + LocalFallback：
 *  - distributed 模式：SoulEngine 通过 @ohos.data.distributedDataObject 广播
 *  - fallback 模式：LocalFallback 本地内存 + 持久化
 *
 * 复合 payload（如 position 4 字段）拆解为 4 个 sub-path，每个独立 LWW；
 * observe 时所有字段到齐才 emit，避免半状态触发 UI 闪烁。
 *
 * 不直接暴露给业务调用方；走 SyncCoordinator.realtime.<domain>。
 */
export class RealtimeChannel {
  private static readonly engine = SoulEngine.getInstance();

  // ---------- public API ----------

  static async set<K extends RealtimeDomainKey>(
    domain: K, value: RealtimePayloads[K],
  ): Promise<void> {
    const engine = RealtimeChannel.engine;
    const fields = RealtimeChannel.fieldNamesOf(domain);
    const obj = value as unknown as Record<string, unknown>;
    if (!engine.isFallbackMode) {
      for (let i = 0; i < fields.length; i++) {
        const f = fields[i];
        await engine.update(RealtimeChannel.pathFor(domain, f), obj[f]);
      }
    } else {
      for (let i = 0; i < fields.length; i++) {
        const f = fields[i];
        await LocalFallback.set(RealtimeChannel.pathFor(domain, f), obj[f]);
      }
    }
  }

  static async get<K extends RealtimeDomainKey>(
    domain: K,
  ): Promise<RealtimePayloads[K] | null> {
    const engine = RealtimeChannel.engine;
    const fields = RealtimeChannel.fieldNamesOf(domain);
    const out: Record<string, unknown> = {};
    if (!engine.isFallbackMode) {
      for (let i = 0; i < fields.length; i++) {
        const f = fields[i];
        const v = RealtimeChannel.readOnce(engine, RealtimeChannel.pathFor(domain, f));
        if (v !== undefined) out[f] = v;
      }
    } else {
      for (let i = 0; i < fields.length; i++) {
        const f = fields[i];
        const v = await LocalFallback.get<unknown>(
          RealtimeChannel.pathFor(domain, f), undefined as unknown,
        );
        if (v !== undefined) out[f] = v;
      }
    }
    return RealtimeChannel.isComplete(domain, out)
      ? (out as unknown as RealtimePayloads[K])
      : null;
  }

  static observe<K extends RealtimeDomainKey>(
    domain: K, listener: (value: RealtimePayloads[K]) => void,
  ): () => void {
    const engine = RealtimeChannel.engine;
    const fields = RealtimeChannel.fieldNamesOf(domain);
    const state: Record<string, unknown> = {};
    const emit = (): void => {
      if (RealtimeChannel.isComplete(domain, state)) {
        try {
          // 拷贝避免外部修改污染内部 state
          const copy: Record<string, unknown> = {};
          for (let i = 0; i < fields.length; i++) copy[fields[i]] = state[fields[i]];
          listener(copy as unknown as RealtimePayloads[K]);
        } catch (_e) { /* swallow */ }
      }
    };
    const unsubs: Array<() => void> = [];
    for (let i = 0; i < fields.length; i++) {
      const f = fields[i];
      const path = RealtimeChannel.pathFor(domain, f);
      if (!engine.isFallbackMode) {
        unsubs.push(engine.subscribe<unknown>(path, (v) => { state[f] = v; emit(); }));
      } else {
        unsubs.push(LocalFallback.subscribe<unknown>(path, (v) => { state[f] = v; emit(); }));
      }
    }
    return () => {
      for (let i = 0; i < unsubs.length; i++) unsubs[i]();
    };
  }

  // ---------- internals ----------

  private static pathFor(domain: RealtimeDomainKey, field: string): string {
    return `${domain}.${field}`;
  }

  /**
   * 同步 read：subscribe 立即回调当前 cached 值，捕获后立刻 unsubscribe。
   * 避免 TDZ：先声明 captured，再调 subscribe，cb 中只写 captured，
   * subscribe 返回后立刻 unsub —— 不在 cb 内调用 unsub。
   */
  private static readOnce(engine: SoulEngine, path: string): unknown {
    let captured: unknown = undefined;
    let received: boolean = false;
    const unsub = engine.subscribe<unknown>(path, (v) => {
      if (!received) { received = true; captured = v; }
    });
    unsub();
    return received ? captured : undefined;
  }

  private static fieldNamesOf(domain: RealtimeDomainKey): string[] {
    if (domain === 'position') return ['bookId', 'chapterId', 'pageIdx', 'charOffset'];
    if (domain === 'selection') return ['sessionId', 'chapterId', 'startCharOffset', 'endCharOffset'];
    return ['deviceId', 'deviceName', 'platform', 'lastActiveMs'];
  }

  private static isComplete(domain: RealtimeDomainKey, state: Record<string, unknown>): boolean {
    const fields = RealtimeChannel.fieldNamesOf(domain);
    for (let i = 0; i < fields.length; i++) {
      if (state[fields[i]] === undefined) return false;
    }
    return true;
  }
}
