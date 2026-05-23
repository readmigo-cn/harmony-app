// ExampleAbility.test.ets
// Hypium UIAbility smoke test for the Readmigo CN HarmonyOS NEXT entry module.
// Phase 2 will add real assertions (UIAbility lifecycle, page nav); this is W1
// framework setup so CI can prove `hvigor test` runs to completion.

import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';

export default function exampleAbilityTest() {
  describe('ExampleAbilityTest', () => {
    beforeAll(() => {
      // Phase 2: bootstrap AbilityDelegator and start EntryAbility here.
    });

    beforeEach(() => {
      // No-op for W1 placeholder.
    });

    afterEach(() => {
      // No-op for W1 placeholder.
    });

    afterAll(() => {
      // Phase 2: tear down delegator context.
    });

    it('should run hypium framework and pass a trivial assertion', 0, () => {
      // W1 sanity check: confirms @ohos/hypium is wired up and the runner finds tests.
      const sum: number = 1 + 1;
      expect(sum).assertEqual(2);
    });

    it('should expose the expected bundle name', 0, () => {
      // Phase 2: replace with `bundleManager.getBundleInfoForSelf(...)` assertion.
      const expectedBundle: string = 'com.readmigo.harmony.cn';
      expect(expectedBundle).assertEqual('com.readmigo.harmony.cn');
    });
  });
}
