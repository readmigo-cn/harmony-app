// L1 - Foundation - Surface
// Registry mapping (SurfaceKind, intentKind) → builder renderer reference.

import { SurfaceKind } from './SurfaceKind';
import type { IntentKind } from '../intent/Intent';

/**
 * A renderer is a function that receives feature state and returns an ArkUI builder.
 * The return type is intentionally `unknown` here because Builder references in ArkTS
 * cannot be generically typed at the registry level — callers cast at usage site.
 * @since W1
 */
export type RendererFn<S> = (state: S) => void;

interface RegistryKey {
  kind: SurfaceKind;
  intentKind: IntentKind;
}

function makeKey(kind: SurfaceKind, intentKind: IntentKind): string {
  return `${kind}::${intentKind}`;
}

/**
 * Associates surface kinds and intent kinds with concrete renderer functions.
 * Features register their renderers here during app boot.
 * @since W1
 */
export class SurfaceRegistry {
  private static readonly renderers: Map<string, RendererFn<unknown>> = new Map();

  /**
   * Register a renderer for a specific (surface kind, intent kind) pair.
   * Later registrations override earlier ones (last-write-wins).
   * @since W1
   */
  static register<S>(
    kind: SurfaceKind,
    intentKind: IntentKind,
    renderer: RendererFn<S>,
  ): void {
    SurfaceRegistry.renderers.set(
      makeKey(kind, intentKind),
      renderer as RendererFn<unknown>,
    );
  }

  /**
   * Resolve the renderer for a given surface + intent combination.
   * Falls back to Phone renderer if an exact match is not found.
   * Returns null if no renderer exists even for Phone.
   * @since W1
   */
  static resolve<S>(
    kind: SurfaceKind,
    intentKind: IntentKind,
  ): RendererFn<S> | null {
    const exact = SurfaceRegistry.renderers.get(makeKey(kind, intentKind));
    if (exact) return exact as RendererFn<S>;

    // Fallback: Phone is the baseline renderer.
    if (kind !== SurfaceKind.Phone) {
      const fallback = SurfaceRegistry.renderers.get(makeKey(SurfaceKind.Phone, intentKind));
      if (fallback) return fallback as RendererFn<S>;
    }
    return null;
  }

  /** Returns all registered (surfaceKind, intentKind) keys for diagnostics. @since W1 */
  static registeredKeys(): RegistryKey[] {
    const result: RegistryKey[] = [];
    for (const key of SurfaceRegistry.renderers.keys()) {
      const [kind, intentKind] = key.split('::') as [SurfaceKind, IntentKind];
      result.push({ kind, intentKind });
    }
    return result;
  }
}
