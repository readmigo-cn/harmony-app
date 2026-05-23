// scripts/check-import-boundary.mjs
// Enforce layer dependency rules for the Hybrid feature-first architecture.
import { readFileSync } from 'node:fs';
import { glob } from 'node:fs/promises';

// 每个 layer 的 "禁止 import" 列表（路径片段，匹配会触发 violation）。
// 注意：features 内部跨 feature 在下面有专门的同 feature 例外处理。
const RULES = {
  'features/': ['/features/'],
  'ui/':       ['/features/', '/api/', '/store/'],
  'api/':      ['/features/', '/ui/', '/store/'],
  'store/':    ['/features/', '/ui/'],
  'model/':    ['/features/', '/ui/', '/api/', '/store/', '/core/'],
  'core/':     ['/features/', '/ui/', '/api/', '/store/'],
};

// 例外白名单（path-prefix in source file → 允许的 forbidden 片段集合）
// 这些是公认的"composition root / glue / 工程现实"，不破坏架构原则：
//   - core/shell：app 装配根，必须知道所有顶层 feature page；
//   - core/widget：HarmonyOS Widget ExtensionAbility，独立运行实体，需直连 api/；
//   - core/router：路由服务需读 UserStore 做 auth guard；
//   - core/theme：ThemeService 持久化用户偏好（SettingsStore + StoreKeys）；
//   - core/experiments：RemoteConfig 取用户 group；
//   - api/client：HTTP 拦截器从 UserStore 取 token / 401 时清空 store。
const PATH_EXCEPTIONS = [
  { source: 'core/shell/',         allow: ['/features/', '/ui/', '/store/', '/api/'] },
  { source: 'core/widget/',        allow: ['/api/', '/store/', '/features/'] },
  { source: 'core/router/',        allow: ['/store/'] },
  { source: 'core/theme/',         allow: ['/store/'] },
  { source: 'core/experiments/',   allow: ['/store/'] },
  { source: 'api/client/',         allow: ['/store/'] },
];

// 跨 feature 允许清单（source feature → target features[]）。
// 这些场景在 spec 中明确允许：reader / vocab / multi-platform / multi-device 内部共享 widget-like 组件。
// 物理拆分到 ui/ 还需进一步重构，先用此 allowlist 落地，后续在 ARCHITECTURE.md 中跟踪。
const CROSS_FEATURE_ALLOW = {
  // reader 阅读时调起 ai-tools 词义解释卡、audiobook 朗读、multi-device 设备协同
  'reader': ['ai-tools', 'audiobook', 'multi-device'],
  // vocab SRS 复习用 ai-tools 解释卡 + audiobook TTS + multi-device clipboard
  'vocab': ['ai-tools', 'audiobook', 'multi-device'],
  // 多端布局聚合多个 feature 的能力
  'multi-platform': ['ai-tools', 'notes'],
  // 分布式同步需要写 notes / 读 watch 端展示数据
  'multi-device': ['notes', 'multi-platform'],
};

const ROOT = 'harmony-app/entry/src/main/ets';
let violations = 0;

function isPathExempt(relPath, forbidden) {
  for (const ex of PATH_EXCEPTIONS) {
    if (relPath.startsWith(ex.source) && ex.allow.includes(forbidden)) return true;
  }
  return false;
}

for await (const filepath of glob(`${ROOT}/**/*.ets`)) {
  const relPath = filepath.replace(`${ROOT}/`, '');
  let layer = null;
  for (const prefix of Object.keys(RULES)) {
    if (relPath.startsWith(prefix)) { layer = prefix; break; }
  }
  if (!layer) continue;

  const lines = readFileSync(filepath, 'utf8').split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!/^\s*import\s/.test(line) && !/\bfrom\s+['"]/.test(line)) continue;

    for (const forbidden of RULES[layer]) {
      if (!line.includes(forbidden)) continue;

      // Cross-feature 例外：
      if (layer === 'features/' && forbidden === '/features/') {
        const myFeat = relPath.match(/^features\/([^/]+)/);
        const tgtFeat = line.match(/features\/([^/'"]+)/);
        if (myFeat && tgtFeat) {
          // 同 feature 永远 OK
          if (myFeat[1] === tgtFeat[1]) continue;
          // 允许清单
          const allowed = CROSS_FEATURE_ALLOW[myFeat[1]] || [];
          if (allowed.includes(tgtFeat[1])) continue;
        }
      }

      // path-level 白名单
      if (isPathExempt(relPath, forbidden)) continue;

      console.error(`VIOLATION [${layer}]: ${filepath}:${i + 1}`);
      console.error(`  ${line.trim()}`);
      violations++;
    }
  }
}

if (violations > 0) {
  console.error(`\n${violations} import boundary violation(s).`);
  process.exit(1);
}
console.log('Import boundary check passed.');
