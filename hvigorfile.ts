// hvigorfile.ts - Project level build configuration
import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { spawnSync } from 'node:child_process';

// PR-7: Import boundary enforcement.
// 在每次 hvigor 构建启动时跑 scripts/check-import-boundary.mjs；如果 violation
// 数 > 0 直接 throw，构建失败。详见 docs/ARCHITECTURE.md。
// TODO: verify hvigor plugin API shape — hvigor 4.x 的实际 plugin spec 可能要求
// 不同的 lifecycle hook (e.g. pluginContext.registerLifecycleHook)，此处用最直接
// 的 apply()，若未被调用，请改为 hvigor 推荐的形态。
const importBoundaryPlugin = {
  pluginId: 'importBoundary',
  apply: () => {
    const r = spawnSync('node', ['scripts/check-import-boundary.mjs'], { stdio: 'inherit' });
    if (r.status !== 0) {
      throw new Error('Import boundary check failed');
    }
  },
};

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[importBoundaryPlugin]         /* Custom plugin to extend the functionality of Hvigor. */
}
