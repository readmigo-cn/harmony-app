# harmony-app

The `HarmonyOS NEXT` main application, built on the **Hybrid feature-first architecture**. Full design and inter-layer dependency rules live in
[`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md).

## Module layout at a glance

Under `entry/src/main/ets/`, the codebase is split into the following layers:

| Layer | Contents |
|---|---|
| `entryability/` / `abilities/` | Ability entry points |
| `core/` | Cross-cutting concerns (router / shell / native / persistence / widget / theme, etc.) |
| `ui/` | Cross-feature shared UI (primitives / responsive / lazy) |
| `api/` | HTTP client + REST APIs grouped by business domain |
| `store/` | Global reactive stores (UserStore / SettingsStore / ReadingStore / AudioPlayerStore) |
| `model/` | Single-source domain models (aligned with server-cn DTOs) |
| `features/` | 15 vertical features (reader / library / audiobook / vocab / discover / notes / ai-tools / account / support / study / notification / admin / multi-device / multi-platform / dev) |

Inter-layer dependencies are enforced by `scripts/check-import-boundary.mjs` during the hvigor pre-build step.

## Page semantics currently aligned

Page semantics are aligned with `readmigo-repos/mobile`, covering:

- Reading chain: `Login` / `Onboarding` / `Discover` / `Library` / `Reader` / `Me`
- Learning aids: `Notes` / `Vocab` / `FlashcardSession` / `ReadingComprehension` / `StudyPlan` / `WordAssociation` / `WordFamily` / `VocabStats` / `WeaknessAnalysis`
- Account & service: `Subscriptions` / `RefundFlow` / `Contact` / `PasswordReset`
- Support / system: `Feedback` / `TicketList` / `TicketDetail` / `Faq` / `About` / `UserAgreement` / `PrivacyPolicy` / `OssLicenses` / `NotificationCenter`
- Multi-surface: `AudiobookTab` / `AudiobookPlayer` / Watch / Tablet sub-layouts
- Developer: `XComponentDemo` / `ComponentGallery`

## Still required for Huawei backend onboarding

- `entry/agconnect-services.json`
- Signing certificate
- Actual `bundleName`
- Actual SDK version numbers
