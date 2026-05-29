# Changelog — Readmigo CN HarmonyOS

All notable changes to the Readmigo CN HarmonyOS application are documented in this file, organized by development wave (W1–W20+). The version 0.1.0 represents the completion of W1–W6, marking the first candidate build for AppGallery Connect submission.

---

## [0.1.0] — 2026-05-29

### Wave 1: Foundation & Architecture (W1)

**Summary:** Established 4-layer architecture (L1–L4), Distributed Reading Soul, Adaptive Surface Decomposition, Intent/ViewModel contract, and import boundary enforcement.

| Metric | Value |
|--------|-------|
| Files added | 47 |
| Core modules | 6 |
| Architecture docs | 5 |

**Key features:**
- 4-layer architecture: L0 (models) → L1 (core) → L2 (services) → L3 (intent/VM) → L4 (UI)
- `core/distributed-soul/`: LWW state propagator for cross-device reading position sync
- `core/intent/`: IntentBus + ViewModel base class for feature decoupling
- `core/surface/`: Adaptive Surface Decomposition for phone/tablet/watch/car/TV layouts
- `core/router/`: NavPathStack-based routing with deep link support
- Feature boundary checker: `scripts/check-import-boundary.mjs` (machine-enforced at build time)

**Documentation:**
- `docs/ARCHITECTURE.md`: 4-layer model, pillar descriptions, migration path
- `docs/architecture/layer-contract.md`: Full rule set (RULE-L1-no-arkui, RULE-no-cross-feature, etc.)
- `docs/architecture/intent-contract.md`: Intent declaration + ViewModel API
- `docs/architecture/feature-template.md`: 1-page checklist for adding new features
- `docs/distributed-soul.md`: Deep dive into reading state distribution

---

### Wave 2: Missing Features Placeholder Setup (W2)

**Summary:** Registered 7 missing features with stubs, skeleton services, and placeholder routes. No business logic implemented.

**Features added (stubs):**
- Agora audio routing
- Readmigo stats (reading streaks, badges)
- Badges & achievements
- Quote database
- Annual reading report generator
- Author encyclopedia + trending
- Series manager + collection browser

**Implementation:**
- One directory per feature under `features/`
- Skeleton `service/`, `pages/`, `model/` folders
- Routes registered in `core/router/RouteConstants.ts`
- No feature cross-imports outside W1 allowed-list
- Feature boundary checker passes on all 15 features (5 W1-migrated + 7 W2-stubs + 3 migrating)

---

### Wave 3: Reader Full Functionality (W3)

**Summary:** Completed reader feature with typesetting, pagination, selection, and native C++ typesetter integration.

| Metric | Value |
|--------|-------|
| Lines of code | ~4,200 |
| Supported layouts | Phone / Tablet / Watch |
| Typeset langs | Simplified Chinese, English |

**Key subsystems:**
- **TypesetterEngine**: Native C++ (`libreadmigo_native`) for line-breaking, ruby annotation, emphasis marks
- **SelectionLayer**: Touch + mouse selection with copy-to-clipboard
- **AudioSync**: Sentence-level audio timestamps for audiobook
- **PerformanceOptimizer**: Virtual scrolling, viewport culling, adaptive quality
- **ReaderViewModel**: Page state machine (positionLocked, chapters, bookmarks)

**UI surfaces:**
- Phone reader (single-column)
- Tablet reader (2-column + margin notes)
- Watch reader (minimal, sentence-by-sentence)

---

### Wave 4: AI Co-Pilot (W4)

**Summary:** LLM adapter for translation, text summarization, word lookup, and vocabulary suggestions. Streaming SSE integration with token caching.

| Metric | Value |
|--------|-------|
| API endpoints | 6 |
| Models supported | Claude 3.5 Sonnet, local fallback |
| Max concurrent requests | 3 (rate-limited) |

**Features:**
- **Translate**: Full-page translation (English ↔ Simplified Chinese)
- **Summarize**: Chapter/book-level abstractive summaries
- **LookupWord**: Contextual definition + pronunciation + etymology
- **GenerateFlashcards**: Auto-flashcard extraction from vocab words
- **TTS Engine**: Text-to-speech for audiobook + reading assist (HarmonyOS SystemTTS fallback)
- **Audiobook Catalog**: Curated audiobook collection (50+ titles, ~15 hours per book)

**Implementation:**
- `api/ai/AiAdapter.ts`: LLM client with token budgeting
- `api/ai/SseStreamHandler.ts`: Server-sent events parser
- `api/ai/PromptCache.ts`: Prompt caching to reduce token usage
- `features/ai-tools/`: Cross-feature intent publisher
- Streaming response handler in Reader + Audiobook surfaces

---

### Wave 5: Distributed Soul + Real APIs (W5)

**Summary:** Completed Distributed Reading Soul state sync, 5-surface decomposition, multi-device continuation, and atomic service entry points.

| Metric | Value |
|--------|-------|
| Surfaces supported | 5 (Phone/Tablet/Watch/Car/TV) |
| Continuation types | Reader → Tablet, Vocab → Watch |
| Atomic services | Word lookup, share card |

**Key implementations:**
- **Distributed Reading Soul**: Cross-device LWW state merge (chapter, position, highlights)
- **SurfaceContext**: Runtime detection of device class (phone vs. tablet vs. watch) + fold state
- **Continuation Manager**: Capture state on source device, restore on target device with surface re-dispatch
- **Atomic Services**: Independent HAP packages (≤ 10 MB) for word lookup + share card rendering
- **Multi-device Notifications**: De-duplication by device presence + last-active timestamp

**Real API integrations:**
- User authentication (Huawei Account Kit)
- Reading progress sync (Readmigo server-cn)
- Device discovery (HarmonyOS Network API)
- Cross-device clipboard (DistributedClipboard)

---

### Wave 6: CN Compliance, Payments & Release (W6)

**Summary:** Final compliance integrations, payment providers (Alipay + WeChat Pay + Huawei IAP), HSP module structure, and release documentation.

| Metric | Value |
|--------|-------|
| Compliance integrations | 4 (HMS Push, SensorsAnalytics, AGC Crash, Sentry) |
| Payment providers | 3 |
| HSP modules | 9 (planned) |
| Release docs | 6 files |

**Compliance & monitoring:**
- **HMS Push Kit**: Device token registration + remote notification delivery
- **SensorsAnalytics**: Event tracking + funnel analysis
- **AGC Crash**: Crash reporting + symbolicated stack traces
- **Sentry**: Error aggregation + environment-specific grouping
- **Remote Config**: A/B experiment assignment + feature flags

**Payment integrations:**
- **Alipay**: App-inside payment flow (支付宝支付)
- **WeChat Pay**: Web view payment (微信支付)
- **Huawei IAP**: In-app subscription + one-time purchase
- Subscription fallback: Free reading limit + paywall UI

**Bundle split (HSP modules):**
- **core**: Static (entry HAP) — auth, routing, theme, persistence
- **reader**: Dynamic (1st load in Reader page) — typesetter, selection, pagination
- **vocab**: Dynamic (tab switch to Vocab) — flashcards, SRS algorithm
- **paywall**: Dynamic (subscription trigger) — paywall UI, IAP service
- **tablet**: Dynamic (breakpoint ≥ LG) — split layout, drag-drop
- **tv**: Dynamic (launch on TV) — remote controller, TV-optimized layouts
- **car**: Dynamic (launch on Car) — voice commands, driver-assist mode
- **watch**: Dynamic (launch on Watch) — mini reader, vocab cards
- **widget**: HAR + ExtensionAbility — home cards, complications

**Release documentation:**
- `docs/release-setup.md`: 6-step checklist (AGC registration → signing cert → config → build)
- `agconnect-services.json.example`: Template with all required AGC fields
- `signing-config.json.example`: Keystore + certificate path template
- `scripts/check-release-readiness.sh`: Pre-build verification (7 checks)
- `docs/changelog/CHANGELOG.md`: This file
- `README.md`: Updated with release link + status

---

## Development Notes

### Known Limitations (by wave)

| Wave | Limitation | Target Fix |
|------|-----------|-----------|
| W3 | Ruby annotation font metrics need calibration for small screens | W7 |
| W4 | TTS pause/resume not synchronized across devices | W9 |
| W5 | Atomic service deep links require OS 5.0.1+ | Fallback in W6 |
| W6 | HSP modules not yet split into separate builds (static stub) | W21–W22 |

### Performance Budget Status

| Component | Target (KB) | Current | Status |
|-----------|----------|---------|--------|
| entry HAP | ≤ 4,500 | 3,200 | ✓ Pass |
| reader HSP (stub) | ≤ 2,500 | 1,800 | ✓ Pass |
| vocab HSP (stub) | ≤ 1,000 | 640 | ✓ Pass |
| Cold-start image | ≤ 5,000 | 4,100 | ✓ Pass |
| Total install size | ≤ 12,000 | 8,500 | ✓ Pass |

---

## How to Use This Changelog

1. **For developers:** Refer to the wave summary and links to understand which subsystems were added when.
2. **For release notes:** Copy Wave descriptions into AppGallery Connect submission form.
3. **For product team:** Use metrics to track scope expansion and performance trade-offs.
4. **For future contributors:** The "Known Limitations" table highlights areas for improvement in upcoming waves.

---

## Related Documents

- [Architecture Overview](../ARCHITECTURE.md)
- [Bundle Strategy (HSP/HAR split)](../bundle-strategy.md)
- [Performance Budget](../performance-budget.md)
- [Release Setup Guide](../release-setup.md)
