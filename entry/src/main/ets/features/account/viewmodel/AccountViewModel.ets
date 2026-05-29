// L3 Feature - Account - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import type { AnyIntent } from '../../../core/intent/Intent';
import type { OpenAccountIntent } from '../../../core/intent/Intent';
import { ACCOUNT_INTENT_KINDS } from '../intent/AccountIntents';

export interface AccountState {
  readonly activeSection: 'profile' | 'subscription' | 'settings' | 'support';
  readonly loading: boolean;
  readonly error: string | null;
}

const INITIAL_STATE: AccountState = {
  activeSection: 'profile',
  loading: false,
  error: null,
};

export class AccountViewModel extends FeatureViewModel<AccountState> {
  readonly kind = 'account';

  constructor() {
    super(INITIAL_STATE);
  }

  init(): () => void {
    const bus = IntentBus.getInstance();
    const unsubs = ACCOUNT_INTENT_KINDS.map((k) =>
      bus.subscribe(k, (intent) => this.handle(intent)),
    );
    return () => unsubs.forEach((u) => u());
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    if (intent.kind === 'account/open') {
      this.handleOpenAccount(intent as OpenAccountIntent);
    }
  }

  private handleOpenAccount(intent: OpenAccountIntent): void {
    this.state = { ...this.state, activeSection: intent.payload.section, error: null };
  }
}
