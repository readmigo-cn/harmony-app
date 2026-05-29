// L3 Feature - Discover - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import type { AnyIntent } from '../../../core/intent/Intent';
import type { BrowseDiscoverIntent } from '../../../core/intent/Intent';
import { DISCOVER_INTENT_KINDS } from '../intent/DiscoverIntents';

export interface DiscoverState {
  readonly activeCategory: string | null;
  readonly searchQuery: string | null;
  readonly loading: boolean;
  readonly error: string | null;
}

const INITIAL_STATE: DiscoverState = {
  activeCategory: null,
  searchQuery: null,
  loading: false,
  error: null,
};

export class DiscoverViewModel extends FeatureViewModel<DiscoverState> {
  readonly kind = 'discover';

  constructor() {
    super(INITIAL_STATE);
  }

  init(): () => void {
    const bus = IntentBus.getInstance();
    const unsubs = DISCOVER_INTENT_KINDS.map((k) =>
      bus.subscribe(k, (intent) => this.handle(intent)),
    );
    return () => unsubs.forEach((u) => u());
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    if (intent.kind === 'discover/browse') {
      this.handleBrowse(intent as BrowseDiscoverIntent);
    }
  }

  private handleBrowse(intent: BrowseDiscoverIntent): void {
    const { category, searchQuery } = intent.payload;
    this.state = { ...this.state, activeCategory: category, searchQuery, loading: true, error: null };
    // Actual data fetch is owned by the existing Discover page; VM tracks filter state only.
    this.state = { ...this.state, loading: false };
  }
}
