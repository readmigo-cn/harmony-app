# harmony-app architecture

This app uses the **Hybrid feature-first architecture**, introduced during the 2026-05-17 refactor (PR-0 ~ PR-7).

## Top-level directories

`entry/src/main/ets/`:

- `entryability/` `abilities/` — Ability entry points
- `core/` — Cross-cutting concerns and platform capabilities (router / shell / native / persistence / widget / theme / extensions / analytics / monitoring / performance / cache / experiments / moderation / dynamic / atomic)
- `ui/` — Cross-feature shared UI (primitives / responsive / lazy / sheets)
- `api/` — HTTP client, packaged by business domain (client / books / auth / reading / ai / notes / study / subscription / support / widget)
- `store/` — Global reactive stores (UserStore / SettingsStore / ReadingStore / AudioPlayerStore)
- `model/` — Single-source domain models (aligned with server-cn DTOs)
- `features/` — 15 vertical features:
  - reader / library / audiobook / vocab — core reading chain
  - discover / notes / ai-tools — learning aids
  - account / support / study — account & service
  - notification / admin — system capabilities
  - multi-device / multi-platform — HarmonyOS ecosystem adaptation
  - dev — developer tools (conditionally excluded in release builds)

## Inter-layer dependency rules

| Layer | May import | Forbidden imports |
|---|---|---|
| `features/<X>/` | core, ui, api, store, model | other `features/<Y>/` (cross-feature goes through store/api; exceptions below) |
| `api/<domain>/` | core/native, model | features, ui, store (`api/client/` may read store to fetch auth token) |
| `store/` | api, core/persistence, model | features, ui |
| `model/` | — | any runtime module |
| `ui/` | core/theme, model (types only) | features, api, store |
| `core/` | sibling modules within core | features, ui, api, store (composition root exceptions below) |

`scripts/check-import-boundary.mjs` enforces these rules during the hvigor pre-build step.

### Exception whitelist

The following paths are explicitly allowed by the boundary script for "composition root / engineering reality" reasons:

| Source path | Allowed imports |
|---|---|
| `core/shell/` | features, ui, store, api (app composition root) |
| `core/widget/` | api, store, features (Widget ExtensionAbility is an independent runtime entity) |
| `core/router/` | store (auth-guard reads UserStore) |
| `core/theme/` | store (ThemeService persists user preferences) |
| `core/experiments/` | store (reads user group) |
| `api/client/` | store (interceptor reads token from UserStore) |

### Allowed cross-feature dependencies

A few inter-feature dependencies are legitimate and explicitly declared in the script:

- `reader` → `ai-tools` / `audiobook` / `multi-device`: trigger word explanation, read-aloud, and device handoff while reading
- `vocab` → `ai-tools` / `audiobook` / `multi-device`: SRS review uses explanation cards / TTS / clipboard
- `multi-platform` → `ai-tools` / `notes`: multi-surface layouts aggregate capabilities across features
- `multi-device` → `notes` / `multi-platform`: distributed sync writes notes / watch surface display

Future work: move shared components (e.g. ExplainCard / WordExplainSheet) down into `ui/sheets/` to further reduce cross-feature dependencies.

## Workflow for adding a new feature

1. `mkdir -p features/<new>/{pages,components,service}`
2. Write a `features/<new>/index.ets` barrel
3. Add route constants under the `// ── new entries below ──` anchor in `core/router/RouteConstants.ets`
4. Register new pages in `entry/src/main/resources/base/profile/main_pages.json`
5. Run `hvigor assembleHap` and verify the import boundary check passes

## Historical specs & plans

- Design: `docs/specs/2026-05-17-harmony-app-feature-first-design.md`
- Implementation plan: `docs/specs/2026-05-17-harmony-app-feature-first-impl-plan.md`

## Phase 2 follow-ups (unrelated to the refactor, tracked separately)

- AudioPlayerStore reactive refactor (callback → @ObservedV2 / @Trace)
- Align with server-cn Audiobook DTO
- Performance / startup / rendering optimizations
- Physical HarmonyOS HAR/HSP modularization
- Move cross-feature shared UI into `ui/sheets/` to shrink the whitelist
