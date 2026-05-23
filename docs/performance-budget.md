# Performance budget — Readmigo HarmonyOS

Version: W20-C3
Updated: 2026-05-01

---

## 1. Overall targets

| Metric | Target | Hard limit | Measurement |
|------|--------|------|---------|
| Cold start (process creation → first frame rendered) | < 2000ms | 3000ms | PerformanceMonitor `app_start` |
| First screen render (EntryAbility.onCreate complete → UI visible) | < 500ms | 800ms | PerformanceMonitor `first_frame` |
| Chapter load (chapter tap → text readable) | < 800ms | 1500ms | PerformanceMonitor `chapter_load` |
| Page turn render (Reader page frame rate) | 60fps | 45fps | PerformanceMonitor `recordFrame` |
| Search response (input → result list rendered) | < 300ms | 600ms | PerformanceMonitor `search_response` |
| Memory peak (reading the longest chapter) | < 200MB | 250MB | MemoryGuard CRITICAL threshold |
| HAP package size | < 80MB | 100MB | DevEco Build Report |

---

## 2. Per-page performance budget

### 2.1 Launch / Index page

| Stage | Budget | Notes |
|------|------|------|
| PreferencesManager.init | < 50ms | CRITICAL task |
| DatabaseManager.init | < 100ms | CRITICAL task |
| UserStore + ReadingStore + SettingsStore init | < 150ms | Aggregate, CRITICAL task |
| ThemeService.init | < 30ms | CRITICAL task |
| First-screen UI render (Index.ets build) | < 100ms | ArkUI rendering pipeline |
| CRITICAL tasks total | < 430ms | Leaves 70ms for ArkUI initialization |

### 2.2 Reader page

| Metric | Budget | Notes |
|------|------|------|
| Chapter content load (network + typesetting) | < 800ms | `chapter_load` mark |
| Page-turn animation frame rate | ≥ 60fps | Janky frames < 5% |
| Janky-frame threshold | > 16.7ms / frame | PerformanceMonitor |
| Word-selection popup latency | < 200ms | Long-press → ExplainCard visible |
| Native typesetting computation (per page) | < 50ms | typesetting.ets NAPI call |

### 2.3 Library page

| Metric | Budget | Notes |
|------|------|------|
| Library list render (50 books) | < 200ms | LazyForEach + LazyImage |
| Cover image first load | < 500ms | CacheManager download |
| Cover image cache hit | < 20ms | LRU in-memory cache |
| Search response | < 300ms | `search_response` mark |

### 2.4 Audiobook page

| Metric | Budget | Notes |
|------|------|------|
| Audio first-play latency | < 1000ms | Includes network + AVPlayer init |
| Subtitle sync error | < 100ms | TTS / subtitle timeline alignment |

---

## 3. Memory budget

| Scenario | Budget | Level |
|------|------|------|
| Idle app (background) | < 80MB | Normal |
| Reading (single chapter) | < 150MB | Normal ceiling |
| Reading (extra-long chapter + translation) | < 180MB | WARN trigger |
| Peak hard limit | < 200MB | CRITICAL trigger |

### Memory cleanup strategy (MemoryGuard)

```
WARN (≥150MB):
  → CacheManager.clear('translations')
  → ImageLruCache.clear(25)  (drop half)

CRITICAL (≥180MB):
  → CacheManager.clear('translations')
  → CacheManager.clear('dict')
  → ImageLruCache.clear()  (full)
  → typesetting.clearLayoutCache()
  → globalThis.gc()  (GC hint)
```

---

## 4. HAP package size budget

| Module | Target | Notes |
|------|------|------|
| JS bundle (ArkTS compilation output) | < 8MB | Split on demand |
| Native `.so` (libreadmigo_native.so) | < 4MB | arm64-v8a |
| Bundled resources (icons / fonts) | < 10MB | Fonts bundle Regular + Bold only |
| Dynamic-download resources (audio / extra fonts) | N/A | Downloaded at runtime, not counted in HAP |
| HAP total | < 80MB | DevEco Build Report check |

---

## 5. Monitoring metrics and alert thresholds

### 5.1 SensorsAnalytics reporting

Event name: `perf_metric`

| Attribute | Description |
|------|------|
| `metric_name` | Monitor point name (app_start / first_frame, etc.) |
| `duration_ms` | Elapsed time (ms) |
| `fps_avg` | Current frame rate |
| `fps_janky` | Janky frame count |
| `mem_rss_kb` | Current RSS (KB) |
| `exceeded_budget` | Over budget? (0/1) |

Alert: `exceeded_budget = 1` AND `metric_name IN (app_start, first_frame)` → triggers the SensorsAnalytics alert dashboard.

### 5.2 Sentry alerts

| Scenario | Level |
|------|-------|
| Any metric over budget | warning |
| Frame rate consistently below 50fps | warning |
| CRITICAL memory cleanup triggered | error |

### 5.3 Key alert thresholds

| Metric | Alert threshold | Source |
|------|---------|------|
| `app_start` | > 2000ms | PerformanceMonitor.THRESHOLDS |
| `first_frame` | > 500ms | PerformanceMonitor.THRESHOLDS |
| `chapter_load` | > 800ms | PerformanceMonitor.THRESHOLDS |
| `page_render` | > 100ms | PerformanceMonitor.THRESHOLDS |
| `search_response` | > 300ms | PerformanceMonitor.THRESHOLDS |
| Memory WARN | ≥ 150MB | MemoryGuard |
| Memory CRITICAL | ≥ 180MB | MemoryGuard |

---

## 6. Tooling

### 6.1 Development

| Tool | Use |
|------|------|
| DevEco Studio → ArkUI Inspector | Component tree / layout render cost analysis |
| DevEco Studio → Profiler → CPU | JS thread + native hotspot analysis |
| DevEco Studio → Profiler → Memory | Heap snapshot / memory leak localization |
| `hdc shell perf record` | Native-side performance sampling (framework + NAPI) |
| `hdc shell hilog` | Real-time PerformanceMonitor log viewing |

```bash
# View PerformanceMonitor output
hdc shell hilog | grep PerformanceMonitor

# View memory usage
hdc shell hidumper -s AbilityManagerService -a "-a"

# Capture perf samples (30s)
hdc shell perf record -p $(hdc shell pidof cn.readmigo.app) -g -d 30 -o /data/perf.data
hdc file recv /data/perf.data ./perf.data
```

### 6.2 CI / automation

- Every PR merge triggers automated performance regression tests (target: W21 onboarding)
- DevEco Build Report validates HAP size; > 80MB blocks merge

### 6.3 W18 dashboard integration

Sample SensorsAnalytics dashboard query (HogQL):

```sql
SELECT
  metric_name,
  quantile(0.50)(duration_ms) AS p50,
  quantile(0.90)(duration_ms) AS p90,
  quantile(0.99)(duration_ms) AS p99,
  countIf(exceeded_budget = 1) AS over_budget_count
FROM events
WHERE event = 'perf_metric'
  AND timestamp >= now() - INTERVAL 7 DAY
GROUP BY metric_name
ORDER BY p90 DESC
```

Dashboard location: SensorsAnalytics → "Performance Monitoring" board (established W21).

---

## 7. Optimization roadmap

| Priority | Optimization | Expected gain | Sprint |
|--------|--------|---------|--------|
| P0 | StartupOptimizer task tiering (this sprint) | Cold start -30% | W20 |
| P0 | LazyImage + LRU cache (this sprint) | First-screen memory -20MB | W20 |
| P1 | Chapter content prefetch (background prefetch next chapter) | chapter_load -50% | W21 |
| P1 | Native layout cache (cache chapter layout in memory) | Page turn +10fps | W21 |
| P2 | ArkUI component lazy loading (Library already uses LazyForEach; Reader pending) | Memory -15MB | W22 |
| P2 | HAP packaging split (split by Ability; main package < 10MB) | Install speed +40% | W22 |
| P3 | WebP cover images (replace PNG, -60% size) | HAP / cache -20MB | W23 |
