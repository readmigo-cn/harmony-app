// scripts/check-import-boundary.mjs
// Enforce layer dependency rules for the Hybrid feature-first + W1 distributed architecture.
import { readFileSync } from 'node:fs';
import { glob } from 'node:fs/promises';

// ── W1 Layer classification ──────────────────────────────────────────────────
// Maps glob-style path prefixes to logical layer IDs used in LAYER_RULES below.
// Evaluated top-to-bottom; first match wins.
const LAYERS = {
  'core/distributed-soul/':  'L1',
  'core/intent/':            'L1',
  'core/surface/':           'L1',
  'core/theme/':             'L1',
  'core/router/':            'L1',
  'core/shell/':             'L1',
  'core/widget/':            'L1',
  'core/experiments/':       'L1',
  'core/':                   'L1',
  'api/':                    'L2',
  'store/':                  'L2',
  'features/':               'L3-L4',  // further split below by sub-path
  'ui/':                     'L4-shared',
  'model/':                  'L0',
};

// W1 additional rules layered on top of the existing RULES table:
//   L1 cannot import L2/L3/L4
//   Only core/distributed-soul may import @ohos.data.distributedDataObject
//   core/surface may import from core/intent and core/distributed-soul (same L1 — OK)
//   L3 (feature intent/vm) may not import @ohos.arkui.* except via `import type`
const W1_OHOS_DATA_OBJECT_ALLOWED = 'core/distributed-soul/';

// ── Existing per-layer forbidden-import lists ────────────────────────────────
// (Preserved verbatim from pre-W1 script)
const RULES = {
  'features/': ['/features/'],
  'ui/':       ['/features/', '/api/', '/store/'],
  'api/':      ['/features/', '/ui/', '/store/'],
  'store/':    ['/features/', '/ui/'],
  'model/':    ['/features/', '/ui/', '/api/', '/store/', '/core/'],
  'core/':     ['/features/', '/ui/', '/api/', '/store/'],
};

// ── Exception whitelist ──────────────────────────────────────────────────────
// Composition-root / engineering-reality exceptions preserved from pre-W1:
//   core/shell, core/widget, core/router, core/theme, core/experiments, api/client
// W1 additions:
//   core/distributed-soul — allowed to import @ohos.data.distributedDataObject (native only)
//   core/surface          — allowed to import @ohos.arkui.* (sole ArkUI component in L1)
const PATH_EXCEPTIONS = [
  { source: 'core/shell/',              allow: ['/features/', '/ui/', '/store/', '/api/'] },
  { source: 'core/widget/',             allow: ['/api/', '/store/', '/features/'] },
  { source: 'core/router/',             allow: ['/store/'] },
  { source: 'core/theme/',              allow: ['/store/'] },
  { source: 'core/experiments/',        allow: ['/store/'] },
  { source: 'api/client/',              allow: ['/store/'] },
  // W1: distributed-soul is the only L1 consumer of the native distributed data API.
  { source: 'core/distributed-soul/',   allow: [] },
  // W1: surface/Surface.ets is the sole ArkUI component permitted in L1.
  { source: 'core/surface/',            allow: [] },
];

// ── Cross-feature allowlist ──────────────────────────────────────────────────
const CROSS_FEATURE_ALLOW = {
  'reader':         ['ai-tools', 'audiobook', 'multi-device'],
  'vocab':          ['ai-tools', 'audiobook', 'multi-device'],
  'multi-platform': ['ai-tools', 'notes'],
  'multi-device':   ['notes', 'multi-platform'],
};

// ── W1 additional single-import violation checks ─────────────────────────────
// Run these in the main loop in addition to RULES checks.
function checkW1Rules(relPath, line, lineNum) {
  const violations = [];

  // Rule W1-1: Only core/distributed-soul may import distributedDataObject.
  if (
    line.includes('distributedDataObject') &&
    !relPath.startsWith(W1_OHOS_DATA_OBJECT_ALLOWED)
  ) {
    violations.push({
      file: relPath,
      line: lineNum,
      text: line.trim(),
      reason: 'W1-1: Only core/distributed-soul may import @ohos.data.distributedDataObject',
    });
  }

  // Rule W1-2: L3 feature intent/viewmodel dirs must not import @ohos.arkui.* (except `import type`).
  if (
    (relPath.includes('/intent/') || relPath.includes('/viewmodel/')) &&
    relPath.startsWith('features/') &&
    line.includes('@ohos.arkui') &&
    !line.trim().startsWith('import type')
  ) {
    violations.push({
      file: relPath,
      line: lineNum,
      text: line.trim(),
      reason: 'W1-2: L3 feature intent/viewmodel must not import @ohos.arkui.* (use `import type` only)',
    });
  }

  return violations;
}

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

  const lines = readFileSync(filepath, 'utf8').split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!/^\s*import\s/.test(line) && !/\bfrom\s+['"]/.test(line)) continue;
    // Skip lines that are inside block comments or single-line comments.
    if (/^\s*\*/.test(line) || /^\s*\/\//.test(line) || /^\s*\/\*/.test(line)) continue;

    // ── Existing RULES checks ──
    if (layer) {
      for (const forbidden of RULES[layer]) {
        if (!line.includes(forbidden)) continue;

        if (layer === 'features/' && forbidden === '/features/') {
          const myFeat = relPath.match(/^features\/([^/]+)/);
          const tgtFeat = line.match(/features\/([^/'"]+)/);
          if (myFeat && tgtFeat) {
            if (myFeat[1] === tgtFeat[1]) continue;
            const allowed = CROSS_FEATURE_ALLOW[myFeat[1]] || [];
            if (allowed.includes(tgtFeat[1])) continue;
          }
        }

        if (isPathExempt(relPath, forbidden)) continue;

        console.error(`VIOLATION [${layer}]: ${filepath}:${i + 1}: ${line.trim()}`);
        violations++;
      }
    }

    // ── W1 additional checks ──
    const w1 = checkW1Rules(relPath, line, i + 1);
    for (const v of w1) {
      console.error(`VIOLATION [W1] ${v.file}:${v.line}: ${v.reason}`);
      console.error(`  ${v.text}`);
      violations++;
    }
  }
}

if (violations > 0) {
  console.error(`\n${violations} import boundary violation(s).`);
  process.exit(1);
}
console.log('Import boundary check passed.');

// ── RULE-fanout-13 advisory (does not fail CI until W22) ──────────────────────
// Logs files exceeding 13 project-local imports; see layer-contract.md §7.
let fanoutWarnings = 0;
for await (const filepath of glob(`${ROOT}/**/*.ets`)) {
  const lines = readFileSync(filepath, 'utf8').split('\n');
  let localImports = 0;
  for (const line of lines) {
    if (/^\s*import\s/.test(line) && /\bfrom\s+['"](\.\.|@\/)/.test(line)) {
      localImports++;
    }
  }
  if (localImports > 13) {
    console.warn(`FANOUT-ADVISORY [RULE-fanout-13]: ${filepath} has ${localImports} local imports (ceiling: 13)`);
    fanoutWarnings++;
  }
}
if (fanoutWarnings > 0) {
  console.warn(`\n${fanoutWarnings} file(s) exceed the fanout ceiling (advisory only; enforced in W22).`);
}
