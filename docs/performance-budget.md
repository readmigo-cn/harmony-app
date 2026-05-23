# 性能预算 — 米果智读 HarmonyOS

版本：W20-C3
更新：2026-05-01

---

## 一、总体目标

| 指标 | 目标值 | 硬限 | 测量方法 |
|------|--------|------|---------|
| 冷启动（进程创建→首帧渲染） | < 2000ms | 3000ms | PerformanceMonitor `app_start` |
| 首屏渲染（EntryAbility.onCreate 完成→UI 可见） | < 500ms | 800ms | PerformanceMonitor `first_frame` |
| 章节加载（点击章节→文本可读） | < 800ms | 1500ms | PerformanceMonitor `chapter_load` |
| 翻页渲染（帧率，Reader 页） | 60fps | 45fps | PerformanceMonitor `recordFrame` |
| 搜索响应（输入→结果列表渲染） | < 300ms | 600ms | PerformanceMonitor `search_response` |
| 内存峰值（阅读最长章节时） | < 200MB | 250MB | MemoryGuard CRITICAL 阈值 |
| HAP 包大小 | < 80MB | 100MB | DevEco Build Report |

---

## 二、各页面性能预算

### 2.1 启动 / Index 页

| 阶段 | 预算 | 备注 |
|------|------|------|
| PreferencesManager.init | < 50ms | CRITICAL 任务 |
| DatabaseManager.init | < 100ms | CRITICAL 任务 |
| UserStore + ReadingStore + SettingsStore init | < 150ms | 合计，CRITICAL 任务 |
| ThemeService.init | < 30ms | CRITICAL 任务 |
| 首屏 UI 渲染（Index.ets build） | < 100ms | ArkUI 渲染管线 |
| CRITICAL 任务总计 | < 430ms | 留 70ms 给 ArkUI 初始化 |

### 2.2 Reader 页

| 指标 | 预算 | 备注 |
|------|------|------|
| 章节内容加载（网络 + 排版） | < 800ms | `chapter_load` mark |
| 翻页动画帧率 | ≥ 60fps | 掉帧 < 5% |
| 掉帧判定阈值（janky frame） | > 16.7ms/帧 | PerformanceMonitor |
| 选词弹窗响应 | < 200ms | 长按→ExplainCard 出现 |
| 排版 native 计算（单页） | < 50ms | typesetting.ets NAPI 调用 |

### 2.3 Library / 书库页

| 指标 | 预算 | 备注 |
|------|------|------|
| 书库列表渲染（50本） | < 200ms | LazyForEach + LazyImage |
| 封面图首次加载 | < 500ms | CacheManager 下载 |
| 封面图缓存命中 | < 20ms | LRU 内存缓存 |
| 搜索响应 | < 300ms | `search_response` mark |

### 2.4 听书（Audio）页

| 指标 | 预算 | 备注 |
|------|------|------|
| 音频首次起播延迟 | < 1000ms | 含网络 + AVPlayer init |
| 字幕同步误差 | < 100ms | TTS / 字幕时间轴对齐 |

---

## 三、内存预算

| 场景 | 预算 | 级别 |
|------|------|------|
| 应用空闲（后台） | < 80MB | 正常 |
| 阅读中（单章节） | < 150MB | 正常上限 |
| 阅读中（超长章节 + 翻译） | < 180MB | WARN 触发 |
| 峰值硬限 | < 200MB | CRITICAL 触发 |

### 内存清理策略（MemoryGuard）

```
WARN (≥150MB):
  → CacheManager.clear('translations')
  → ImageLruCache.clear(25)（清一半）

CRITICAL (≥180MB):
  → CacheManager.clear('translations')
  → CacheManager.clear('dict')
  → ImageLruCache.clear()（全清）
  → typesetting.clearLayoutCache()
  → globalThis.gc()（GC hint）
```

---

## 四、HAP 包大小预算

| 模块 | 目标 | 备注 |
|------|------|------|
| JS Bundle（ArkTS 编译产物） | < 8MB | 按需分包 |
| native .so（libreadmigo_native.so） | < 4MB | arm64-v8a |
| 内置资源（图标 / 字体）| < 10MB | 字体仅内置 Regular + Bold |
| 动态下载资源（音频 / 额外字体）| N/A | 运行时下载，不计入 HAP |
| HAP 总计 | < 80MB | DevEco Build Report 核查 |

---

## 五、监控指标与告警阈值

### 5.1 神策（SensorsAnalytics）上报

事件名：`perf_metric`

| 属性 | 说明 |
|------|------|
| `metric_name` | 监控点名称（app_start / first_frame 等） |
| `duration_ms` | 耗时（ms） |
| `fps_avg` | 当前帧率 |
| `fps_janky` | 掉帧计数 |
| `mem_rss_kb` | 当前 RSS（KB） |
| `exceeded_budget` | 是否超预算（0/1） |

告警：`exceeded_budget = 1` 且 `metric_name IN (app_start, first_frame)` → 触发神策告警看板

### 5.2 Sentry 告警

| 场景 | Level |
|------|-------|
| 任意 metric 超预算 | warning |
| 帧率持续低于 50fps | warning |
| CRITICAL 内存清理触发 | error |

### 5.3 关键告警阈值

| 指标 | 告警阈值 | 来源 |
|------|---------|------|
| `app_start` | > 2000ms | PerformanceMonitor.THRESHOLDS |
| `first_frame` | > 500ms | PerformanceMonitor.THRESHOLDS |
| `chapter_load` | > 800ms | PerformanceMonitor.THRESHOLDS |
| `page_render` | > 100ms | PerformanceMonitor.THRESHOLDS |
| `search_response` | > 300ms | PerformanceMonitor.THRESHOLDS |
| 内存 WARN | ≥ 150MB | MemoryGuard |
| 内存 CRITICAL | ≥ 180MB | MemoryGuard |

---

## 六、工具链

### 6.1 开发阶段

| 工具 | 用途 |
|------|------|
| DevEco Studio → ArkUI Inspector | 组件树 / 布局渲染耗时分析 |
| DevEco Studio → Profiler → CPU | JS 线程 + native 热点分析 |
| DevEco Studio → Profiler → Memory | Heap snapshot / 内存泄漏定位 |
| `hdc shell perf record` | native 侧性能采样（框架层 + NAPI） |
| `hdc shell hilog` | PerformanceMonitor 日志实时查看 |

```bash
# 查看 PerformanceMonitor 输出
hdc shell hilog | grep PerformanceMonitor

# 查看内存使用
hdc shell hidumper -s AbilityManagerService -a "-a"

# 抓取 perf 样本（30s）
hdc shell perf record -p $(hdc shell pidof cn.readmigo.app) -g -d 30 -o /data/perf.data
hdc file recv /data/perf.data ./perf.data
```

### 6.2 CI / 自动化

- 每次 PR 合并触发自动化性能回归测试（目标：W21 接入）
- DevEco Build Report 校验 HAP 大小，超 80MB 阻断合并

### 6.3 W18 仪表板集成

神策仪表板查询语句示例（HogQL）：

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

仪表板位置：神策 → 「性能监控」看板（W21 建立）

---

## 七、优化路线图

| 优先级 | 优化项 | 预期收益 | Sprint |
|--------|--------|---------|--------|
| P0 | StartupOptimizer 启动任务分级（本 Sprint） | 冷启动 -30% | W20 |
| P0 | LazyImage + LRU 缓存（本 Sprint） | 首屏内存 -20MB | W20 |
| P1 | 章节内容预加载（下一章节后台 prefetch） | chapter_load -50% | W21 |
| P1 | 排版结果 native 缓存（章节 layout 缓存到内存） | 翻页 +10fps | W21 |
| P2 | ArkUI 组件懒加载（书库 LazyForEach 已有，Reader 待优化） | 内存 -15MB | W22 |
| P2 | HAP 分包（按 Ability 拆分，主包 < 10MB） | 安装速度 +40% | W22 |
| P3 | WebP 封面图（替代 PNG，体积 -60%） | HAP / 缓存 -20MB | W23 |
