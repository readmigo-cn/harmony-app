// L3 Feature - Library - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import { LIBRARY_INTENT_KINDS } from '../intent/LibraryIntents';

export interface LibraryData {
  readonly opened: boolean;
}

export type LibraryState = ViewModelState<LibraryData>;

export class LibraryViewModel extends FeatureViewModel<LibraryData> {
  readonly kind = 'library';

  constructor() {
    super(LIBRARY_INTENT_KINDS);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    if (intent.kind === 'library.openBookshelf') {
      this.state = { status: 'data', data: { opened: true } };
    }
  }
}
