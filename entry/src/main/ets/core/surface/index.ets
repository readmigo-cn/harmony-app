// L1 - Foundation - Surface
// Public barrel for the surface subsystem.

export { SurfaceKind, SURFACE_CAPABILITIES } from './SurfaceKind';
export type { SurfaceCapabilities } from './SurfaceKind';

export { SurfaceContext } from './SurfaceContext';
export { SurfaceRegistry } from './SurfaceRegistry';
export type { RendererFn } from './SurfaceRegistry';

// Surface is the single ArkUI component in L1 — see Surface.ets for justification.
export { Surface } from './Surface';
