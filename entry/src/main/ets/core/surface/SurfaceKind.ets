// L1 - Foundation - Surface
// Device surface classification and per-kind capability declarations.

/**
 * All supported HarmonyOS device surface classes.
 * @since W1
 */
export enum SurfaceKind {
  Phone     = 'phone',
  Tablet    = 'tablet',
  Foldable  = 'foldable',
  Watch     = 'watch',
  Car       = 'car',
  Tv        = 'tv',
}

/**
 * Static capability descriptor for each surface kind.
 * Used by SurfaceRegistry to filter available renderers.
 * @since W1
 */
export interface SurfaceCapabilities {
  /** Device supports direct touch interaction. */
  readonly touchOk: boolean;
  /** Device supports voice input / TTS responses. */
  readonly voiceOk: boolean;
  /** Longest display dimension in dp (portrait height / landscape width). */
  readonly biggestScreenDim: number;
  /** Device has a hardware keyboard or D-pad navigation. */
  readonly hasHardwareKeys: boolean;
  /** Device can participate in HarmonyOS Continuation hand-off. */
  readonly supportsContinuation: boolean;
}

/**
 * Capability table for all known surface kinds.
 * Values are conservative defaults; runtime detection may refine them.
 * @since W1
 */
export const SURFACE_CAPABILITIES: Record<SurfaceKind, SurfaceCapabilities> = {
  [SurfaceKind.Phone]: {
    touchOk: true,
    voiceOk: true,
    biggestScreenDim: 844,
    hasHardwareKeys: false,
    supportsContinuation: true,
  },
  [SurfaceKind.Tablet]: {
    touchOk: true,
    voiceOk: true,
    biggestScreenDim: 1366,
    hasHardwareKeys: false,
    supportsContinuation: true,
  },
  [SurfaceKind.Foldable]: {
    touchOk: true,
    voiceOk: true,
    biggestScreenDim: 1080,
    hasHardwareKeys: false,
    supportsContinuation: true,
  },
  [SurfaceKind.Watch]: {
    touchOk: true,
    voiceOk: true,
    biggestScreenDim: 466,
    hasHardwareKeys: false,
    supportsContinuation: false,
  },
  [SurfaceKind.Car]: {
    touchOk: true,
    voiceOk: true,
    biggestScreenDim: 1920,
    hasHardwareKeys: true,
    supportsContinuation: false,
  },
  [SurfaceKind.Tv]: {
    touchOk: false,
    voiceOk: true,
    biggestScreenDim: 3840,
    hasHardwareKeys: true,
    supportsContinuation: false,
  },
};
