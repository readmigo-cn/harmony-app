// L3 Feature - Discover - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import type { BrowseDiscoverIntent } from '../../../core/intent/Intent';
import { DISCOVER_INTENT_KINDS } from '../intent/DiscoverIntents';

export interface DiscoverData {
  readonly activeTab: string | null;
}

export type DiscoverState = ViewModelState<DiscoverData>;

export class DiscoverViewModel extends FeatureViewModel<DiscoverData> {
  readonly kind = 'discover';

  constructor() {
    super(DISCOVER_INTENT_KINDS);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    if (intent.kind === 'discover.browse') {
      this.handleBrowse(intent as BrowseDiscoverIntent);
    }
  }

  private handleBrowse(intent: BrowseDiscoverIntent): void {
    // Actual data fetch remains in the existing Discover page; VM tracks tab state only.
    this.state = { status: 'data', data: { activeTab: intent.payload.tab ?? null } };
  }
}
