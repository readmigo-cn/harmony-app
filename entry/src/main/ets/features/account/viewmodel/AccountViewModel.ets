// L3 Feature - Account - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import { ACCOUNT_INTENT_KINDS } from '../intent/AccountIntents';

export interface AccountData {
  readonly section: 'profile' | 'subscriptions';
}

export type AccountState = ViewModelState<AccountData>;

export class AccountViewModel extends FeatureViewModel<AccountData> {
  readonly kind = 'account';

  constructor() {
    super(ACCOUNT_INTENT_KINDS);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    switch (intent.kind) {
      case 'account.open':
        this.state = { status: 'data', data: { section: 'profile' } };
        break;
      case 'account.openSubscriptions':
        this.state = { status: 'data', data: { section: 'subscriptions' } };
        break;
      default:
        break;
    }
  }
}
