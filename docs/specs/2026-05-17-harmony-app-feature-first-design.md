# harmony-app Feature-First architecture refactor — design

- **Status**: Draft (awaiting final user approval)
- **Date**: 2026-05-17
- **Scope**: `harmony-app/` only (does not touch badge-engine / typesetting / napi-bridge / llm-adapter / server-cn / infra-cn)
- **Expected output**: 7 PRs, ~5–7 working days, single-person pace
- **Methodology entry**: generated via Claude superpowers `brainstorming` skill; subsequent implementation plan produced by the `writing-plans` skill

---

## 1. Problem statement

harmony-app (Readmigo CN, HarmonyOS NEXT, ~50k lines of ArkTS) currently has a **horizontal layered** structure:

```
entry/src/main/ets/
├── pages/        17k lines / 38+ files (flat top level + 7 surface-adapter subdirs interleaved)
├── service/      14k lines / 22 subdirectories (9 are "single-file directories")
├── components/   10k lines / 24 top-level components + responsive/(3) + optimized/(1) + index.ets barrel (inconsistent classification axis)
├── store/        4 files, `.ts` and `.ets` mixed
├── model/        7 files, `Book.ts` and `Book.ets` coexist with the same name and incompatible fields
├── persistence/  DatabaseManager + RdbOrm + repositories/
├── router/       trio (including over-abstracted RouterAdapter)
├── native/  widget/  theme/  abilities/  extensions/  entryability/
```

### Identified core debt

1. **`.ts` / `.ets` dual-track leftovers** — `Book.ts`, `Audiobook.ts`, and `store/AudioPlayerStore.ts` are `.ts` leftovers copied from overseas mobile; `Book.ts` and `Book.ets` schemas are incompatible (slug/cefrLevel only in .ets; series/list types only in .ts; `UserBook` fields reveal traces of two reader implementations).
2. **service layer over-fragmented** — 9 of 22 subdirectories are single-file directories (admin/car/dynamic/experiments/llm/storage/translation/tts/tv); abstraction cost without corresponding encapsulation benefit.
3. **components classification axes mixed** — `responsive/` (by scenario) and `optimized/` (by characteristic) don't align; `optimized/` has only 1 file.
4. **pages top-level flat + subdirectory mix** — among 38 pages, some are flat and others are in admin/atomic/car/native/tablet/tv/watch subdirs.
5. **Cross-directory jump hell from horizontal layering** — modifying one feature requires bouncing between pages/components/service/store/model 5 directories.
6. **router over-abstraction** — RouteConstants + RouterAdapter + RouterService trio is redundant for 529 total lines.
7. **Implicit paradigm bug** (**out of scope for this refactor**, recorded for Phase 2) — `AudioPlayerStore` uses callback subscribe; ArkUI `@State` doesn't subscribe to it, so UI won't rebuild on state changes.

### Optimization axis

The user has explicitly chosen: **single axis = architecture / code organization cleanup** (not performance, engineering, multi-surface adaptation — those are separate initiatives); intervention depth = **major refactor (6–8 PRs)**, using a feature-first approach.

---

## 2. Approach selection

Three feature-first routes compared:

| Approach | Description | Trade-offs |
|---|---|---|
| **A. Pure feature-first** | features/ fully autonomous; cross-cutting goes through platform/ and shared/ | Shared model/store/API ownership is unclear; shared/ tends to balloon into an unnamed horizontal layer |
| **B. Hybrid (recommended)** | features/ self-contained + core/ui/api/store/model explicit horizontal layers | Matches current code reality; acknowledges horizontal layers' true necessity and slims them down |
| **C. HarmonyOS HAR/HSP multi-module** | Each feature split into a HAR submodule, physically isolated | hvigor configuration cost is high; current scaffolding maturity insufficient; premature |

**Adopted approach: B (Hybrid)**. Reasoning:
- Main pain points are horizontal-layer chaos + .ts/.ets dual track + service over-fragmentation; B addresses all of them.
- 6–8 PR granularity naturally aligns with B's work breakdown.
- No hvigor multi-module configuration changes; rollback remains feasible.
- If a local feature genuinely needs independent packaging later, upgrade to C; do not pay that cost upfront.

---

## 3. Target architecture

### 3.1 Directory tree

```
entry/src/main/ets/
├── entryability/             [unchanged] EntryAbility entry point
├── abilities/                [unchanged] other Abilities
│
├── core/                     # Cross-cutting concerns and platform capabilities
│   ├── router/               ← original router/ trio; deletes RouterAdapter.ets
│   ├── shell/                ← original pages/Index.ets moved in (App skeleton / TabBar)
│   ├── native/               ← original native/ NAPI call layer
│   ├── persistence/          ← original persistence/ + original service/storage (thin shell merged in)
│   ├── widget/               ← original widget/ cards
│   ├── theme/                ← original theme/
│   ├── extensions/           ← original extensions/
│   ├── analytics/            ← original service/analytics
│   ├── monitoring/           ← original service/monitoring
│   ├── performance/          ← original service/performance
│   ├── cache/                ← original service/cache
│   ├── experiments/          ← original service/experiments
│   ├── moderation/           ← original service/moderation
│   ├── dynamic/              ← original service/dynamic (dynamic config)
│   └── atomic/               ← original service/atomic (atomic-service runtime support)
│
├── ui/                       # Cross-feature shared UI components
│   ├── primitives/           ← Button/Card/Input/List/Tab/Toast/Modal/Loading/EmptyState
│   ├── responsive/           ← AdaptiveGrid/FoldAwareLayout/ResponsiveContainer
│   ├── lazy/                 ← LazyImage (original components/optimized/)
│   └── sheets/               ← cross-feature generic Sheets
│
├── api/                      # Unified HTTP/API client, packaged by business domain
│   ├── client/               ← HttpClient + interceptors + normalized errors
│   ├── books/  auth/  reading/  ai/  notes/  study/  subscription/  support/  widget/
│
├── store/                    # Global reactive store (unified .ets)
│   ├── UserStore.ets         SettingsStore.ets  ReadingStore.ets
│   ├── AudioPlayerStore.ets  ← de-.ts'd (filename/syntax only; paradigm bug deferred to Phase 2)
│   └── StoreKeys.ets
│
├── model/                    # Single-source domain models, aligned with server-cn DTOs
│   ├── Book.ets              ← single Book schema (merged from Book.ts + Book.ets)
│   ├── Audiobook.ets         ← de-.ts'd
│   ├── Chapter.ets / ReadingProgress.ets / Highlight.ets / ExplainData.ets
│   └── index.ets             ← barrel
│
└── features/                 # 15 features, each containing pages + components + service-local
    ├── reader/
    ├── library/
    ├── audiobook/
    ├── vocab/
    ├── discover/
    ├── notes/
    ├── ai-tools/
    ├── account/
    ├── support/
    ├── study/
    ├── notification/
    ├── admin/
    ├── multi-device/
    ├── multi-platform/
    └── dev/                  ← conditionally excluded from release builds
```

### 3.2 Inter-layer dependency constraints (enforced)

| Layer | May import | Forbidden imports |
|---|---|---|
| `features/<X>/` | `core/*`, `ui/*`, `api/*`, `store/*`, `model/*` | **other `features/<Y>/`** (cross-feature must go through store/api) |
| `api/<domain>/` | `core/native`, `model/*` | `features/*`, `ui/*`, `store/*` |
| `store/` | `api/*`, `core/persistence`, `model/*` | `features/*`, `ui/*` |
| `model/` | (pure types, zero dependencies) | any runtime module |
| `ui/` | `core/theme`, `core/router` (types), `model/*` (types) | `features/*`, `api/*`, `store/*` |
| `core/` | sibling modules within core | `features/*`, `ui/*`, `api/*`, `store/*` |

**Enforcement**: `tools/check-import-boundary.ts` is wired into the hvigor pre-build hook; violations fail the build. See §6.7.

### 3.3 Key tightening points

- The original 22 service subdirectories: **0 leftovers** — 9 sunk into core/, 1 HTTP client lifted into api/, 12 feature-local moved into features/X/service/, 1 storage thin-shell merged into core/persistence.
- Original components flat + responsive/optimized mess → ui/{primitives, responsive, lazy, sheets} four subdirectories, single classification axis (by UI role).
- router trio → duo: keep `RouteConstants` + `RouterService`; **delete RouterAdapter.ets**.
- Single-source model: delete `Book.ts`; `Audiobook.ts → .ets`; `AudioPlayerStore.ts → .ets`. **Zero `.ts` files under ets/** as a hard acceptance criterion.

---

## 4. Feature split inventory (15)

| Feature | Pages (moved from pages/) | Components (moved from components/) | service-local (moved from service/) |
|---|---|---|---|
| **reader** | `Reader.ets` | BilingualReader / HighlightLayer / SelectionLayer / SentenceHighlight / ReaderSettingsSheet / ChapterTocSheet / NoteEditorSheet | — |
| **library** | `Library.ets` | — | — |
| **audiobook** | `AudiobookPlayer` / `AudiobookTab` | SsmlBuilder | `tts` |
| **vocab** | `Vocab` / `VocabStats` / `FlashcardSession` / `WordAssociation` / `WordFamily` | VocabDetailSheet | — |
| **discover** | `Discover` | — | — |
| **notes** | `Notes` | — | — |
| **ai-tools** | `ReadingComprehension` / `WeaknessAnalysis` | AiContentBadge / ExplainCard / WordExplainSheet | `llm` / `translation` |
| **account** | `Login` / `Onboarding` / `Me` / `Subscriptions` / `RefundFlow` / `Contact` / `PasswordReset` | PaywallSheet | `payment` / `subscription` |
| **support** | `Faq` / `Feedback` / `TicketList` / `TicketDetail` / `PrivacyPolicy` / `UserAgreement` / `About` / `OssLicenses` | — | — |
| **study** | `StudyPlan` | — | — |
| **notification** | `NotificationCenter` | — | `notification` / `push` |
| **admin** | `pages/admin/*` | — | `admin` |
| **multi-device** | — | PasteFromOtherDeviceSheet / DeviceSelectorSheet | `distributed` / `sync` |
| **multi-platform** | `pages/{car, native, tablet, tv, watch}/*` | — | `car` / `tv` |
| **dev** | `pages/dev/*` | — | — |

### Decision points

- `AudioPlayerStore` / `ReadingStore` stay in global `store/` (used by multiple features).
- `discover` / `study` are currently single-page / single-module but remain independent features (room reserved for future expansion).
- `dev` conditionally excluded in the `build-profile.json5` release variant.

---

## 5. Single-source model strategy

### 5.1 Book.ets merge rules (route 1 = server-cn DTO is authoritative)

| Field | Decision | Source |
|---|---|---|
| `id` / `title` / `author` / `language` | required | identical across both versions |
| `slug` | required | .ets / server-cn |
| `cefrLevel` | optional | .ets / server-cn |
| `authorId` | optional | .ts (kept for overseas) |
| `difficultyScore` | optional | .ts (coexists with .ets `difficulty`) |
| `coverUrl` / `description` / `category` / `wordCount` | **optional** (relaxed) | .ets style |
| `hasAudiobook` / `audiobookId` | optional, **placed on Book** (not BookDetail) | .ets |
| `BookDetail.epubUrl / chapters / aiScore / seriesId / seriesName / seriesPosition / seriesBookCount` | optional | .ts (kept) |
| `BookFilters` / `BookListResponse` / `Rating` | kept | .ets |
| `BookList` / `BookListBook` / `BookListType` (rankings) | kept | .ts (preserved per product roadmap) |
| `UserBook.currentChapterIndex` | optional | .ets (native reader) |
| `UserBook.currentCfi` | optional | .ts (epub.js reader; **kept** for future dual-reader compatibility) |
| `UserBook.addedAt/lastReadAt` type | `string` (ISO) | .ets |

### 5.2 Audiobook.ts conversion

- Rename directly `.ts → .ets`
- ArkTS syntax compatibility fixes (`export const` initialization order; `import type` → `import` depending on ArkTS version)
- **Follow-up**: recommend that the server-cn team align this Audiobook DTO (currently missing on backend).

### 5.3 AudioPlayerStore.ts conversion (**two phases**)

- **Phase 1 (this scope)**: filename only `.ts → .ets`; `import type` → `import`; extract callback arrays into a named type `type StateListener = (s: AudioPlayerStore) => void`. **Retain the callback subscribe pattern.**
- **Phase 2 (out of scope here)**: reactive paradigm refactor — migrate to `@ObservedV2` + `@Trace` or `AppStorage` so ArkUI components can subscribe directly via `@StorageLink` / `@Watch`. Tracked in a separate spec/PR.

### 5.4 Acceptance

- `find entry/src/main/ets -name "*.ts" | wc -l` = 0
- `grep -r "from '.*Book\.ts'" entry/src/main/ets` 0 hits
- `model/Book.ets`, `model/Audiobook.ets`, `store/AudioPlayerStore.ets` are the sole copies
- `model/index.ets` barrel regenerated

---

## 6. PR slicing (7 PRs, ordered by dependency)

### Dependency graph

```
PR-1 model + .ts cleanup
  └→ PR-2 core/ base + cross-cutting sink
       └→ PR-3 ui/ + api/ reshuffle
            └→ PR-4 features batch 1 (reader/library/audiobook/vocab)
                 └→ PR-5 features batch 2 (ai-tools/account/study/discover/notes)
                      └→ PR-6 features batch 3 (support/admin/notification/multi-device/multi-platform/dev)
                           └→ PR-7 wrap-up (routing + barrels + boundary check)
```

### 6.1 PR-1: single-source model + eliminate .ts leftovers

- Merge `Book.ts` → `Book.ets`; delete `Book.ts`; de-.ts'd Audiobook and AudioPlayerStore (Phase 1)
- Repo-wide import rewrite
- New `model/index.ets` barrel
- Estimate: ~600 lines of substantive change + ~200 import rewrites; 0.5 day
- Acceptance: 0 `.ts` files; hvigor clean build passes; Hypium unit tests pass; cold start + 5-main-tab smoke OK

### 6.2 PR-2: core/ base + cross-cutting service sink

- Create `core/` top level; 6 existing horizontal dirs moved in (`router/native/persistence/widget/theme/extensions/`)
- 9 cross-cutting service subdirs moved into core/ (cache/monitoring/performance/analytics/experiments/moderation/dynamic/atomic + storage merged into persistence)
- Delete `core/router/RouterAdapter.ets` (grep first to confirm 0 references)
- `pages/Index.ets` → `core/shell/Index.ets`
- Repo-wide import rewrite
- Estimate: ~3500 lines; 0.5–1 day
- Acceptance: old top-level router/native/etc. gone; service/ still exists (remaining 13 feature-local subdirs handled later); hvigor passes; smoke OK

### 6.3 PR-3: ui/ and api/ reshuffle

- 28 components (24 top-level + responsive/3 + optimized/1, delete index.ets barrel) reclassified into `ui/{primitives, responsive, lazy, sheets}` or sunk into features/X/components/
- 11 `service/api/` files split by business domain into `api/{books, auth, reading, ai, notes, study, subscription, support, widget}`
- Extract `api/client/HttpClient.ets` (if scattered, unify)
- Delete `components/index.ets`
- Estimate: ~3000 lines; 0.5–1 day
- Acceptance: top-level `components/` and `service/api/` directories disappear

### 6.4 PR-4: features batch 1 (core reading)

- reader / library / audiobook / vocab — move pages + components + service-local + individual barrels into each feature
- service/tts moved into features/audiobook/
- Routing table updated
- Estimate: ~5500 lines (reader has large components); 1–1.5 days
- Acceptance: 4 features reachable via their paths; service/tts deleted; cold start + Reader main path smoke OK

### 6.5 PR-5: features batch 2 (learning + account)

- ai-tools / account / study / discover / notes — 5 features
- service/{llm, translation, payment, subscription} moved into corresponding features
- Estimate: ~4500 lines; 1 day
- Acceptance: service/{llm, translation, payment, subscription} deleted

### 6.6 PR-6: features batch 3 (periphery + multi-surface + dev)

- support / admin / notification / multi-device / multi-platform / dev — 6 features
- service/{admin, notification, push, distributed, sync, car, tv} moved in
- Add `excludes` for dev in `build-profile.json5` release variant
- Estimate: ~3500 lines; 1 day
- Acceptance: **at this point the old top-level service/ is empty**, delete it; delete old pages/{admin,car,native,tablet,tv,watch,dev}/

### 6.7 PR-7: wrap-up (routing + barrels + boundary check)

- `core/router/RouteConstants.ets` fully reorganized (grouped by feature with comments)
- Complete `index.ets` barrels at every layer and feature
- Add `tools/check-import-boundary.ts` script: walk ets files, validate cross-layer import rules, exit 1 on violation
- hvigor config: wire pre-build hook
- Delete `entry/src/main/ets/pages/` (Index moved out)
- Delete all remaining empty directories
- Update `harmony-app/README.md` + create `docs/ARCHITECTURE.md`
- Estimate: ~1500 lines; 0.5 day
- Acceptance: 0 top-level `pages/components/service/`; boundary script passes; README reflects current reality

### Total effort

**~5–7 working days / single-person pace**.

---

## 7. Risk mitigation

### 7.1 Codemod script (must be built first)

- Location: `scripts/rewrite-imports.mjs`
- Input: `scripts/rewrite-map.json`, maintained per PR
- Implementation: Node.js + simple regex (avoid ts-morph to prevent ArkTS decorator parsing failures)
- Scope: `entry/src/main/ets/**/*.ets` + `entry/src/ohosTest/**/*.ets`
- **Forced skip**: any `from 'lib*.so'` NAPI ABI imports
- Run + clean-build verify in every PR

### 7.2 In-flight build protection

- Mandatory `git mv` (preserve git history)
- Within a single PR: mv → codemod → clean-build verify → fix residue → squash into 1 commit. No broken intermediate commits allowed.
- Before merging each PR: `rm -rf build oh_modules && pnpm install && hvigor build` full rebuild

### 7.3 Rollback playbook

- PR-1 schema causes NPE: revert the single PR; recommend **24h observation** after merge before opening PR-2
- PR-2/3 build breakage: revert the single PR
- PR-4/5/6 a feature crashes after move: revert that PR; other completed features are unaffected (features are decoupled via store/api)
- PR-7 boundary script false positives: temporarily detach the hvigor hook and patch separately
- Hard rule: any single revert must return the repo to a buildable state

### 7.4 PR-1 schema compatibility detail

- Before running the codemod, scan usage sites: `grep -rn "book\.coverUrl\|book\.description\|book\.category\|book\.wordCount" entry/src/main/ets`
- For each usage site, add scenario-appropriate null guards: `book.coverUrl ?? ''`, `book.wordCount ?? 0`, `book.coverUrl?.startsWith(...)`
- Include guard diffs in PR-1 itself to avoid downstream pollution

### 7.5 Routing table / build-profile.json5 merge-conflict protection

- PR-4/5/6 run serially (no parallel openings allowed)
- New `RouteConstants` entries are pinned after the `// ── new entries below ──` anchor, easing rebases

### 7.6 Hypium unit-test sync

- Each PR's codemod also rewrites test imports
- String-literal mock paths in tests are scanned and listed as candidates separately
- Unit-test coverage as a gate per PR

### 7.7 NAPI / native ABI invariance

- `core/native/` `import x from 'lib*.so'` cannot be touched by the codemod (script explicit skip)
- After PR-2 completes, diff verify: `grep -rn "from 'lib.*\.so'" core/native/` must match before and after

### 7.8 dev/ release-build exclusion verification

- In PR-6, add `excludes: ["./features/dev/**"]` to the `build-profile.json5` release variant
- Mandatory: run `hvigor assembleHap --mode=release` and `unzip -l *.hap | grep dev` to verify dev/* is absent from the artifact
- Verify dev/ still present in debug build (no accidental kill)

### 7.9 Pre-merge gate checklist (per PR)

```
□ 1. hvigor clean build passes (always clean, don't rely on incremental cache)
□ 2. Hypium full unit-test suite passes
□ 3. Real-device cold start + 5-main-tab smoke runs without anomalies
□ 4. .ts file count under ets/ = 0 (sustained after PR-1)
□ 5. No broken imports left after codemod
□ 6. NAPI .so imports unchanged (diff before/after)
□ 7. Mock paths in test code updated in sync
□ 8. Routing table entries complete (matches features/X/pages/ count)
□ 9. Single PR's git log = 1 commit only
□ 10. PR description includes the change surface + acceptance list + rollback command
```

---

## 8. Out of Scope / Follow-ups

This refactor **does not include** the following — tracked in separate specs/issues:

1. **AudioPlayerStore reactive paradigm refactor** — callback subscribe → `@ObservedV2` + `@Trace` or `AppStorage`. The current callback pattern is not subscribed to by ArkUI `@State`, so UI doesn't automatically rebuild on state changes. This refactor only does `.ts → .ets` filename + syntax compatibility, **behavior preserved**.
2. **server-cn Audiobook DTO alignment** — backend currently lacks an Audiobook module. Recommend that the server-cn team align with `model/Audiobook.ets`.
3. **Performance / startup / rendering optimization** — user explicitly excluded from this scope.
4. **Engineering / CI / test-coverage improvements** — same as above.
5. **Multi-surface adaptation depth (foldable / tablet / car / TV / watch)** — same as above.
6. **HarmonyOS HAR/HSP modularization** — deferred until a feature genuinely needs independent packaging.

---

## 9. Total acceptance

Global acceptance after the 7 PRs are complete:

- `find entry/src/main/ets -name "*.ts" | wc -l` = **0**
- The top level of `entry/src/main/ets/` contains only: `entryability/  abilities/  core/  ui/  api/  store/  model/  features/`
- Old top-level `pages/  components/  service/  router/  native/  persistence/  widget/  theme/  extensions/` all gone or sunk
- `tools/check-import-boundary.ts` runs in the hvigor pre-build hook; imports violating layer dependency rules fail the build
- `hvigor clean build` + release build both pass
- Full Hypium unit-test suite passes
- Real-device cold start + full main-path smoke OK
- `docs/ARCHITECTURE.md` reflects the new structure

---

## 10. Next steps

- User reviews this spec → upon approval, enter the `superpowers:writing-plans` skill
- writing-plans produces `docs/specs/2026-05-17-harmony-app-feature-first-impl-plan.md`, listing concrete steps, verification commands, and time estimates per PR
- Implementation proceeds in PR-1 → PR-7 order; each PR requires final user confirmation before merge (per the CLAUDE.md "output a plan for me to review before modifying code" rule)
