// L1 - Foundation - Intent
// Abstract base class for all feature ViewModels per intent-contract.md §9.

import type { AnyIntent } from './Intent';
import { IntentBus } from './IntentBus';
import type { Unsubscribe } from './IntentBus';

/**
 * Standard state envelope for every ViewModel.
 * Never carry partial data + error together — see intent-contract.md §5.
 * @since W1
 */
export type ViewModelState<T> =
  | { readonly status: 'idle' }
  | { readonly status: 'loading' }
  | { readonly status: 'data'; readonly data: T }
  | { readonly status: 'error'; readonly error: { readonly code: string; readonly message: string } };

/**
 * Abstract base for all feature ViewModels.
 *
 * Constructor auto-subscribes to the provided intent kinds and manages teardown.
 * Subclasses declare their own @State field for ArkUI reactivity — the base
 * holds a plain reference used for serialization / getState().
 *
 * ArkTS note: @State cannot be declared on abstract base classes; subclasses
 * must re-declare `@State state: ViewModelState<T>` for ArkUI observation.
 * @since W1
 */
export abstract class FeatureViewModel<S extends object> {
  /** Identifier matched by IntentRouter. */
  abstract readonly kind: string;

  protected state: ViewModelState<S>;
  private readonly subs: Unsubscribe[] = [];

  constructor(kinds: ReadonlyArray<IntentKind>, initialState: ViewModelState<S> = { status: 'idle' }) {
    this.state = initialState;
    const bus = IntentBus.getInstance();
    for (const k of kinds) {
      this.subs.push(bus.subscribe(k as IntentKind, (i) => this.handle(i)));
    }
  }

  /**
   * Process an incoming intent. Implementations must return within 1 frame (~16ms);
   * long work goes into L2 service calls; set state.status = 'loading' immediately.
   * @since W1
   */
  protected abstract handle(intent: AnyIntent): Promise<void>;

  /**
   * Tear down all IntentBus subscriptions. Call from the page/component onDestroy.
   * @since W1
   */
  onDestroy(): void {
    this.subs.forEach((u) => u());
    this.subs.length = 0;
  }

  /** Snapshot of current state for serialization or debugging. @since W1 */
  getState(): ViewModelState<S> {
    return this.state;
  }
}

// Re-export IntentKind so ViewModel subclass files can import from one place.
export type { IntentKind } from './Intent';
