// L3 Feature - Library - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import type { AnyIntent } from '../../../core/intent/Intent';
import type { OpenBookshelfIntent } from '../../../core/intent/Intent';
import { LIBRARY_INTENT_KINDS } from '../intent/LibraryIntents';

export interface LibraryState {
  readonly activeShelfId: string | null;
  readonly activeFilterTag: string | null;
  readonly loading: boolean;
  readonly error: string | null;
}

const INITIAL_STATE: LibraryState = {
  activeShelfId: null,
  activeFilterTag: null,
  loading: false,
  error: null,
};

export class LibraryViewModel extends FeatureViewModel<LibraryState> {
  readonly kind = 'library';

  constructor() {
    super(INITIAL_STATE);
  }

  init(): () => void {
    const bus = IntentBus.getInstance();
    const unsubs = LIBRARY_INTENT_KINDS.map((k) =>
      bus.subscribe(k, (intent) => this.handle(intent)),
    );
    return () => unsubs.forEach((u) => u());
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    if (intent.kind === 'library/open-shelf') {
      this.handleOpenShelf(intent as OpenBookshelfIntent);
    }
  }

  private handleOpenShelf(intent: OpenBookshelfIntent): void {
    const { shelfId, filterTag } = intent.payload;
    this.state = {
      ...this.state,
      activeShelfId: shelfId,
      activeFilterTag: filterTag,
      loading: false,
      error: null,
    };
  }
}
