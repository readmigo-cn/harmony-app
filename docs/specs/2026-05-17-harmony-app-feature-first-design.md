# harmony-app Feature-First 架构重构设计

- **状态**: Draft（待用户最终批准）
- **日期**: 2026-05-17
- **范围**: 仅 `readmigo-cn-repos/harmony-app/`（不涉及 badge-engine / typesetting / napi-bridge / llm-adapter / server-cn / infra-cn）
- **预期产出**: 7 个 PR，~5–7 工作日，单人节奏
- **方法论入口**: 由 Claude superpowers `brainstorming` skill 引导生成；后续由 `writing-plans` skill 生成实施计划

---

## 1. 问题陈述

harmony-app（米果智读 CN，HarmonyOS NEXT，~5 万行 ArkTS）当前为**横向分层**结构：

```
entry/src/main/ets/
├── pages/        17k 行 / 38+ 文件（顶层平铺 + 7 个端适配子目录混排）
├── service/      14k 行 / 22 个子目录（9 个为"单文件目录"）
├── components/   10k 行 / 24 个顶层组件 + responsive/(3) + optimized/(1) + index.ets barrel（分类轴不一致）
├── store/        4 文件，`.ts` 和 `.ets` 混用
├── model/        7 文件，`Book.ts` 与 `Book.ets` 同名共存且字段不兼容
├── persistence/  DatabaseManager + RdbOrm + repositories/
├── router/       三件套（含 RouterAdapter 过度抽象）
├── native/  widget/  theme/  abilities/  extensions/  entryability/
```

### 已识别的核心债

1. **`.ts` / `.ets` 双轨残留** — `Book.ts`、`Audiobook.ts`、`store/AudioPlayerStore.ts` 是从海外 mobile 拷贝来的 `.ts` 残留；其中 `Book.ts` 与 `Book.ets` schema 不兼容（slug/cefrLevel 仅 .ets 有；series/榜单类型仅 .ts 有；`UserBook` 字段揭示了两套 reader 实现的痕迹）。
2. **service 层过度细分** — 22 个子目录中 9 个是单文件目录（admin/car/dynamic/experiments/llm/storage/translation/tts/tv），抽象成本无对应封装收益。
3. **components 分类轴混乱** — `responsive/`（按场景）与 `optimized/`（按特征）维度不对齐，`optimized/` 仅 1 文件。
4. **pages 顶层平铺与子目录混排** — 38 个 pages 中既有平铺，又有 admin/atomic/car/native/tablet/tv/watch 子目录。
5. **横向分层带来的跨目录跳转地狱** — 修改一个 feature 需在 pages/components/service/store/model 5 个目录间往返。
6. **router 过度抽象** — RouteConstants + RouterAdapter + RouterService 三件套对 529 行总量而言冗余。
7. **隐性范式 bug**（**本次范围外**，记入 Phase 2）— `AudioPlayerStore` 用 callback subscribe 模式，ArkUI `@State` 不会订阅，UI 不会因状态变化 rebuild。

### 优化轴选择

用户已明确：**单一轴 = 架构 / 代码组织清理**（不动性能、工程化、多端适配 —— 这些是独立专项）；干预深度 = **大重构（6–8 PR）**，采用 feature-first 化方案。

---

## 2. 方案选择

三种 feature-first 化路线对比：

| 方案 | 内容 | 取舍 |
|---|---|---|
| **A. 纯 feature-first** | features/ 完全自治，跨切走 platform/ 和 shared/ | 共享 model/store/API 归属难定；shared/ 容易膨胀成"未命名横向层" |
| **B. Hybrid（推荐）** | features/ 内自治 + core/ui/api/store/model 显式横向层 | 与当前代码现实匹配，承认横向层的真实必要性并瘦身 |
| **C. HarmonyOS HAR/HSP 多模块** | 每 feature 拆 HAR 子模块，物理隔离 | hvigor 配置成本高、当前脚手架成熟度不够、过早 |

**采纳方案：B（Hybrid）**。理由：
- 主要痛点是横向分层混乱 + .ts/.ets 双轨 + service 过度细分；B 全部命中。
- 6–8 PR 颗粒度自然契合 B 的工作分解。
- 不引入 hvigor 多模块配置改动，保留可回退性。
- 未来局部 feature 真需要独立打包时再升级到 C，不预付成本。

---

## 3. 目标架构

### 3.1 目录树

```
entry/src/main/ets/
├── entryability/             [不动] EntryAbility 入口
├── abilities/                [不动] 其他 Ability
│
├── core/                     # 跨切关注点与平台能力
│   ├── router/               ← 原 router/ 三件套；删除 RouterAdapter.ets
│   ├── shell/                ← 原 pages/Index.ets 内迁（App 骨架/TabBar）
│   ├── native/               ← 原 native/ NAPI 调用层
│   ├── persistence/          ← 原 persistence/ + 原 service/storage（薄壳并入）
│   ├── widget/               ← 原 widget/ 卡片
│   ├── theme/                ← 原 theme/
│   ├── extensions/           ← 原 extensions/
│   ├── analytics/            ← 原 service/analytics
│   ├── monitoring/           ← 原 service/monitoring
│   ├── performance/          ← 原 service/performance
│   ├── cache/                ← 原 service/cache
│   ├── experiments/          ← 原 service/experiments
│   ├── moderation/           ← 原 service/moderation
│   ├── dynamic/              ← 原 service/dynamic（动态配置）
│   └── atomic/               ← 原 service/atomic（原子化服务运行时支持）
│
├── ui/                       # 跨 feature 共享 UI 组件
│   ├── primitives/           ← Button/Card/Input/List/Tab/Toast/Modal/Loading/EmptyState
│   ├── responsive/           ← AdaptiveGrid/FoldAwareLayout/ResponsiveContainer
│   ├── lazy/                 ← LazyImage（原 components/optimized/）
│   └── sheets/               ← 跨 feature 通用 Sheet
│
├── api/                      # 统一 HTTP/API 客户端，按业务域分包
│   ├── client/               ← HttpClient + 拦截器 + 错误归一化
│   ├── books/  auth/  reading/  ai/  notes/  study/  subscription/  support/  widget/
│
├── store/                    # 全局响应式 store（统一 .ets）
│   ├── UserStore.ets         SettingsStore.ets  ReadingStore.ets
│   ├── AudioPlayerStore.ets  ← 反 .ts 化（仅文件名/语法；范式 bug 留 Phase 2）
│   └── StoreKeys.ets
│
├── model/                    # 单一源 domain model，对齐 server-cn DTO
│   ├── Book.ets              ← 唯一 Book schema（合并自 Book.ts + Book.ets）
│   ├── Audiobook.ets         ← 反 .ts 化
│   ├── Chapter.ets / ReadingProgress.ets / Highlight.ets / ExplainData.ets
│   └── index.ets             ← barrel
│
└── features/                 # 15 个 feature，各自包含 pages + components + service-local
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
    └── dev/                  ← release build 中条件排除
```

### 3.2 层间依赖约束（强制）

| 层 | 可以 import | 禁止 import |
|---|---|---|
| `features/<X>/` | `core/*`, `ui/*`, `api/*`, `store/*`, `model/*` | **其他 `features/<Y>/`**（跨 feature 必须走 store/api） |
| `api/<域>/` | `core/native`, `model/*` | `features/*`, `ui/*`, `store/*` |
| `store/` | `api/*`, `core/persistence`, `model/*` | `features/*`, `ui/*` |
| `model/` | （纯类型，零依赖） | 任何运行时模块 |
| `ui/` | `core/theme`, `core/router`（类型）, `model/*`（类型） | `features/*`, `api/*`, `store/*` |
| `core/` | 同层之间允许 | `features/*`, `ui/*`, `api/*`, `store/*` |

**强制手段**：`tools/check-import-boundary.ts` 脚本接入 hvigor pre-build hook，违规则构建失败。详见 §6.7。

### 3.3 关键收紧点

- 原 22 个 service 子目录 **0 残留**：跨切下沉 core/ (9 个)、HTTP 客户端上提 api/ (1 个)、feature 专属内迁 features/X/service/ (12 个)、storage 薄壳并入 core/persistence (1 个)。
- 原 components 平铺 + responsive/optimized 杂乱 → ui/{primitives, responsive, lazy, sheets} 四子目录、分类轴单一（按 UI 角色）。
- router 三件套 → 二件套：保留 `RouteConstants` + `RouterService`，**删除 RouterAdapter.ets**。
- model 单一源：删除 `Book.ts`、`Audiobook.ts → .ets`、`AudioPlayerStore.ts → .ets`。**ets/ 内 0 个 `.ts` 文件**作为硬验收。

---

## 4. features 切分清单（15 个）

| Feature | Pages（从 pages/ 内迁） | Components（从 components/ 内迁） | service-local（从 service/ 内迁） |
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

### 决策点

- `AudioPlayerStore` / `ReadingStore` 留全局 `store/`（多 feature 都用）。
- `discover` / `study` 暂时单页/单模块，保持独立 feature（未来扩展空间已留）。
- `dev` 在 `build-profile.json5` release variant 中 conditional exclude。

---

## 5. Model 单一源策略

### 5.1 Book.ets 合并规则（路线 1 = 以 server-cn DTO 为权威）

| 字段 | 决策 | 来源 |
|---|---|---|
| `id` / `title` / `author` / `language` | required | 两版相同 |
| `slug` | required | .ets / server-cn |
| `cefrLevel` | optional | .ets / server-cn |
| `authorId` | optional | .ts（海外保留） |
| `difficultyScore` | optional | .ts（与 .ets 的 `difficulty` 并存） |
| `coverUrl` / `description` / `category` / `wordCount` | **optional**（放宽） | .ets 风格 |
| `hasAudiobook` / `audiobookId` | optional，**放在 Book**（非 BookDetail） | .ets |
| `BookDetail.epubUrl / chapters / aiScore / seriesId / seriesName / seriesPosition / seriesBookCount` | optional | .ts（保留） |
| `BookFilters` / `BookListResponse` / `Rating` | 保留 | .ets |
| `BookList` / `BookListBook` / `BookListType`（榜单） | 保留 | .ts（产品路线图保留） |
| `UserBook.currentChapterIndex` | optional | .ets（原生 reader） |
| `UserBook.currentCfi` | optional | .ts（epub.js reader；**保留**以兼容未来双 reader 切换） |
| `UserBook.addedAt/lastReadAt` 类型 | `string`（ISO） | .ets |

### 5.2 Audiobook.ts 转换

- 直接重命名 `.ts → .ets`
- ArkTS 语法兼容修正（`export const` 初始化顺序、`import type` → `import` 视 ArkTS 版本而定）
- **followup**：建议 server-cn 团队对齐此 Audiobook DTO（当前后端缺失）。

### 5.3 AudioPlayerStore.ts 转换（**两阶段**）

- **Phase 1（本次范围）**：仅文件名 `.ts → .ets`、`import type` → `import`、callback 数组提取命名类型 `type StateListener = (s: AudioPlayerStore) => void`。**保留 callback subscribe 模式**。
- **Phase 2（本次范围外）**：响应式范式重构，迁移到 `@ObservedV2` + `@Trace` 或 `AppStorage`，让 ArkUI 组件能用 `@StorageLink` / `@Watch` 直接订阅。独立 spec/PR 跟踪。

### 5.4 验收

- `find entry/src/main/ets -name "*.ts" | wc -l` = 0
- `grep -r "from '.*Book\.ts'" entry/src/main/ets` 0 命中
- `model/Book.ets`、`model/Audiobook.ets`、`store/AudioPlayerStore.ets` 唯一存在
- `model/index.ets` barrel 重新生成

---

## 6. PR 切片（7 个，按依赖排序）

### 依赖图

```
PR-1 model + .ts 清算
  └→ PR-2 core/ 底座 + 跨切下沉
       └→ PR-3 ui/ + api/ 重排
            └→ PR-4 features 批一（reader/library/audiobook/vocab）
                 └→ PR-5 features 批二（ai-tools/account/study/discover/notes）
                      └→ PR-6 features 批三（support/admin/notification/multi-device/multi-platform/dev）
                           └→ PR-7 收尾（路由 + barrel + boundary 校验）
```

### 6.1 PR-1：Model 单一源 + 消灭 .ts 残留

- 合并 `Book.ts` → `Book.ets`，删除 `Book.ts`；Audiobook 与 AudioPlayerStore 反 .ts 化（Phase 1）
- 全仓 import 重写
- 新增 `model/index.ets` barrel
- 估算：~600 行实质改动 + ~200 处 import 重写；0.5 天
- 验收：`.ts` 文件数 0；hvigor clean build pass；Hypium 单测 pass；冷启动 + 5 主 tab smoke OK

### 6.2 PR-2：core/ 底座 + 跨切 service 下沉

- 创建 `core/` 顶层；6 个原横向目录搬入 (`router/native/persistence/widget/theme/extensions/`)
- 9 个跨切 service 子目录搬入 core/（cache/monitoring/performance/analytics/experiments/moderation/dynamic/atomic + storage 并入 persistence）
- 删除 `core/router/RouterAdapter.ets`（先 grep 确认 0 引用）
- `pages/Index.ets` → `core/shell/Index.ets`
- 全仓 import 重写
- 估算：~3500 行；0.5–1 天
- 验收：旧顶层 router/native 等消失；service/ 仍存（剩余 13 个 feature-local 子目录待后续）；hvigor pass；smoke OK

### 6.3 PR-3：ui/ 与 api/ 重排

- 28 个 components（24 顶层 + responsive/3 + optimized/1，删除 index.ets barrel）重分类到 `ui/{primitives, responsive, lazy, sheets}` 或下沉到 features/X/components/
- `service/api/` 11 个 Api 文件按业务域分包到 `api/{books, auth, reading, ai, notes, study, subscription, support, widget}`
- 抽出 `api/client/HttpClient.ets`（如散落，统一抽出）
- 删除 `components/index.ets`
- 估算：~3000 行；0.5–1 天
- 验收：`components/` `service/api/` 顶层目录消失

### 6.4 PR-4：features 批一（核心阅读）

- reader / library / audiobook / vocab 四 feature 内迁（pages + components + service-local + 各自 barrel）
- service/tts 移入 features/audiobook/
- 路由表更新
- 估算：~5500 行（reader 含大组件）；1–1.5 天
- 验收：4 feature 路径可达；service/tts 删除；冷启动 + Reader 主路径 smoke OK

### 6.5 PR-5：features 批二（学习 + 账户）

- ai-tools / account / study / discover / notes 五 feature
- service/{llm, translation, payment, subscription} 内迁到对应 feature
- 估算：~4500 行；1 天
- 验收：service/{llm, translation, payment, subscription} 删除

### 6.6 PR-6：features 批三（外围 + 多端 + dev）

- support / admin / notification / multi-device / multi-platform / dev 六 feature
- service/{admin, notification, push, distributed, sync, car, tv} 内迁
- `build-profile.json5` 加 dev 在 release variant 的 exclude
- 估算：~3500 行；1 天
- 验收：**旧 service/ 顶层目录此时为空**，删除；旧 pages/{admin,car,native,tablet,tv,watch,dev}/ 删除

### 6.7 PR-7：收尾（路由 + barrel + boundary 校验）

- `core/router/RouteConstants.ets` 全量重排（按 features 分组注释）
- 各层 / 各 feature `index.ets` barrel 完善
- 新增 `tools/check-import-boundary.ts` 脚本：遍历 ets 文件，校验跨层 import 规则，违规 exit 1
- hvigor 配置：接入 pre-build hook
- 删除 `entry/src/main/ets/pages/`（Index 已搬走）
- 删除所有残留空目录
- 更新 `harmony-app/README.md` + 新建 `docs/ARCHITECTURE.md`
- 估算：~1500 行；0.5 天
- 验收：0 顶层 `pages/components/service/`；boundary 脚本通过；README 反映现状

### 总工作量

**~5–7 工作日 / 单人节奏**。

---

## 7. 风险防护

### 7.1 Codemod 脚本（必须先建）

- 位置：`scripts/rewrite-imports.mjs`
- 输入：`scripts/rewrite-map.json`，每 PR 维护一份
- 实现：Node.js + 简单 regex（不引入 ts-morph，避免 ArkTS 装饰器解析失败）
- 范围：`entry/src/main/ets/**/*.ets` + `entry/src/ohosTest/**/*.ets`
- **强制跳过**：任何形如 `from 'lib*.so'` 的 NAPI ABI import
- 每 PR 内必跑 + clean build 验证

### 7.2 中间态构建保护

- 强制 `git mv`（保留 git 历史）
- 单 PR 内：mv → codemod → clean build 验证 → 修残留 → 整合为 1 commit。严禁留 broken intermediate commit。
- 每 PR 合并前必须 `rm -rf build oh_modules && pnpm install && hvigor build` 全量重建

### 7.3 回滚预案

- PR-1 schema 引发 NPE：单 PR revert；建议合并后**观察 24h** 再开 PR-2
- PR-2/3 后构建挂：revert 单 PR
- PR-4/5/6 某 feature 内迁后崩：revert 该 PR；其他 feature 已完成不受影响（feature 之间通过 store/api 解耦）
- PR-7 boundary 脚本误报：暂摘 hvigor hook、单独修
- Hard rule：单次 revert 必须使仓库回到 buildable 状态

### 7.4 PR-1 schema 兼容性细化

- Codemod 跑前先扫使用点：`grep -rn "book\.coverUrl\|book\.description\|book\.category\|book\.wordCount" entry/src/main/ets`
- 对每个使用点按场景补空守卫：`book.coverUrl ?? ''`、`book.wordCount ?? 0`、`book.coverUrl?.startsWith(...)`
- 把守卫的 diff 收进 PR-1 本身，避免下游污染

### 7.5 路由表 / build-profile.json5 合并冲突防护

- PR-4/5/6 串行（不允许并行打开）
- `RouteConstants` 新增条目固定在 `// ── new entries below ──` 锚点之后，便于 rebase

### 7.6 Hypium 单测同步

- 每 PR codemod 同时重写测试代码的 import
- 单测的字符串字面量 mock path 单独扫描列嫌疑
- 单测覆盖率每 PR 跑通作为 gate

### 7.7 NAPI / native ABI 不变性

- `core/native/` 内 `import x from 'lib*.so'` 不能被 codemod 触碰（脚本 explicit skip）
- PR-2 完成后做 diff 验证：`grep -rn "from 'lib.*\.so'" core/native/` 前后必须一致

### 7.8 dev/ release build 排除验证

- PR-6 内 `build-profile.json5` release variant 加 `excludes: ["./features/dev/**"]`
- 必跑 `hvigor assembleHap --mode=release` 后 `unzip -l *.hap | grep dev` 检查 dev/* 不在产物里
- debug build 检查 dev/ 仍在（不被误伤）

### 7.9 守门检查表（每 PR 合并前）

```
□ 1. hvigor clean build pass（必跑 clean，不依赖增量缓存）
□ 2. Hypium 单测全套 pass
□ 3. 真机冷启动 + 5 主 tab smoke 无异常
□ 4. ets/ 内 .ts 文件数 = 0（PR-1 后持续保持）
□ 5. codemod 跑后无遗漏 broken import
□ 6. NAPI .so import 未被改动（diff before/after）
□ 7. 单测代码中的 mock path 同步更新
□ 8. 路由表条目齐全（与 features/X/pages/ 实际数量一致）
□ 9. 单 PR git log 仅 1 个 commit
□ 10. PR 描述包含本 PR 改动面 + 验收清单 + 回滚命令
```

---

## 8. Out of Scope / Followups

本次重构**不包含**以下专项，单独立 spec/issue 追踪：

1. **AudioPlayerStore 响应式范式重构** — callback subscribe → `@ObservedV2` + `@Trace` 或 `AppStorage`。当前 callback 模式不被 ArkUI `@State` 订阅，UI 不会因状态变化自动 rebuild。本次仅做 `.ts → .ets` 文件名 + 语法兼容，**保留行为不变**。
2. **server-cn Audiobook DTO 对齐** — 当前后端缺失 Audiobook 模块。建议 server-cn 团队对齐 `model/Audiobook.ets`。
3. **性能 / 启动 / 渲染优化** — 用户已明确不在本次范围。
4. **工程化 / CI / 测试覆盖率提升** — 同上。
5. **多端适配（折叠屏 / 平板 / 车机 / TV / 手表）深化** — 同上。
6. **HarmonyOS HAR/HSP 模块化** — 留待某 feature 真正需要独立打包时再升级。

---

## 9. 验收总和

完成 7 个 PR 后的全局验收：

- `find entry/src/main/ets -name "*.ts" | wc -l` = **0**
- `entry/src/main/ets/` 顶层只剩：`entryability/  abilities/  core/  ui/  api/  store/  model/  features/`
- 旧顶层 `pages/  components/  service/  router/  native/  persistence/  widget/  theme/  extensions/` 全部消失或下沉
- `tools/check-import-boundary.ts` 在 hvigor pre-build hook 中运行，违反层间依赖规则的 import 导致构建失败
- `hvigor clean build` + release build 双双通过
- Hypium 全套单测通过
- 真机冷启动 + 全主路径 smoke OK
- `docs/ARCHITECTURE.md` 反映新结构

---

## 10. 下一步

- 用户 review 本 spec → 批准后进入 `superpowers:writing-plans` skill
- writing-plans 产出 `docs/specs/2026-05-17-harmony-app-feature-first-impl-plan.md`，列出每个 PR 的具体步骤、verification 命令、估时
- 实施按 PR-1 → PR-7 顺序进行；每个 PR 合并前需用户最终确认（per CLAUDE.md "修改代码之前需要先输出方案让我 review" 规则）
