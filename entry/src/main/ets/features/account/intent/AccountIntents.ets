// L3 Feature - Account - Intent
import type { OpenAccountIntent } from '../../../core/intent/Intent';
import { SurfaceKind } from '../../../core/surface/SurfaceKind';

export type { OpenAccountIntent };

export type AccountIntent = OpenAccountIntent;
export type AccountIntentKind = AccountIntent['kind'];

export const ACCOUNT_INTENT_KINDS: AccountIntentKind[] = [
  'account/open',
];

export function makeOpenAccountIntent(
  section: 'profile' | 'subscription' | 'settings' | 'support' = 'profile',
  source: SurfaceKind = SurfaceKind.Phone,
): OpenAccountIntent {
  return {
    kind: 'account/open',
    payload: { section },
    idempotencyKey: `account/open:${section}:${Date.now()}`,
    source,
    tsMs: Date.now(),
  };
}
