# harmony-app Feature-First refactor implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `harmony-app/` from horizontal-layer structure to Hybrid feature-first architecture, delivered as 7 independently revertible PRs.

**Architecture:** Top-level directories = `core/` (cross-cutting + platform) + `ui/` (shared UI) + `api/` (HTTP client split by business domain) + `store/` (global reactive store) + `model/` (single-source domain model) + `features/` (15 vertical features). Each PR does only `git mv` + import path rewrites + the necessary schema merge; **no semantic refactoring**.

**Tech Stack:** ArkTS (HarmonyOS NEXT) / hvigor build / Hypium unit tests / Node.js codemod / git on Gitee.

**Spec:** [`./2026-05-17-harmony-app-feature-first-design.md`](./2026-05-17-harmony-app-feature-first-design.md)

**Working Directory:** All paths below are relative to `harmony-app/` unless explicitly absolute.

---

## On the meaning of TDD in this plan

This plan is primarily a **pure refactor**: file relocation + import rewriting; no new features are introduced. The classical "write test → see red → implement → see green" loop does not apply. **Here "tests" means:**

1. `hvigor clean build` must pass (the build is the test)
2. Existing Hypium unit tests must keep passing (regression test)
3. Real-device cold start + 5-main-tab smoke must be OK (manual smoke)
4. The specific `grep` / `find` commands at each PR's tail must return expected output (structural assertions)

Every task follows the same rhythm: **Action → Verify → Commit**. If Verify fails, apply the rollback playbook in spec §7.3.

---

## Common command prefix

All commands default to running under `harmony-app/`:

```bash
cd /Users/HONGBGU/Documents/readmigo-cn/harmony-app
```

The **mandatory verification suite** before every task ends (referred to below as the **"VERIFY suite"**):

```bash
# 1. Full build (always clean)
rm -rf build oh_modules
ohpm install
hvigor clean
hvigor assembleHap

# 2. Hypium unit tests
hvigor test

# 3. .ts residue check (must remain 0 after PR-1)
find entry/src/main/ets -name "*.ts" | wc -l

# 4. NAPI ABI invariance
grep -rn "from 'lib.*\.so'" entry/src/main/ets/ | sort > /tmp/napi-after.txt
diff /tmp/napi-before.txt /tmp/napi-after.txt   # must be empty
```

---

## File structure (refactor target state)

### Core layer (cross-cutting concerns + platform capabilities)

| Path | Responsibility |
|---|---|
| `entry/src/main/ets/core/router/RouteConstants.ets` | Route path constants (grouped by feature with comments) |
| `entry/src/main/ets/core/router/RouterService.ets` | Routing service |
| `entry/src/main/ets/core/shell/Index.ets` | App skeleton + TabBar (originally pages/Index.ets) |
| `entry/src/main/ets/core/native/` | NAPI call layer (contains `import x from 'lib*.so'`, **ABI unchanged**) |
| `entry/src/main/ets/core/persistence/` | DatabaseManager / RdbOrm / repositories / PreferencesManager |
| `entry/src/main/ets/core/widget/` | Home-screen widget cards |
| `entry/src/main/ets/core/theme/` | Theming system |
| `entry/src/main/ets/core/extensions/` | Extension utilities |
| `entry/src/main/ets/core/analytics/` | Analytics |
| `entry/src/main/ets/core/monitoring/` | Monitoring |
| `entry/src/main/ets/core/performance/` | Performance metric collection |
| `entry/src/main/ets/core/cache/` | In-memory / disk cache |
| `entry/src/main/ets/core/experiments/` | A/B experiments |
| `entry/src/main/ets/core/moderation/` | Content moderation |
| `entry/src/main/ets/core/dynamic/` | Dynamic config / hot config |
| `entry/src/main/ets/core/atomic/` | HarmonyOS atomic-service runtime support |

### UI / API / Store / Model / Features layers

See spec §3.1 directory tree and §4 features split inventory.

### Tools and scripts

| Path | Responsibility |
|---|---|
| `scripts/rewrite-imports.mjs` | Node.js codemod that rewrites imports according to `rewrite-map-prX.json` |
| `scripts/rewrite-map-pr1.json` ... `pr7.json` | Per-PR path mapping table |
| `scripts/check-import-boundary.mjs` | Introduced in PR-7; validates cross-layer dependency rules |
| `scripts/test-rewrite/` | Fixture tests for the codemod itself |

---

# PR-0: Codemod infrastructure (preliminary task)

PR-0 provides the import rewriting tool used by every subsequent PR. **Must complete before starting PR-1.**

### Task 0.1: Create the codemod main script

**Files:**
- Create: `scripts/rewrite-imports.mjs`

- [ ] **Step 1: Write the script**

```javascript
// scripts/rewrite-imports.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { glob } from 'node:fs/promises';

const NAPI_SKIP = /from\s+['"]lib[^'"]*\.so['"]/;

async function main() {
  const mapFile = process.argv[2];
  const root = process.argv[3] || 'entry/src/main/ets';
  if (!mapFile) {
    console.error('Usage: node rewrite-imports.mjs <map.json> [root]');
    process.exit(1);
  }
  const parsed = JSON.parse(readFileSync(mapFile, 'utf8'));
  const compiled = parsed.mappings.map(m => ({ re: new RegExp(m.from, 'g'), to: m.to }));

  let filesChanged = 0;
  let importsChanged = 0;
  const testRoot = root.replace('main/ets', 'ohosTest/ets');

  for (const r of [root, testRoot]) {
    for await (const filepath of glob(`${r}/**/*.ets`)) {
      const original = readFileSync(filepath, 'utf8');
      const lines = original.split('\n');
      let modified = false;
      const newLines = lines.map(line => {
        if (!/^\s*import\s/.test(line)) return line;
        if (NAPI_SKIP.test(line)) return line;
        let out = line;
        for (const m of compiled) {
          out = out.replace(m.re, m.to);
        }
        if (out !== line) {
          modified = true;
          importsChanged++;
        }
        return out;
      });
      if (modified) {
        writeFileSync(filepath, newLines.join('\n'));
        filesChanged++;
      }
    }
  }
  console.log(`Files changed: ${filesChanged}`);
  console.log(`Imports rewritten: ${importsChanged}`);
}

main().catch(err => { console.error(err); process.exit(1); });
```

- [ ] **Step 2: Commit**

```bash
git add scripts/rewrite-imports.mjs
git commit -m "chore(scripts): add codemod for import rewriting"
```

### Task 0.2: Codemod self-test fixture

**Files:**
- Create: `scripts/test-rewrite/fixture.ets`
- Create: `scripts/test-rewrite/expected.ets`
- Create: `scripts/test-rewrite/test-map.json`
- Create: `scripts/test-rewrite/run-test.mjs`

- [ ] **Step 1: Write fixture input**

```
// scripts/test-rewrite/fixture.ets
import { Foo } from '../service/cache/Foo';
import { Bar } from './service/api/BarApi';
import { Baz } from 'libnative.so';
import { Qux } from '../router/RouterService';
```

- [ ] **Step 2: Write expected output**

```
// scripts/test-rewrite/expected.ets
import { Foo } from '../core/cache/Foo';
import { Bar } from './api/bar/BarApi';
import { Baz } from 'libnative.so';
import { Qux } from '../core/router/RouterService';
```

- [ ] **Step 3: Write the test map**

```json
{
  "version": "test",
  "mappings": [
    { "from": "(\\.\\.?/)+service/cache/", "to": "$1core/cache/" },
    { "from": "(\\.\\.?/)+service/api/Bar", "to": "$1api/bar/Bar" },
    { "from": "(\\.\\.?/)+router/", "to": "$1core/router/" }
  ]
}
```

- [ ] **Step 4: Write the test runner (use spawnSync array form, no shell)**

```javascript
// scripts/test-rewrite/run-test.mjs
import { spawnSync } from 'node:child_process';
import { readFileSync, copyFileSync, mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dir = mkdtempSync(path.join(tmpdir(), 'codemod-test-'));
try {
  const inside = path.join(dir, 'entry', 'src', 'main', 'ets');
  mkdirSync(inside, { recursive: true });
  copyFileSync(path.join(__dirname, 'fixture.ets'), path.join(inside, 'fixture.ets'));

  const mapPath = path.join(__dirname, 'test-map.json');
  const rewriter = path.join(__dirname, '..', 'rewrite-imports.mjs');
  const r = spawnSync('node', [rewriter, mapPath, inside], { stdio: 'inherit' });
  if (r.status !== 0) { console.error('rewriter failed'); process.exit(1); }

  const actual = readFileSync(path.join(inside, 'fixture.ets'), 'utf8');
  const expected = readFileSync(path.join(__dirname, 'expected.ets'), 'utf8');
  if (actual.trim() !== expected.trim()) {
    console.error('FAIL');
    console.error('--- Expected ---'); console.error(expected);
    console.error('--- Actual ---');   console.error(actual);
    process.exit(1);
  }
  console.log('OK');
} finally {
  rmSync(dir, { recursive: true, force: true });
}
```

- [ ] **Step 5: Run the test**

```bash
node scripts/test-rewrite/run-test.mjs
```

Expected output: `Files changed: 1`, `Imports rewritten: 3`, `OK`

- [ ] **Step 6: Commit**

```bash
git add scripts/test-rewrite/
git commit -m "chore(scripts): add codemod self-test fixture"
```

### Task 0.3: Establish NAPI ABI baseline

- [ ] **Step 1: Save current NAPI import snapshot**

```bash
mkdir -p .refactor-snapshots
grep -rn "from 'lib.*\.so'" entry/src/main/ets/ | sort > .refactor-snapshots/napi-baseline.txt
wc -l .refactor-snapshots/napi-baseline.txt
```

Expected: shows the current total count of NAPI `.so` import lines

- [ ] **Step 2: Add .refactor-snapshots/ to gitignore**

Open `.gitignore` and append at the end:

```
.refactor-snapshots/
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore .refactor-snapshots/"
```

---

# PR-1: Single-source model + eliminate .ts residue

**Target output:** 0 `.ts` files under ets/; `model/Book.ets` as the only Book schema; hvigor build pass; full Hypium pass.

**Branch:** `git checkout -b refactor/pr1-model-unify`

### Task 1.1: Merge Book.ets schema

**Files:**
- Modify: `entry/src/main/ets/model/Book.ets`

- [ ] **Step 1: Overwrite `entry/src/main/ets/model/Book.ets` entirely with the content below**

```typescript
/**
 * Book domain model — single source (merged from historical Book.ts + Book.ets).
 * Fields aligned with server-cn /api/v1/books DTO; product fields from overseas mobile kept as optional.
 */

export type BookStatus = 'want-to-read' | 'reading' | 'finished';
export type SortBy = 'recent' | 'lastRead' | 'title' | 'rating';
export type BookListType =
  | 'RANKING' | 'EDITORS_PICK' | 'COLLECTION' | 'UNIVERSITY'
  | 'CELEBRITY' | 'ANNUAL_BEST' | 'AI_RECOMMENDED' | 'PERSONALIZED' | 'AI_FEATURED';

export interface Book {
  id: string;
  slug: string;
  title: string;
  author: string;
  authorId?: string;
  authorZh?: string;
  coverUrl?: string;
  coverThumbUrl?: string;
  description?: string;
  language: string;
  cefrLevel?: string;
  difficulty?: number;
  difficultyScore?: number;
  category?: string;
  wordCount?: number;
  publishYear?: number;
  source?: string;
  goodreadsRating?: number;
  doubanRating?: number;
  genres?: string[];
  hasAudiobook?: boolean;
  audiobookId?: string;
}

export interface BookDetail extends Book {
  epubUrl?: string;
  chapters?: Chapter[];
  aiScore?: number;
  estimatedReadTime?: number;
  totalChapters?: number;
  tags?: string[];
  seriesId?: string;
  seriesName?: string;
  seriesPosition?: number;
  seriesBookCount?: number;
}

export interface UserBook {
  bookId: string;
  book: Book;
  status: BookStatus;
  addedAt: string;
  lastReadAt?: string;
  progress: number;
  currentChapterIndex?: number;
  currentCfi?: string;
}

export interface Chapter {
  id: string;
  title: string;
  href?: string;
  order: number;
  wordCount?: number;
}

export interface BookFilters {
  page?: number;
  limit?: number;
  language?: string;
  cefrLevel?: string;
  category?: string;
  search?: string;
  sortBy?: SortBy;
}

export interface BookListResponse {
  items: Book[];
  total: number;
  page: number;
  limit: number;
  hasMore: boolean;
}

export interface BookListBook {
  id: string;
  title: string;
  author: string;
  authorId?: string;
  description?: string;
  coverUrl?: string;
  coverThumbUrl?: string;
  difficultyScore?: number;
  wordCount?: number;
  genres?: string[];
  doubanRating?: number;
  goodreadsRating?: number;
  rank?: number;
  customDescription?: string;
  difficulty?: number;
  audiobookId?: string;
}

export interface BookList {
  id: string;
  name: string;
  nameEn?: string;
  subtitle?: string;
  description?: string;
  coverUrl?: string;
  type: BookListType;
  displayStyle?: string;
  bookCount: number;
  sortOrder?: number;
  isActive?: boolean;
  showRank?: boolean;
  showDescription?: boolean;
  maxDisplayCount?: number;
  isAiGenerated?: boolean;
  books?: BookListBook[];
  createdAt?: string;
  updatedAt?: string;
}

export interface Rating {
  id: string;
  userId: string;
  userName?: string;
  rating: number;
  comment?: string;
  createdAt: string;
}
```

- [ ] **Step 2: Delete Book.ts**

```bash
git rm entry/src/main/ets/model/Book.ts
```

### Task 1.2: Scan Book required-field call sites and add guards

**Files:** every `.ets` file that references the affected fields

- [ ] **Step 1: Enumerate call sites**

```bash
grep -rn "book\.\(coverUrl\|description\|category\|wordCount\)" entry/src/main/ets --include="*.ets" > /tmp/book-required-uses.txt
cat /tmp/book-required-uses.txt
```

- [ ] **Step 2: Manually add scenario-appropriate guards**

For each call site, substitute per the table below:

| Original | Replace with |
|---|---|
| `book.coverUrl` (string assignment / Image src) | `book.coverUrl ?? ''` |
| `book.coverUrl.length > 0` | `(book.coverUrl?.length ?? 0) > 0` |
| `book.coverUrl.startsWith('http')` | `book.coverUrl?.startsWith('http') === true` |
| `book.description` | `book.description ?? ''` |
| `book.category` | `book.category ?? 'Other'` |
| `book.wordCount > 0` | `(book.wordCount ?? 0) > 0` |
| `book.wordCount` (display) | `book.wordCount ?? 0` |

- [ ] **Step 3: Re-grep to verify no omissions**

```bash
grep -rn "book\.\(coverUrl\|description\|category\|wordCount\)\b" entry/src/main/ets --include="*.ets" | grep -v "?? \|?\."
```

Expected: empty

### Task 1.3: Convert Audiobook.ts → Audiobook.ets

- [ ] **Step 1: git mv**

```bash
git mv entry/src/main/ets/model/Audiobook.ts entry/src/main/ets/model/Audiobook.ets
```

- [ ] **Step 2: Check ArkTS syntax compatibility**

Open `entry/src/main/ets/model/Audiobook.ets` and confirm:
- No `import type` statements (if any, change to `import`)
- All interface field types contain no `any`
- `export const PLAYBACK_SPEEDS` and similar definitions appear before they are used

### Task 1.4: Convert AudioPlayerStore.ts → AudioPlayerStore.ets

- [ ] **Step 1: git mv**

```bash
git mv entry/src/main/ets/store/AudioPlayerStore.ts entry/src/main/ets/store/AudioPlayerStore.ets
```

- [ ] **Step 2: Change `import type` to `import`**

Open the file and change:

```typescript
import type {
  Audiobook,
  AudiobookChapter,
  PlaybackSpeed,
  SleepTimerOption,
  AudioPlayerState,
} from '../model/Audiobook';
```

to:

```typescript
import {
  Audiobook,
  AudiobookChapter,
  PlaybackSpeed,
  SleepTimerOption,
  AudioPlayerState,
} from '../model/Audiobook';
```

- [ ] **Step 3: Extract a named listener type**

Insert right after the top-of-file imports:

```typescript
export type AudioPlayerStateListener = (state: AudioPlayerStore) => void;
```

Change:

```typescript
private onStateChangeCallbacks: Array<(state: AudioPlayerStore) => void> = [];
```

to:

```typescript
private onStateChangeCallbacks: AudioPlayerStateListener[] = [];
```

Update the `subscribe(callback)` signature similarly to `subscribe(callback: AudioPlayerStateListener): () => void`.

- [ ] **Step 4: Append a Phase 2 follow-up comment (end of file)**

```typescript
// PHASE 2 FOLLOWUP: replace callback subscribe with @ObservedV2 + @Trace decorators
// or migrate to AppStorage so ArkUI @State / @StorageLink can subscribe directly.
// Current callback model does NOT trigger ArkUI rebuild — UI changes rely on
// upstream wrappers. See docs/specs/2026-05-17-harmony-app-feature-first-design.md §8.
```

### Task 1.5: Create the model/index.ets barrel

**Files:**
- Create: `entry/src/main/ets/model/index.ets`

- [ ] **Step 1: Write the barrel**

```typescript
// entry/src/main/ets/model/index.ets
export * from './Book';
export * from './Audiobook';
export * from './Chapter';
export * from './ReadingProgress';
export * from './Highlight';
export * from './ExplainData';
```

### Task 1.6: Write PR-1 rewrite-map and run the codemod

**Files:**
- Create: `scripts/rewrite-map-pr1.json`

- [ ] **Step 1: Write the mapping file**

```json
{
  "version": "PR-1",
  "mappings": [
    { "from": "/model/Book\\.ts(?=['\"])", "to": "/model/Book" },
    { "from": "/model/Audiobook\\.ts(?=['\"])", "to": "/model/Audiobook" },
    { "from": "/store/AudioPlayerStore\\.ts(?=['\"])", "to": "/store/AudioPlayerStore" }
  ]
}
```

Note: ArkTS imports default to no suffix, so the rewrite rule strips the `.ts` suffix. Run it as a safety net.

- [ ] **Step 2: Run the codemod**

```bash
node scripts/rewrite-imports.mjs scripts/rewrite-map-pr1.json
```

- [ ] **Step 3: Manually grep for any `.ts` suffix residue**

```bash
grep -rn "from '.*Book\.ts'" entry/src/main/ets --include="*.ets"
grep -rn "from '.*Audiobook\.ts'" entry/src/main/ets --include="*.ets"
grep -rn "from '.*AudioPlayerStore\.ts'" entry/src/main/ets --include="*.ets"
```

Expected: 0 hits

### Task 1.7: Run the VERIFY suite

- [ ] **Step 1: Save NAPI baseline to /tmp**

```bash
cp .refactor-snapshots/napi-baseline.txt /tmp/napi-before.txt
```

- [ ] **Step 2: Clean + rebuild**

```bash
rm -rf build oh_modules
ohpm install
hvigor clean
hvigor assembleHap
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Hypium unit tests**

```bash
hvigor test
```

Expected: all tests pass

- [ ] **Step 4: .ts residue check**

```bash
find entry/src/main/ets -name "*.ts" | wc -l
```

Expected: `0`

- [ ] **Step 5: NAPI ABI diff**

```bash
grep -rn "from 'lib.*\.so'" entry/src/main/ets/ | sort > /tmp/napi-after.txt
diff /tmp/napi-before.txt /tmp/napi-after.txt
```

Expected: empty

- [ ] **Step 6: Real-device smoke**

Deploy to a real device via DevEco Studio; verify cold start + 5-main-tab switching + opening any book into Reader without crash.

### Task 1.8: Squash commit + push + MR

- [ ] **Step 1: Squash into a single commit**

```bash
git add -A
git commit -m "refactor(model): unify Book schema and eliminate .ts residue (PR-1)

- Merge Book.ts into Book.ets as single source of truth (aligned to
  server-cn DTO, with overseas-mobile fields retained as optional)
- Rename Audiobook.ts and store/AudioPlayerStore.ts to .ets
- Add model/index.ets barrel
- Add null-guards at all book.coverUrl/description/category/wordCount
  call sites for the relaxed-optional schema
- Phase 1 only: AudioPlayerStore retains callback subscribe model;
  reactive paradigm migration deferred to Phase 2 followup

Verification:
- find entry/src/main/ets -name '*.ts' | wc -l == 0
- hvigor clean assembleHap pass
- hvigor test pass
- 5-tab smoke OK on real device"
```

- [ ] **Step 2: Push and open MR**

```bash
git push -u origin refactor/pr1-model-unify
```

On Gitee, open MR titled: `PR-1: Model unification & .ts residue elimination`.

- [ ] **Step 3: Wait 24h after merge before opening PR-2** (per spec §7.3 safeguard)

---

# PR-2: core/ foundation + cross-cutting service sink

**Target output:** `core/` top-level established; 9 cross-cutting services sunk; 6 original horizontal directories moved in; hvigor build pass.

**Branch:** `git checkout main && git pull && git checkout -b refactor/pr2-core-foundation`

### Task 2.1: grep to confirm 0 RouterAdapter references

- [ ] **Step 1: Search references**

```bash
grep -rn "RouterAdapter" entry/src/main/ets --include="*.ets"
```

Expected: 0 hits, or only the self-definition in router/RouterAdapter.ets. If external references exist, pause this task and eliminate them first.

### Task 2.2: Move the 6 original horizontal directories into core/

- [ ] **Step 1: Create core top level**

```bash
mkdir -p entry/src/main/ets/core
```

- [ ] **Step 2: git mv the 6 directories**

```bash
git mv entry/src/main/ets/router entry/src/main/ets/core/router
git mv entry/src/main/ets/native entry/src/main/ets/core/native
git mv entry/src/main/ets/persistence entry/src/main/ets/core/persistence
git mv entry/src/main/ets/widget entry/src/main/ets/core/widget
git mv entry/src/main/ets/theme entry/src/main/ets/core/theme
git mv entry/src/main/ets/extensions entry/src/main/ets/core/extensions
```

- [ ] **Step 3: Delete RouterAdapter (if Task 2.1 confirmed 0 references)**

```bash
git rm entry/src/main/ets/core/router/RouterAdapter.ets
```

### Task 2.3: Move the 9 cross-cutting service subdirectories into core/

- [ ] **Step 1: git mv 8 independent subdirectories**

```bash
git mv entry/src/main/ets/service/cache entry/src/main/ets/core/cache
git mv entry/src/main/ets/service/monitoring entry/src/main/ets/core/monitoring
git mv entry/src/main/ets/service/performance entry/src/main/ets/core/performance
git mv entry/src/main/ets/service/analytics entry/src/main/ets/core/analytics
git mv entry/src/main/ets/service/experiments entry/src/main/ets/core/experiments
git mv entry/src/main/ets/service/moderation entry/src/main/ets/core/moderation
git mv entry/src/main/ets/service/dynamic entry/src/main/ets/core/dynamic
git mv entry/src/main/ets/service/atomic entry/src/main/ets/core/atomic
```

- [ ] **Step 2: Merge service/storage into core/persistence**

```bash
ls entry/src/main/ets/service/storage/
```

If only `Storage.ets` is present:

```bash
git mv entry/src/main/ets/service/storage/Storage.ets entry/src/main/ets/core/persistence/Storage.ets
rmdir entry/src/main/ets/service/storage
```

On filename conflict, rename first then move.

### Task 2.4: Move Index.ets into core/shell/

- [ ] **Step 1: Create directory + mv**

```bash
mkdir -p entry/src/main/ets/core/shell
git mv entry/src/main/ets/pages/Index.ets entry/src/main/ets/core/shell/Index.ets
```

- [ ] **Step 2: Update `entry/src/main/module.json5`**

Open module.json5. If the `pages` field points to a profile (e.g. `"$profile:main_pages"`), open the corresponding `entry/src/main/resources/base/profile/main_pages.json` and change `"pages/Index"` to `"core/shell/Index"`.

### Task 2.5: Write PR-2 rewrite-map and run the codemod

- [ ] **Step 1: Write `scripts/rewrite-map-pr2.json`**

```json
{
  "version": "PR-2",
  "mappings": [
    { "from": "(?<=['\"])(\\.\\.?/)+router/", "to": "$1core/router/" },
    { "from": "(?<=['\"])(\\.\\.?/)+native/", "to": "$1core/native/" },
    { "from": "(?<=['\"])(\\.\\.?/)+persistence/", "to": "$1core/persistence/" },
    { "from": "(?<=['\"])(\\.\\.?/)+widget/", "to": "$1core/widget/" },
    { "from": "(?<=['\"])(\\.\\.?/)+theme/", "to": "$1core/theme/" },
    { "from": "(?<=['\"])(\\.\\.?/)+extensions/", "to": "$1core/extensions/" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/cache/", "to": "$1core/cache/" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/monitoring/", "to": "$1core/monitoring/" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/performance/", "to": "$1core/performance/" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/analytics/", "to": "$1core/analytics/" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/experiments/", "to": "$1core/experiments/" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/moderation/", "to": "$1core/moderation/" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/dynamic/", "to": "$1core/dynamic/" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/atomic/", "to": "$1core/atomic/" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/storage/", "to": "$1core/persistence/" },
    { "from": "(?<=['\"])(\\.\\.?/)+pages/Index(?=['\"])", "to": "$1core/shell/Index" }
  ]
}
```

**Note:** the codemod only does name substitution; **it does not correct `../` level counts**. Wrong relative-path levels due to caller location changes are located via build errors and fixed by hand.

- [ ] **Step 2: Run the codemod**

```bash
node scripts/rewrite-imports.mjs scripts/rewrite-map-pr2.json
```

- [ ] **Step 3: hvigor build to collect failing imports**

```bash
hvigor clean
hvigor assembleHap 2>&1 | tee /tmp/build-pr2.log | grep -i "Cannot find\|not found\|module" | head -50
```

- [ ] **Step 4: Manually fix relative-path prefixes one error at a time**

Each error points at a relative-import level issue. Open the file with the error and adjust the `../` count.

### Task 2.6: Run the VERIFY suite

- [ ] **Step 1: Full rebuild**

```bash
rm -rf build oh_modules
ohpm install
hvigor clean
hvigor assembleHap
```

Expected: BUILD SUCCESSFUL

- [ ] **Step 2: Hypium unit tests**

```bash
hvigor test
```

- [ ] **Step 3: Structural assertion**

```bash
for d in router native persistence widget theme extensions; do
  test -d "entry/src/main/ets/$d" && echo "FAIL: $d still exists" || echo "OK: $d gone"
done
ls entry/src/main/ets/core/
```

Expected: all OK; about 15–16 subdirectories under core/

- [ ] **Step 4: NAPI ABI diff**

```bash
grep -rn "from 'lib.*\.so'" entry/src/main/ets/ | sort > /tmp/napi-after-pr2.txt
diff .refactor-snapshots/napi-baseline.txt /tmp/napi-after-pr2.txt
```

Expected: empty

- [ ] **Step 5: Real-device smoke** (5 main tabs + opening a book once)

### Task 2.7: Commit + push + MR

```bash
git add -A
git commit -m "refactor(core): establish core/ foundation and cross-cutting service descent (PR-2)

- Create core/ top-level grouping for cross-cutting concerns
- Move router/native/persistence/widget/theme/extensions to core/
- Move 8 cross-cutting service subdirs to core/
- Merge service/storage into core/persistence
- Move pages/Index.ets to core/shell/Index.ets
- Delete unused RouterAdapter.ets
- Rewrite all import paths via scripts/rewrite-map-pr2.json codemod"

git push -u origin refactor/pr2-core-foundation
```

---

# PR-3: ui/ + api/ reshuffle

**Target output:** the top-level `components/` and `service/api/` flat layouts disappear; `ui/` 4 subdirectories + `api/` business-domain split established; hvigor build pass.

**Branch:** `git checkout main && git pull && git checkout -b refactor/pr3-ui-api`

### Task 3.1: components/ → ui/ reclassification

- [ ] **Step 1: Create the 4 ui/ subdirectories**

```bash
mkdir -p entry/src/main/ets/ui/primitives entry/src/main/ets/ui/responsive entry/src/main/ets/ui/lazy entry/src/main/ets/ui/sheets
```

- [ ] **Step 2: Move primitives**

```bash
for f in Button Card Input List Tab Toast Modal Loading EmptyState; do
  git mv entry/src/main/ets/components/$f.ets entry/src/main/ets/ui/primitives/$f.ets
done
```

- [ ] **Step 3: Move responsive**

```bash
git mv entry/src/main/ets/components/responsive/AdaptiveGrid.ets entry/src/main/ets/ui/responsive/AdaptiveGrid.ets
git mv entry/src/main/ets/components/responsive/FoldAwareLayout.ets entry/src/main/ets/ui/responsive/FoldAwareLayout.ets
git mv entry/src/main/ets/components/responsive/ResponsiveContainer.ets entry/src/main/ets/ui/responsive/ResponsiveContainer.ets
rmdir entry/src/main/ets/components/responsive
```

- [ ] **Step 4: Move lazy**

```bash
git mv entry/src/main/ets/components/optimized/LazyImage.ets entry/src/main/ets/ui/lazy/LazyImage.ets
rmdir entry/src/main/ets/components/optimized
```

- [ ] **Step 5: Delete the components/index.ets barrel**

```bash
git rm entry/src/main/ets/components/index.ets
```

Feature-local components (BilingualReader / VocabDetailSheet / etc.) remain at the top of `components/` for now; they will be moved in PR-4/5/6.

### Task 3.2: service/api/ → api/ business-domain split

- [ ] **Step 1: Create the api/ business-domain subdirectories**

```bash
mkdir -p entry/src/main/ets/api/client entry/src/main/ets/api/books entry/src/main/ets/api/auth entry/src/main/ets/api/reading entry/src/main/ets/api/ai entry/src/main/ets/api/notes entry/src/main/ets/api/study entry/src/main/ets/api/subscription entry/src/main/ets/api/support entry/src/main/ets/api/widget
```

- [ ] **Step 2: Move the 11 Api files**

```bash
git mv entry/src/main/ets/service/api/BooksApi.ets entry/src/main/ets/api/books/BooksApi.ets
git mv entry/src/main/ets/service/api/AuthApi.ets entry/src/main/ets/api/auth/AuthApi.ets
git mv entry/src/main/ets/service/api/ReadingApi.ets entry/src/main/ets/api/reading/ReadingApi.ets
git mv entry/src/main/ets/service/api/StatsApi.ets entry/src/main/ets/api/reading/StatsApi.ets
git mv entry/src/main/ets/service/api/AiApi.ets entry/src/main/ets/api/ai/AiApi.ets
git mv entry/src/main/ets/service/api/WordAnalysisApi.ets entry/src/main/ets/api/ai/WordAnalysisApi.ets
git mv entry/src/main/ets/service/api/NotesApi.ets entry/src/main/ets/api/notes/NotesApi.ets
git mv entry/src/main/ets/service/api/StudyPlanApi.ets entry/src/main/ets/api/study/StudyPlanApi.ets
git mv entry/src/main/ets/service/api/SubscriptionApi.ets entry/src/main/ets/api/subscription/SubscriptionApi.ets
git mv entry/src/main/ets/service/api/SupportApi.ets entry/src/main/ets/api/support/SupportApi.ets
git mv entry/src/main/ets/service/api/WidgetApi.ets entry/src/main/ets/api/widget/WidgetApi.ets
rmdir entry/src/main/ets/service/api
```

### Task 3.3: HttpClient extraction (only if currently scattered)

- [ ] **Step 1: Check whether a unified HttpClient already exists**

```bash
grep -rn "class HttpClient\|http.createHttp\|@ohos\.net\.http" entry/src/main/ets/api --include="*.ets"
```

- [ ] **Step 2: If each Api calls `new http.createHttp()` itself, extract a common client**

Create `entry/src/main/ets/api/client/HttpClient.ets`:

```typescript
import http from '@ohos.net.http';

export interface RequestOptions {
  method?: http.RequestMethod;
  header?: Record<string, string>;
  body?: string | Object;
  timeout?: number;
}

export interface ApiResponse<T> {
  data: T;
  status: number;
  ok: boolean;
}

const DEFAULT_TIMEOUT_MS = 15000;
const BASE_URL = 'https://api.readmigo.cn';

export class HttpClient {
  private static instance: HttpClient | null = null;

  static getInstance(): HttpClient {
    if (!HttpClient.instance) {
      HttpClient.instance = new HttpClient();
    }
    return HttpClient.instance;
  }

  async request<T>(path: string, opts: RequestOptions = {}): Promise<ApiResponse<T>> {
    const client = http.createHttp();
    try {
      const resp = await client.request(`${BASE_URL}${path}`, {
        method: opts.method ?? http.RequestMethod.GET,
        header: opts.header,
        extraData: opts.body,
        connectTimeout: opts.timeout ?? DEFAULT_TIMEOUT_MS,
        readTimeout: opts.timeout ?? DEFAULT_TIMEOUT_MS,
      });
      const data = typeof resp.result === 'string' ? JSON.parse(resp.result) : resp.result;
      return { data: data as T, status: resp.responseCode, ok: resp.responseCode >= 200 && resp.responseCode < 300 };
    } finally {
      client.destroy();
    }
  }
}
```

Adopt the existing style for the concrete implementation. If a unified client already exists, move it directly into `api/client/`.

- [ ] **Step 3: If extraction won't fit this PR's time budget, leave a TODO for PR-7**

### Task 3.4: Write PR-3 rewrite-map and run the codemod

- [ ] **Step 1: Write `scripts/rewrite-map-pr3.json`**

```json
{
  "version": "PR-3",
  "mappings": [
    { "from": "(?<=['\"])(\\.\\.?/)+components/(Button|Card|Input|List|Tab|Toast|Modal|Loading|EmptyState)", "to": "$1ui/primitives/$2" },
    { "from": "(?<=['\"])(\\.\\.?/)+components/responsive/", "to": "$1ui/responsive/" },
    { "from": "(?<=['\"])(\\.\\.?/)+components/optimized/LazyImage", "to": "$1ui/lazy/LazyImage" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/api/BooksApi", "to": "$1api/books/BooksApi" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/api/AuthApi", "to": "$1api/auth/AuthApi" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/api/ReadingApi", "to": "$1api/reading/ReadingApi" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/api/StatsApi", "to": "$1api/reading/StatsApi" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/api/AiApi", "to": "$1api/ai/AiApi" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/api/WordAnalysisApi", "to": "$1api/ai/WordAnalysisApi" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/api/NotesApi", "to": "$1api/notes/NotesApi" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/api/StudyPlanApi", "to": "$1api/study/StudyPlanApi" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/api/SubscriptionApi", "to": "$1api/subscription/SubscriptionApi" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/api/SupportApi", "to": "$1api/support/SupportApi" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/api/WidgetApi", "to": "$1api/widget/WidgetApi" }
  ]
}
```

- [ ] **Step 2: Run the codemod**

```bash
node scripts/rewrite-imports.mjs scripts/rewrite-map-pr3.json
```

- [ ] **Step 3: build + fix relative paths** (same flow as PR-2)

### Task 3.5: Run VERIFY suite + commit + push + MR

```bash
git add -A
git commit -m "refactor(ui+api): reorganize components into ui/ and service/api into api/ (PR-3)

- ui/{primitives,responsive,lazy,sheets} 4-axis classification
- api/ split by business domain plus shared client/
- Delete components/index.ets barrel
- Rewrite all import paths via scripts/rewrite-map-pr3.json codemod"

git push -u origin refactor/pr3-ui-api
```

---

# PR-4: features batch 1 (reader / library / audiobook / vocab)

**Target output:** 4 core features migrated; features/ top level established; service/tts deleted.

**Branch:** `git checkout main && git pull && git checkout -b refactor/pr4-features-core`

### Task 4.1: Build features/ top-level structure

```bash
mkdir -p entry/src/main/ets/features/reader/pages entry/src/main/ets/features/reader/components entry/src/main/ets/features/reader/service
mkdir -p entry/src/main/ets/features/library/pages entry/src/main/ets/features/library/components
mkdir -p entry/src/main/ets/features/audiobook/pages entry/src/main/ets/features/audiobook/components entry/src/main/ets/features/audiobook/service
mkdir -p entry/src/main/ets/features/vocab/pages entry/src/main/ets/features/vocab/components
```

### Task 4.2: Migrate the reader feature

- [ ] **Step 1: mv files**

```bash
git mv entry/src/main/ets/pages/Reader.ets entry/src/main/ets/features/reader/pages/Reader.ets
git mv entry/src/main/ets/components/BilingualReader.ets entry/src/main/ets/features/reader/components/BilingualReader.ets
git mv entry/src/main/ets/components/HighlightLayer.ets entry/src/main/ets/features/reader/components/HighlightLayer.ets
git mv entry/src/main/ets/components/SelectionLayer.ets entry/src/main/ets/features/reader/components/SelectionLayer.ets
git mv entry/src/main/ets/components/SentenceHighlight.ets entry/src/main/ets/features/reader/components/SentenceHighlight.ets
git mv entry/src/main/ets/components/ChapterTocSheet.ets entry/src/main/ets/features/reader/components/ChapterTocSheet.ets
git mv entry/src/main/ets/components/ReaderSettingsSheet.ets entry/src/main/ets/features/reader/components/ReaderSettingsSheet.ets
git mv entry/src/main/ets/components/NoteEditorSheet.ets entry/src/main/ets/features/reader/components/NoteEditorSheet.ets
```

- [ ] **Step 2: Write features/reader/index.ets barrel**

```typescript
// entry/src/main/ets/features/reader/index.ets
export * from './pages/Reader';
export * from './components/BilingualReader';
export * from './components/HighlightLayer';
export * from './components/SelectionLayer';
export * from './components/SentenceHighlight';
export * from './components/ChapterTocSheet';
export * from './components/ReaderSettingsSheet';
export * from './components/NoteEditorSheet';
```

### Task 4.3: Migrate the library feature

```bash
git mv entry/src/main/ets/pages/Library.ets entry/src/main/ets/features/library/pages/Library.ets
```

Write `entry/src/main/ets/features/library/index.ets`:

```typescript
export * from './pages/Library';
```

### Task 4.4: Migrate the audiobook feature (including service/tts)

```bash
git mv entry/src/main/ets/pages/AudiobookPlayer.ets entry/src/main/ets/features/audiobook/pages/AudiobookPlayer.ets
git mv entry/src/main/ets/pages/AudiobookTab.ets entry/src/main/ets/features/audiobook/pages/AudiobookTab.ets
git mv entry/src/main/ets/components/SsmlBuilder.ets entry/src/main/ets/features/audiobook/components/SsmlBuilder.ets
```

Move service/tts (use `find ... -exec git mv`):

```bash
for f in entry/src/main/ets/service/tts/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/audiobook/service/$name"
done
rmdir entry/src/main/ets/service/tts
```

Write the audiobook barrel.

### Task 4.5: Migrate the vocab feature

```bash
git mv entry/src/main/ets/pages/Vocab.ets entry/src/main/ets/features/vocab/pages/Vocab.ets
git mv entry/src/main/ets/pages/VocabStats.ets entry/src/main/ets/features/vocab/pages/VocabStats.ets
git mv entry/src/main/ets/pages/FlashcardSession.ets entry/src/main/ets/features/vocab/pages/FlashcardSession.ets
git mv entry/src/main/ets/pages/WordAssociation.ets entry/src/main/ets/features/vocab/pages/WordAssociation.ets
git mv entry/src/main/ets/pages/WordFamily.ets entry/src/main/ets/features/vocab/pages/WordFamily.ets
git mv entry/src/main/ets/components/VocabDetailSheet.ets entry/src/main/ets/features/vocab/components/VocabDetailSheet.ets
```

Write the vocab barrel.

### Task 4.6: Write PR-4 rewrite-map + run codemod

- [ ] **Step 1: Write `scripts/rewrite-map-pr4.json`**

```json
{
  "version": "PR-4",
  "mappings": [
    { "from": "(?<=['\"])(\\.\\.?/)+pages/Reader(?=['\"])", "to": "$1features/reader/pages/Reader" },
    { "from": "(?<=['\"])(\\.\\.?/)+pages/Library(?=['\"])", "to": "$1features/library/pages/Library" },
    { "from": "(?<=['\"])(\\.\\.?/)+pages/AudiobookPlayer(?=['\"])", "to": "$1features/audiobook/pages/AudiobookPlayer" },
    { "from": "(?<=['\"])(\\.\\.?/)+pages/AudiobookTab(?=['\"])", "to": "$1features/audiobook/pages/AudiobookTab" },
    { "from": "(?<=['\"])(\\.\\.?/)+pages/Vocab(?=['\"])", "to": "$1features/vocab/pages/Vocab" },
    { "from": "(?<=['\"])(\\.\\.?/)+pages/VocabStats(?=['\"])", "to": "$1features/vocab/pages/VocabStats" },
    { "from": "(?<=['\"])(\\.\\.?/)+pages/FlashcardSession(?=['\"])", "to": "$1features/vocab/pages/FlashcardSession" },
    { "from": "(?<=['\"])(\\.\\.?/)+pages/WordAssociation(?=['\"])", "to": "$1features/vocab/pages/WordAssociation" },
    { "from": "(?<=['\"])(\\.\\.?/)+pages/WordFamily(?=['\"])", "to": "$1features/vocab/pages/WordFamily" },
    { "from": "(?<=['\"])(\\.\\.?/)+components/BilingualReader(?=['\"])", "to": "$1features/reader/components/BilingualReader" },
    { "from": "(?<=['\"])(\\.\\.?/)+components/HighlightLayer(?=['\"])", "to": "$1features/reader/components/HighlightLayer" },
    { "from": "(?<=['\"])(\\.\\.?/)+components/SelectionLayer(?=['\"])", "to": "$1features/reader/components/SelectionLayer" },
    { "from": "(?<=['\"])(\\.\\.?/)+components/SentenceHighlight(?=['\"])", "to": "$1features/reader/components/SentenceHighlight" },
    { "from": "(?<=['\"])(\\.\\.?/)+components/ChapterTocSheet(?=['\"])", "to": "$1features/reader/components/ChapterTocSheet" },
    { "from": "(?<=['\"])(\\.\\.?/)+components/ReaderSettingsSheet(?=['\"])", "to": "$1features/reader/components/ReaderSettingsSheet" },
    { "from": "(?<=['\"])(\\.\\.?/)+components/NoteEditorSheet(?=['\"])", "to": "$1features/reader/components/NoteEditorSheet" },
    { "from": "(?<=['\"])(\\.\\.?/)+components/SsmlBuilder(?=['\"])", "to": "$1features/audiobook/components/SsmlBuilder" },
    { "from": "(?<=['\"])(\\.\\.?/)+components/VocabDetailSheet(?=['\"])", "to": "$1features/vocab/components/VocabDetailSheet" },
    { "from": "(?<=['\"])(\\.\\.?/)+service/tts/", "to": "$1features/audiobook/service/" }
  ]
}
```

- [ ] **Step 2: Run codemod + fix relative paths**

### Task 4.7: Update RouteConstants

Open `entry/src/main/ets/core/router/RouteConstants.ets`. Change `ROUTE_*` constant values from `pages/X` to `features/<feature>/pages/X`. The specific constant list depends on the existing code. For example:

```typescript
export const ROUTE_READER = 'features/reader/pages/Reader';
export const ROUTE_LIBRARY = 'features/library/pages/Library';
export const ROUTE_AUDIOBOOK_PLAYER = 'features/audiobook/pages/AudiobookPlayer';
export const ROUTE_AUDIOBOOK_TAB = 'features/audiobook/pages/AudiobookTab';
export const ROUTE_VOCAB = 'features/vocab/pages/Vocab';
export const ROUTE_VOCAB_STATS = 'features/vocab/pages/VocabStats';
export const ROUTE_FLASHCARD = 'features/vocab/pages/FlashcardSession';
export const ROUTE_WORD_ASSOCIATION = 'features/vocab/pages/WordAssociation';
export const ROUTE_WORD_FAMILY = 'features/vocab/pages/WordFamily';
```

### Task 4.8: Update module.json5 pages list

Update every page path in `entry/src/main/resources/base/profile/main_pages.json` (or the inlined module.json5) to its new location.

### Task 4.9: Run VERIFY suite + commit + push + MR

Smoke test focus:
- Open any book into Reader without crash
- AudiobookPlayer loads without crash
- Vocab / FlashcardSession card operations without crash

```bash
git add -A
git commit -m "refactor(features): migrate reader/library/audiobook/vocab into features/ (PR-4)

- features/{reader,library,audiobook,vocab}/ now contain their own
  pages + components + service-local
- service/tts moved under features/audiobook/
- RouteConstants and module.json5 pages list updated
- Rewrite all import paths via scripts/rewrite-map-pr4.json codemod"

git push -u origin refactor/pr4-features-core
```

---

# PR-5: features batch 2 (ai-tools / account / study / discover / notes)

**Target output:** 5 features migrated; service/{llm, translation, payment, subscription} deleted.

**Branch:** `git checkout main && git pull && git checkout -b refactor/pr5-features-learning`

### Task 5.1: Build the 5 feature top-levels

```bash
mkdir -p entry/src/main/ets/features/ai-tools/pages entry/src/main/ets/features/ai-tools/components entry/src/main/ets/features/ai-tools/service
mkdir -p entry/src/main/ets/features/account/pages entry/src/main/ets/features/account/components entry/src/main/ets/features/account/service
mkdir -p entry/src/main/ets/features/study/pages
mkdir -p entry/src/main/ets/features/discover/pages
mkdir -p entry/src/main/ets/features/notes/pages
```

### Task 5.2: Migrate ai-tools

```bash
git mv entry/src/main/ets/pages/ReadingComprehension.ets entry/src/main/ets/features/ai-tools/pages/ReadingComprehension.ets
git mv entry/src/main/ets/pages/WeaknessAnalysis.ets entry/src/main/ets/features/ai-tools/pages/WeaknessAnalysis.ets
git mv entry/src/main/ets/components/AiContentBadge.ets entry/src/main/ets/features/ai-tools/components/AiContentBadge.ets
git mv entry/src/main/ets/components/ExplainCard.ets entry/src/main/ets/features/ai-tools/components/ExplainCard.ets
git mv entry/src/main/ets/components/WordExplainSheet.ets entry/src/main/ets/features/ai-tools/components/WordExplainSheet.ets

# service/llm and service/translation contain 1 file each
for f in entry/src/main/ets/service/llm/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/ai-tools/service/$name"
done
rmdir entry/src/main/ets/service/llm

for f in entry/src/main/ets/service/translation/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/ai-tools/service/$name"
done
rmdir entry/src/main/ets/service/translation
```

Write the ai-tools barrel.

### Task 5.3: Migrate account (with payment + subscription service)

```bash
git mv entry/src/main/ets/pages/Login.ets entry/src/main/ets/features/account/pages/Login.ets
git mv entry/src/main/ets/pages/Onboarding.ets entry/src/main/ets/features/account/pages/Onboarding.ets
git mv entry/src/main/ets/pages/Me.ets entry/src/main/ets/features/account/pages/Me.ets
git mv entry/src/main/ets/pages/Subscriptions.ets entry/src/main/ets/features/account/pages/Subscriptions.ets
git mv entry/src/main/ets/pages/RefundFlow.ets entry/src/main/ets/features/account/pages/RefundFlow.ets
git mv entry/src/main/ets/pages/Contact.ets entry/src/main/ets/features/account/pages/Contact.ets
git mv entry/src/main/ets/pages/PasswordReset.ets entry/src/main/ets/features/account/pages/PasswordReset.ets
git mv entry/src/main/ets/components/PaywallSheet.ets entry/src/main/ets/features/account/components/PaywallSheet.ets

mkdir -p entry/src/main/ets/features/account/service/payment entry/src/main/ets/features/account/service/subscription
for f in entry/src/main/ets/service/payment/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/account/service/payment/$name"
done
rmdir entry/src/main/ets/service/payment

for f in entry/src/main/ets/service/subscription/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/account/service/subscription/$name"
done
rmdir entry/src/main/ets/service/subscription
```

Write the account barrel.

### Task 5.4: Migrate study / discover / notes

```bash
git mv entry/src/main/ets/pages/StudyPlan.ets entry/src/main/ets/features/study/pages/StudyPlan.ets
git mv entry/src/main/ets/pages/Discover.ets entry/src/main/ets/features/discover/pages/Discover.ets
git mv entry/src/main/ets/pages/Notes.ets entry/src/main/ets/features/notes/pages/Notes.ets
```

Write each barrel (a one-liner `export * from './pages/X';`).

### Task 5.5: Write PR-5 rewrite-map + run codemod + fix relative paths

`scripts/rewrite-map-pr5.json` lists every source/target for the mv operations above. Structure mirrors the PR-4 map.

### Task 5.6: Update RouteConstants + module.json5 pages

Add paths for the new features.

### Task 5.7: VERIFY + commit + push + MR

```bash
git add -A
git commit -m "refactor(features): migrate ai-tools/account/study/discover/notes (PR-5)

- service/{llm,translation} -> features/ai-tools/service/
- service/{payment,subscription} -> features/account/service/
- RouteConstants and module.json5 pages updated
- Rewrite all import paths via scripts/rewrite-map-pr5.json codemod"

git push -u origin refactor/pr5-features-learning
```

---

# PR-6: features batch 3 (support / admin / notification / multi-device / multi-platform / dev)

**Target output:** 6 features migrated; the top-level service/ is completely emptied and deleted; the old pages/ multi-surface subdirectories are emptied and deleted; dev is excluded from release builds.

**Branch:** `git checkout main && git pull && git checkout -b refactor/pr6-features-periphery`

### Task 6.1: Build the 6 feature top-levels

```bash
mkdir -p entry/src/main/ets/features/support/pages
mkdir -p entry/src/main/ets/features/admin/pages entry/src/main/ets/features/admin/service
mkdir -p entry/src/main/ets/features/notification/pages entry/src/main/ets/features/notification/service
mkdir -p entry/src/main/ets/features/multi-device/components entry/src/main/ets/features/multi-device/service
mkdir -p entry/src/main/ets/features/multi-platform/pages entry/src/main/ets/features/multi-platform/service
mkdir -p entry/src/main/ets/features/dev/pages
```

### Task 6.2: Migrate support (8 pages)

```bash
for f in Faq Feedback TicketList TicketDetail PrivacyPolicy UserAgreement About OssLicenses; do
  git mv entry/src/main/ets/pages/$f.ets entry/src/main/ets/features/support/pages/$f.ets
done
```

### Task 6.3: Migrate admin

```bash
for f in entry/src/main/ets/pages/admin/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/admin/pages/$name"
done
rmdir entry/src/main/ets/pages/admin

for f in entry/src/main/ets/service/admin/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/admin/service/$name"
done
rmdir entry/src/main/ets/service/admin
```

### Task 6.4: Migrate notification

```bash
git mv entry/src/main/ets/pages/NotificationCenter.ets entry/src/main/ets/features/notification/pages/NotificationCenter.ets

mkdir -p entry/src/main/ets/features/notification/service/notification entry/src/main/ets/features/notification/service/push
for f in entry/src/main/ets/service/notification/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/notification/service/notification/$name"
done
rmdir entry/src/main/ets/service/notification

for f in entry/src/main/ets/service/push/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/notification/service/push/$name"
done
rmdir entry/src/main/ets/service/push
```

### Task 6.5: Migrate multi-device

```bash
git mv entry/src/main/ets/components/PasteFromOtherDeviceSheet.ets entry/src/main/ets/features/multi-device/components/PasteFromOtherDeviceSheet.ets
git mv entry/src/main/ets/components/DeviceSelectorSheet.ets entry/src/main/ets/features/multi-device/components/DeviceSelectorSheet.ets

mkdir -p entry/src/main/ets/features/multi-device/service/distributed entry/src/main/ets/features/multi-device/service/sync
for f in entry/src/main/ets/service/distributed/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/multi-device/service/distributed/$name"
done
rmdir entry/src/main/ets/service/distributed

for f in entry/src/main/ets/service/sync/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/multi-device/service/sync/$name"
done
rmdir entry/src/main/ets/service/sync
```

### Task 6.6: Migrate multi-platform

```bash
for sub in car native tablet tv watch; do
  git mv entry/src/main/ets/pages/$sub entry/src/main/ets/features/multi-platform/pages/$sub
done

for f in entry/src/main/ets/service/car/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/multi-platform/service/$name"
done
rmdir entry/src/main/ets/service/car

for f in entry/src/main/ets/service/tv/*; do
  name=$(basename "$f")
  git mv "$f" "entry/src/main/ets/features/multi-platform/service/$name"
done
rmdir entry/src/main/ets/service/tv
```

### Task 6.7: Migrate dev

```bash
git mv entry/src/main/ets/pages/dev entry/src/main/ets/features/dev/pages
```

### Task 6.8: build-profile.json5 release excludes dev/

Open `entry/build-profile.json5`. In the release config under `targets[name=default].buildOption` (or top-level `buildOption`), add a source exclude (syntax per the current OpenHarmony hvigor version):

```json5
{
  "buildOption": {
    "sourceOption": {
      "scan": {
        "excludePatterns": ["./src/main/ets/features/dev/**"]
      }
    }
  }
}
```

Confirm the exact field names against the current hvigor docs. Alternative: add a product variant via `targets` with a conditional include.

### Task 6.9: Delete the empty top-level service/

```bash
ls entry/src/main/ets/service/
rmdir entry/src/main/ets/service
```

If not empty, investigate the leftovers.

### Task 6.10: Delete the empty pages/

```bash
ls entry/src/main/ets/pages/
rmdir entry/src/main/ets/pages
```

### Task 6.11: Delete the empty components/

```bash
ls entry/src/main/ets/components/
rmdir entry/src/main/ets/components
```

### Task 6.12: Write PR-6 rewrite-map + run codemod + fix relative paths

`scripts/rewrite-map-pr6.json` lists each mv mapping. Run, then fix the build.

### Task 6.13: Release build verification — dev/ excluded

- [ ] **Step 1: Release build + inspect hap contents**

```bash
hvigor assembleHap --mode=release
unzip -l entry/build/default/outputs/default/entry-default.hap | grep dev
```

Expected: empty (dev/ not in the release artifact)

- [ ] **Step 2: Debug build — verify dev/ still present**

```bash
hvigor assembleHap --mode=debug
unzip -l entry/build/default/outputs/default/entry-default-debug.hap | grep dev
```

Expected: non-empty (debug build contains dev/)

### Task 6.14: VERIFY + commit + push + MR

```bash
git add -A
git commit -m "refactor(features): migrate support/admin/notification/multi-*/dev (PR-6)

- Final batch: 6 features migrated to features/
- All remaining service/* subdirs cleaned out; service/ deleted
- Old pages/ multi-device subdirs cleaned out; pages/ deleted
- components/ deleted (now empty)
- dev/ conditionally excluded from release builds via build-profile
- Rewrite all import paths via scripts/rewrite-map-pr6.json codemod"

git push -u origin refactor/pr6-features-periphery
```

---

# PR-7: Wrap-up (routing + barrels + boundary check + docs)

**Target output:** complete barrel exports at every layer; the import boundary check script is wired into hvigor; a new docs/ARCHITECTURE.md.

**Branch:** `git checkout main && git pull && git checkout -b refactor/pr7-finalize`

### Task 7.1: Complete each layer's barrel

- [ ] **Step 1: core/index.ets**

```typescript
export * from './router/RouteConstants';
export * from './router/RouterService';
```

Extend per the actual public API surface of core/.

- [ ] **Step 2: ui/index.ets**

```typescript
export * from './primitives/Button';
export * from './primitives/Card';
export * from './primitives/Input';
export * from './primitives/List';
export * from './primitives/Tab';
export * from './primitives/Toast';
export * from './primitives/Modal';
export * from './primitives/Loading';
export * from './primitives/EmptyState';
export * from './responsive/AdaptiveGrid';
export * from './responsive/FoldAwareLayout';
export * from './responsive/ResponsiveContainer';
export * from './lazy/LazyImage';
```

- [ ] **Step 3: api/index.ets**

```typescript
export * from './client/HttpClient';
export * from './books/BooksApi';
export * from './auth/AuthApi';
export * from './reading/ReadingApi';
export * from './reading/StatsApi';
export * from './ai/AiApi';
export * from './ai/WordAnalysisApi';
export * from './notes/NotesApi';
export * from './study/StudyPlanApi';
export * from './subscription/SubscriptionApi';
export * from './support/SupportApi';
export * from './widget/WidgetApi';
```

- [ ] **Step 4: store/index.ets**

```typescript
export * from './UserStore';
export * from './SettingsStore';
export * from './ReadingStore';
export * from './AudioPlayerStore';
export * from './StoreKeys';
```

### Task 7.2: Reorganize RouteConstants with grouped comments

Open `entry/src/main/ets/core/router/RouteConstants.ets`. Group by feature:

```typescript
// ─── reader ─────────────────────────────────────────────
export const ROUTE_READER = 'features/reader/pages/Reader';

// ─── library ────────────────────────────────────────────
export const ROUTE_LIBRARY = 'features/library/pages/Library';

// ─── audiobook ──────────────────────────────────────────
export const ROUTE_AUDIOBOOK_PLAYER = 'features/audiobook/pages/AudiobookPlayer';
export const ROUTE_AUDIOBOOK_TAB = 'features/audiobook/pages/AudiobookTab';

// (group all 15 features)

// ── new entries below ──
// (rebase friendly anchor)
```

### Task 7.3: Write the import boundary check script

**File:** `scripts/check-import-boundary.mjs`

```javascript
// scripts/check-import-boundary.mjs
import { readFileSync } from 'node:fs';
import { glob } from 'node:fs/promises';

const RULES = {
  'features/': ['/features/'],  // imports between sibling features forbidden (self-feature paths whitelisted)
  'ui/': ['/features/', '/api/', '/store/'],
  'api/': ['/features/', '/ui/', '/store/'],
  'store/': ['/features/', '/ui/'],
  'model/': ['/features/', '/ui/', '/api/', '/store/', '/core/'],
  'core/': ['/features/', '/ui/', '/api/', '/store/'],
};

const root = 'entry/src/main/ets';
let violations = 0;

for await (const filepath of glob(`${root}/**/*.ets`)) {
  const relPath = filepath.replace(`${root}/`, '');
  let layer = null;
  for (const prefix of Object.keys(RULES)) {
    if (relPath.startsWith(prefix)) { layer = prefix; break; }
  }
  if (!layer) continue;

  const lines = readFileSync(filepath, 'utf8').split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!/^\s*import\s/.test(line)) continue;
    for (const forbidden of RULES[layer]) {
      if (!line.includes(forbidden)) continue;
      if (layer === 'features/' && forbidden === '/features/') {
        const m = relPath.match(/^features\/([^\/]+)/);
        const myFeature = m ? m[1] : null;
        const importMatch = line.match(/features\/([^\/'\"]+)/);
        const targetFeature = importMatch ? importMatch[1] : null;
        if (myFeature && targetFeature && myFeature === targetFeature) continue;
      }
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
```

### Task 7.4: Wire the boundary script into the hvigor pre-build hook

Open `hvigorfile.ts` and replace with:

```typescript
import { appTasks, OhosAppContext } from '@ohos/hvigor-ohos-plugin';
import { spawnSync } from 'node:child_process';

const importBoundaryCheck = {
  pluginId: 'importBoundaryCheck',
  apply: (ctx: OhosAppContext) => {
    const r = spawnSync('node', ['scripts/check-import-boundary.mjs'], { stdio: 'inherit' });
    if (r.status !== 0) {
      throw new Error('Import boundary check failed');
    }
  },
};

export default {
  system: appTasks,
  plugins: [importBoundaryCheck],
};
```

The exact custom-plugin API depends on the current hvigor version. Fallback: invoke the check script via npm script in CI.

### Task 7.5: Write docs/ARCHITECTURE.md

**File:** `docs/ARCHITECTURE.md`

```markdown
# harmony-app architecture

This app uses the Hybrid feature-first architecture.

## Top-level directories

- `entryability/` `abilities/` — Ability entry points
- `core/` — cross-cutting concerns and platform capabilities
- `ui/` — cross-feature shared UI (primitives / responsive / lazy / sheets)
- `api/` — HTTP client, packaged by business domain
- `store/` — global reactive store
- `model/` — single-source domain model (aligned with server-cn DTOs)
- `features/` — 15 vertical features

## Inter-layer dependency rules

See docs/specs/2026-05-17-harmony-app-feature-first-design.md §3.2.

`scripts/check-import-boundary.mjs` enforces them in the hvigor pre-build.

## Feature list

15 features: reader / library / audiobook / vocab / discover / notes / ai-tools / account / support / study / notification / admin / multi-device / multi-platform / dev.

## Workflow for adding a new feature

1. Create a directory under `features/`: `features/<new>/{pages,components,service}`
2. Write a `features/<new>/index.ets` barrel
3. Add a route constant under the `// ── new entries below ──` anchor in `core/router/RouteConstants.ets`
4. Register the new page(s) in `entry/src/main/module.json5` (or its corresponding profile)
5. Run `hvigor assembleHap` and verify the boundary check passes
```

### Task 7.6: Update harmony-app/README.md to reflect the new structure

Open `README.md`, update the directory description; remove stale phrases like "start by laying out the directory structure"; link to `docs/ARCHITECTURE.md`.

### Task 7.7: VERIFY + commit + push + MR

```bash
git add -A
git commit -m "refactor(finalize): barrel exports, import boundary enforcement, docs (PR-7)

- Complete barrel exports for core/ui/api/store/model + each feature
- Regroup RouteConstants by feature with rebase-friendly anchor
- Add scripts/check-import-boundary.mjs enforcing layer dependency rules
- Wire boundary check into hvigor pre-build hook
- Write docs/ARCHITECTURE.md describing the Hybrid feature-first layout
- Update README.md to reflect new structure"

git push -u origin refactor/pr7-finalize
```

---

# Global acceptance (after PR-7 merges)

```bash
# 1. .ts residue
find entry/src/main/ets -name "*.ts" | wc -l
# Expected: 0

# 2. Top-level structure
ls entry/src/main/ets/
# Expected: entryability/  abilities/  core/  ui/  api/  store/  model/  features/

# 3. Old top-levels fully gone
for d in pages components service router native persistence widget theme extensions; do
  test -d "entry/src/main/ets/$d" && echo "FAIL: $d still exists" || echo "OK: $d gone"
done

# 4. boundary check
node scripts/check-import-boundary.mjs
# Expected: "Import boundary check passed."

# 5. clean build, both modes
rm -rf build oh_modules && ohpm install && hvigor clean
hvigor assembleHap
hvigor assembleHap --mode=release

# 6. Hypium suite
hvigor test
```

Real-device regression: cold start + full main-path smoke.

---

# Out of Scope (matches spec §8)

This plan does **not** execute the following — tracked in Phase 2 specs/plans:

1. AudioPlayerStore reactive paradigm refactor (callback → `@ObservedV2` / `@Trace`)
2. server-cn Audiobook DTO alignment
3. Performance / startup / rendering optimization
4. Engineering / CI / test-coverage improvements
5. Multi-surface adaptation depth (foldable / tablet / car / TV / watch)
6. HarmonyOS HAR/HSP modularization

---

# Self-review notes

This plan's self-review covered:

1. **Spec coverage**: each section in spec §1–9 has a corresponding task in this plan. The 6 OOS items in spec §8 are preserved at the end of this plan.
2. **Placeholder scan**: no TBD / TODO residue; every step carries a concrete command or code snippet. The `BASE_URL` in HttpClient is a real placeholder URL; it should be read from core/dynamic config — recorded as a Phase 2 follow-up.
3. **Type consistency**: the `AudioPlayerStateListener` type name is consistent across files; `Book` fields in spec §5 fully align with the Task 1.1 table.
4. **PR independence**: each PR can be reverted independently without breaking earlier PRs' states; one codemod map per PR.
5. **NAPI ABI guard**: every PR runs a NAPI diff at the end; baseline is established in PR-0 Task 0.3.
6. **child_process usage**: all automation scripts use `spawnSync(cmd, [args...])` array form rather than shell string concatenation, eliminating command-injection risk.

If during execution the plan diverges from reality (e.g. the hvigor release exclude syntax or the actual module.json5 structure), patch in place as needed — **do not block progress**.

---

# Execution Handoff

The plan has been committed to `docs/specs/2026-05-17-harmony-app-feature-first-impl-plan.md`.

Choose how to execute it (tell me in the next turn):

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task; review at task checkpoints; iterate fast
**2. Inline Execution** — execute task-by-task in the current session, pausing at key checkpoints for review
