// L1 - Foundation - Surface
// Detects the current device surface kind from deviceInfo + display breakpoint.

import deviceInfo from '@ohos.deviceInfo';
import { SurfaceKind } from './SurfaceKind';

type SurfaceObserver = (kind: SurfaceKind) => void;

/** Breakpoint dp thresholds matching the theme/Breakpoints contract. */
const TABLET_BP = 840;
const TV_BP = 1920;

function classifyByDeviceType(deviceType: string, screenWidthDp: number): SurfaceKind {
  const t = deviceType.toLowerCase();
  if (t.includes('watch')) return SurfaceKind.Watch;
  if (t.includes('car'))   return SurfaceKind.Car;
  if (t.includes('tv') || screenWidthDp >= TV_BP) return SurfaceKind.Tv;
  if (t.includes('fold'))  return SurfaceKind.Foldable;
  if (t.includes('tablet') || screenWidthDp >= TABLET_BP) return SurfaceKind.Tablet;
  return SurfaceKind.Phone;
}

/**
 * Reads device class from @ohos.deviceInfo and current display width.
 * Observers are notified when the active surface changes (e.g. fold/unfold).
 * @since W1
 */
export class SurfaceContext {
  private static cachedKind: SurfaceKind | null = null;
  private static readonly observers: SurfaceObserver[] = [];

  /**
   * Returns the current surface kind. Result is memoized until notifyChange().
   * @since W1
   */
  static current(): SurfaceKind {
    if (SurfaceContext.cachedKind) return SurfaceContext.cachedKind;

    let rawType = 'default';
    try {
      rawType = deviceInfo.deviceType ?? 'default';
    } catch (_e) {
      // deviceInfo unavailable in unit test environments.
    }

    // screenWidthDp not directly available without UIContext in L1; use 0 as default.
    // Callers with UIContext should call notifyWidthChange() after mount.
    const kind = classifyByDeviceType(rawType, 0);
    SurfaceContext.cachedKind = kind;
    return kind;
  }

  /**
   * Call when display width changes (e.g. window resize, fold event).
   * Re-classifies the surface and notifies observers if it changed.
   * @since W1
   */
  static notifyWidthChange(screenWidthDp: number): void {
    let rawType = 'default';
    try {
      rawType = deviceInfo.deviceType ?? 'default';
    } catch (_e) { /* ignored */ }

    const newKind = classifyByDeviceType(rawType, screenWidthDp);
    if (newKind !== SurfaceContext.cachedKind) {
      SurfaceContext.cachedKind = newKind;
      for (const cb of SurfaceContext.observers) {
        try { cb(newKind); } catch (_e) { /* swallow */ }
      }
    }
  }

  /**
   * Subscribe to surface kind changes. Returns an unsubscribe function.
   * @since W1
   */
  static observe(cb: SurfaceObserver): () => void {
    SurfaceContext.observers.push(cb);
    // Emit current value immediately.
    try { cb(SurfaceContext.current()); } catch (_e) { /* swallow */ }
    return () => {
      const idx = SurfaceContext.observers.indexOf(cb);
      if (idx >= 0) SurfaceContext.observers.splice(idx, 1);
    };
  }
}
