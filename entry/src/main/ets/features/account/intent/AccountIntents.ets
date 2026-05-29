// L3 Feature - Account - Intent
import type { OpenAccountIntent, OpenSubscriptionsIntent } from '../../../core/intent/Intent';

export type { OpenAccountIntent, OpenSubscriptionsIntent };

export type AccountIntent = OpenAccountIntent | OpenSubscriptionsIntent;
export type AccountIntentKind = AccountIntent['kind'];

export const ACCOUNT_INTENT_KINDS: AccountIntentKind[] = [
  'account.open',
  'account.openSubscriptions',
];

export function makeOpenAccountIntent(): OpenAccountIntent {
  return {
    kind: 'account.open',
    payload: {},
    idempotencyKey: `account.open:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeOpenSubscriptionsIntent(): OpenSubscriptionsIntent {
  return {
    kind: 'account.openSubscriptions',
    payload: {},
    idempotencyKey: `account.openSubscriptions:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}
