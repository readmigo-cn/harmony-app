// List.test.ets
// Hypium suite aggregator. DevEco picks up `testsuite()` and runs every suite
// imported here. Add new `*.test.ets` files alongside this entry.

import exampleAbilityTest from './ExampleAbility.test';
import loginPageTest from './Login.test';
import readerPageTest from './Reader.test';
// ── Phase 2 e2e suites（W10-C7） ──
import happyPathE2ETest from './e2e/HappyPath.test';
import settingsFlowE2ETest from './e2e/SettingsFlow.test';
import offlineModeE2ETest from './e2e/OfflineMode.test';
import errorRecoveryE2ETest from './e2e/ErrorRecovery.test';
// ── W20-C5 集成验收套件 ──
import fullFlowE2ETest from './e2e/FullFlow.test';

export default function testsuite() {
  exampleAbilityTest();
  loginPageTest();
  readerPageTest();
  // e2e
  happyPathE2ETest();
  settingsFlowE2ETest();
  offlineModeE2ETest();
  errorRecoveryE2ETest();
  fullFlowE2ETest();
}
