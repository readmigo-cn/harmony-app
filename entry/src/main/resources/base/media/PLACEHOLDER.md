# Entry 媒体资源

Entry HAP 模块的 base 媒体资源。HarmonyOS qualifier 系统会自动按设备特性选择 `dark/` `large/` 等变体（如未来需要）。

## 当前资源

| 资源名 | 尺寸 | 格式 | 状态 | 来源 |
|--------|------|------|------|------|
| `app_icon.png` | 1024×1024 | PNG | ✅ 已提供 | 同 AppScope/app_icon |
| `start_window_background.png` | 1080×2400 | PNG | 🟡 程序生成占位 | ImageMagick: 品牌绿背景 + icon 居中 |
| `app_icon.svg` | — | SVG | 历史遗留 | 旧版图标，可由 design 决定是否保留 |

> `start_window_background.png` 当前是程序生成的最简启动图（纯色背景 + 居中图标），等 design team 出最终启动页设计后替换。

## 图标策略

**本项目不使用大量 UI icon 资源**。代码中的图标分两种实现：

1. **Unicode glyphs** — 大多数交互图标用单字符 emoji/symbol，如阅读器翻页样式选择：
   ```typescript
   // entry/src/main/ets/features/reader/components/ReaderSettingsSheet.ets
   { value: 'paged',      label: '卷页', icon: '⊟' }
   { value: 'horizontal', label: '滑动', icon: '↔' }
   { value: 'scroll',     label: '滚动', icon: '↕' }
   ```

2. **书封 fallback** — 仅 `app_icon` 一处复用：列表视图 cover 加载失败时显示
   `Image(book.coverUrl ?? $r('app.media.app_icon'))`

历史上 PLACEHOLDER 曾列出 chevron / search / close / play / pause 等 45+ icons，但 PR1-PR7 feature-first 重构后实际代码全部改走 Unicode 字符。如未来需要补 SVG icon，请同步更新本文件清单。

## 资源更新流程

```bash
# 启动图重新生成（如需调整背景色或加文字）
SRC=/Users/HONGBGU/Documents/readmigo-repos/brand/assets/app-icon/icon-1024.png
magick -size 1080x2400 xc:'#4CAF50' \
  \( "$SRC" -resize 480x480 \) -gravity center -composite \
  entry/src/main/resources/base/media/start_window_background.png
```

应用图标从 brand repo 同步见 [`AppScope/resources/base/media/PLACEHOLDER.md`](../../../../../AppScope/resources/base/media/PLACEHOLDER.md)。

## 国际化文案

文案统一在 `entry/src/main/resources/{base,zh_CN,zh_TW,en_US}/element/string.json`，不在本目录。

## 验收

- [x] 启动窗口能正常显示（非 1×1 黑白占位）
- [x] 书封 fallback 引用解析成功
- [ ] design team 交付正式启动页后替换
- [ ] 真机验证启动过渡动画
