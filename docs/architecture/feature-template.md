# Feature Template — Readmigo HarmonyOS (W1)

> Numbered checklist for adding (or migrating) a feature without violating
> the 4-layer rule (`docs/architecture/layer-contract.md`) or the Intent
> contract (`docs/architecture/intent-contract.md`).

---

## 0. TL;DR

A feature is a directory under `features/<X>/` with **five** mandatory
sub-folders. Each sub-folder maps 1:1 to a layer (L2/L3/L4). Renderers per
SurfaceKind are **optional but recommended**.

```
features/<X>/
  intent/        (L3)  — Intents + typed factories
  viewmodel/     (L3)  — State machine + intent handlers
  service/       (L2)  — HTTP, persistence, domain logic
  pages/         (L4)  — ArkUI page entry
  surfaces/      (L4)  — Per-SurfaceKind renderers (optional)
  components/    (L4)  — Shared sub-components (optional)
  index.ets      — Barrel
```

---

## 1. Steps to add a feature

### Step 1 — create the folder

```
mkdir -p features/<X>/{intent,viewmodel,service,pages,surfaces,components}
touch features/<X>/index.ets
```

### Step 2 — declare intents (L3)

`features/<X>/intent/<X>Intents.ets`:

- Define a discriminated union `type <X>Intent = | … | …` per
  `docs/architecture/intent-contract.md` §1.
- Provide a typed factory object (`<X>Intents.openBook(bookId)`) so
  renderers don't write string literals for `kind`.
- Export `<X>_INTENT_KINDS: ReadonlyArray<string>` so the ViewModel
  constructor can subscribe with one call.

### Step 3 — write the ViewModel (L3)

`features/<X>/viewmodel/<X>ViewModel.ets`:

- Extends `FeatureViewModel<S>` (`core/intent/`).
- `S` is the feature's domain state shape (e.g. `ReaderState`).
- Implement `handle(intent)` with `switch (intent.kind)` narrowing.
- **Only** imports allowed: L2 services, L1 (`core/intent/`,
  `core/distributed-soul/`), L0 (`model/`), `import type` from ArkUI.

### Step 4 — write the Service (L2)

`features/<X>/service/<X>Service.ets`:

- One class, statically constructable (no DI framework).
- Talks to `api/<domain>/`, `store/`, `core/persistence/`.
- Returns plain values / Promises; **does not** publish intents,
  **does not** know about state envelopes.

### Step 5 — write the Page (L4)

`features/<X>/pages/<X>Page.ets`:

- Single `@Component struct` exported as `<X>Page`.
- Constructs `<X>ViewModel` in `aboutToAppear`; calls `onDestroy` in
  `aboutToDisappear`.
- `build()` delegates to `Surface(...)` from `core/surface/`, passing the
  state. **Page does not branch on SurfaceKind.**

### Step 6 — write per-Surface renderers (L4, optional)

`features/<X>/surfaces/{Phone,Tablet,Watch,Car,Tv}Surface.ets`:

- One file per SurfaceKind you support; missing ones fall back per
  `docs/surface-decomposition.md` §2.
- Each file exports `@Builder render<X>OnPhone(state: <X>State)` (or
  equivalent). **No sibling-surface imports.**
- Renderer emits intents via `IntentBus.publish(<X>Intents.foo(args))`.

### Step 7 — register routes

- Add a route constant under the `// ── new entries below ──` anchor in
  `core/router/RouteConstants.ets`.
- Register the page in `entry/src/main/resources/base/profile/main_pages.json`.
- If the feature is the entry point of a new UIAbility (atomic service),
  add it to `module.json5` instead.

### Step 8 — barrel

`features/<X>/index.ets`:

- Re-export the page, the intents typed factory, and the public state
  type. **Do not** re-export the ViewModel or Service (those are
  internal).

### Step 9 — run the checks

```
node harmony-app/scripts/check-import-boundary.mjs
hvigorw assembleHap
```

The first fails on layer violations; the second fails on type errors and
unused imports.

### Step 10 — write the test

`entry/src/ohosTest/ets/test/<X>ViewModel.test.ets`:

- Drive intents through `IntentBus`; assert `vm.state` transitions.
- Stub the service via constructor injection or a module-level seam.

---

## 2. File-by-file mandatory checklist

| File | Layer | Mandatory? | Notes |
|---|---|---|---|
| `features/<X>/intent/<X>Intents.ets` | L3 | yes | Discriminated union + factory + KINDS array |
| `features/<X>/viewmodel/<X>ViewModel.ets` | L3 | yes | Extends `FeatureViewModel<S>` |
| `features/<X>/service/<X>Service.ets` | L2 | yes | One class; statically constructable |
| `features/<X>/pages/<X>Page.ets` | L4 | yes | `@Component struct`; delegates to `Surface(...)` |
| `features/<X>/surfaces/PhoneSurface.ets` | L4 | recommended | Falls back to default renderer if absent |
| `features/<X>/surfaces/TabletSurface.ets` | L4 | optional | Required only if W11 ships Tablet support for this feature |
| `features/<X>/surfaces/WatchSurface.ets` | L4 | optional | Required for `multi-device` features only |
| `features/<X>/surfaces/CarSurface.ets` | L4 | optional | W13+ |
| `features/<X>/surfaces/TvSurface.ets` | L4 | optional | W13+ |
| `features/<X>/components/*.ets` | L4 | optional | Shared sub-components used by multiple surfaces |
| `features/<X>/index.ets` | — | yes | Barrel; re-exports public surface only |
| `entry/src/ohosTest/ets/test/<X>ViewModel.test.ets` | test | yes | Drives intents, asserts state |

---

## 3. Smallest possible feature (cheat-sheet)

For a stub feature (no UI yet) you can stop at:

```
features/<X>/
  intent/<X>Intents.ets       (define one intent kind)
  viewmodel/<X>ViewModel.ets  (handle that intent, set state.data)
  service/<X>Service.ets      (one method returning a fixture)
  pages/<X>Page.ets           (renders state.status === 'data' ? Text : Skeleton)
  index.ets
```

5 files. CI passes. You can land it before the surfaces/components exist.

---

## 4. Migrating an existing feature (W1 only)

For the 5 W1 features (reader, discover, library, account, audiobook), the
service/, pages/, components/ directories already exist from the pre-W1
hybrid-feature-first refactor. The migration is **additive**:

1. **Do not** rename/move existing service/, pages/, components/.
2. Add `features/<X>/intent/` and `features/<X>/viewmodel/`.
3. Move state-machine code from the existing service into the new
   ViewModel; the service should end up data-fetching only.
4. Rewrite `pages/<X>Page.ets`'s `build()` to delegate to
   `Surface(state)` instead of constructing the layout inline. Keep the
   `@Component` shell.
5. Re-export the new intents via `index.ets`.

The boundary checker's existing exceptions still apply — see
`scripts/check-import-boundary.mjs` `CROSS_FEATURE_ALLOW`.

---

## 5. Forbidden patterns

| # | Pattern | Detected by | Why forbidden |
|---|---|---|---|
| F-1 | Cross-feature import (`features/X` → `features/Y`) outside `CROSS_FEATURE_ALLOW` | boundary checker `RULE-no-feature-cross` | Couples release cadence; breaks bundle split (`docs/bundle-strategy.md`) |
| F-2 | ArkUI runtime import inside `features/<X>/viewmodel/` | boundary checker `W1-2` (`RULE-L3-no-arkui-runtime`) | VMs must be renderer-agnostic so all 5 SurfaceKinds share one VM |
| F-3 | `@ohos.data.distributedDataObject` outside `core/distributed-soul/` | boundary checker `W1-1` (`RULE-L1-Soul-exclusive`) | Splits LWW conflict resolution; see `docs/distributed-soul.md` §3 |
| F-4 | Mutating an Intent after `publish()` (e.g. `intent.payload.foo = …`) | code review (intents are `Object.freeze`d at construction) | Subscribers see a race; violates discriminated-union narrowing assumptions |
| F-5 | Service call directly inside ArkUI `build()` (e.g. `Text(svc.fetchTitle())`) | code review | Blocks frame; loses error handling; bypasses the state envelope |
| F-6 | `if (kind === SurfaceKind.Phone) { … } else { … }` inside a single renderer | code review | Defeats the point of surface decomposition; split into `PhoneSurface.ets` and `TabletSurface.ets` |
| F-7 | ViewModel branches on `intent.source` for business logic | code review | Surface routing is SurfaceRegistry's job, not the VM's; see `intent-contract.md` §7 |
| F-8 | `import { router } from '@ohos.arkui.router'` inside a ViewModel | boundary checker `RULE-L3-no-arkui-runtime` | Navigation is an Intent; the router subscribes to `nav.*` |
| F-9 | Service publishes Intents | code review | Inverts the L4 → L3 → L2 dataflow; services return values |
| F-10 | More than 13 project-local imports in one file | boundary checker `RULE-fanout-13` (advisory until W22) | Empirically correlates with files too big to lazy-load |

---

## 6. Cross-references

- `docs/architecture/layer-contract.md` — full RULE-IDs the boundary
  checker emits.
- `docs/architecture/intent-contract.md` — intent shape, bus semantics,
  state envelope.
- `docs/surface-decomposition.md` — when to add per-Surface renderers.
- `docs/distributed-soul.md` — when a feature owns cross-device state.
- `docs/bundle-strategy.md` — which HSP your feature lives in.
- `docs/performance-budget.md` — page-level budgets your renderer must
  respect.
