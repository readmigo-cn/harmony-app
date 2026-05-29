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

## Release

For releasing v0.1.0 to AppGallery Connect, follow the **[Release Setup Guide](./docs/release-setup.md)**. The 6-step checklist covers AGC registration, signing certificates, config injection, and build verification.

**Pre-release verification:**
```bash
bash scripts/check-release-readiness.sh
```

**Build signed HAP:**
```bash
./hvigorw assembleHap --mode product=release
```

See [`docs/changelog/CHANGELOG.md`](./docs/changelog/CHANGELOG.md) for W1–W6 feature summary.

## Implementation Status

| Wave | Focus | Status |
|------|-------|--------|
| W1 | 4-layer architecture, IntentBus, Surface decomposition | ✓ Complete |
| W2 | 7 missing feature stubs (Agora, stats, badges, quotes, etc.) | ✓ Complete |
| W3 | Reader full functionality (typesetter, selection, audio sync) | ✓ Complete |
| W4 | AI co-pilot (translation, summarization, LookupWord, TTS) | ✓ Complete |
| W5 | Distributed Soul, 5-surface decomposition, continuation | ✓ Complete |
| W6 | CN compliance (HMS Push, SensorsAnalytics, AGC), payments, release docs | ✓ Complete |
| W7+ | HSP dynamic loading, performance tuning, remaining integrations | Pending |

## Still required for post-W6 phases

- **W21–W22:** Migrate reader/vocab/paywall/tablet/tv/car/watch/widget to runtime HSP (dynamic loading)
- **Payment provider real implementation:** Replace MOCK_OK stubs in Alipay/WeChat/IAP
- **atomic-service independent signing:** Package word-lookup + share-card as separate ≤ 10 MB HAPs
- **Performance optimization:** Meet cold-start budget (≤ 5 GB, ≤ 430 ms to first frame)
- **E2E integration tests:** Reader + AI + payments end-to-end flows
