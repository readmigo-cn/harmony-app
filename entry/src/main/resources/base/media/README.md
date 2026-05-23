# 媒体资源文件说明

> **重要**: 本目录需要添加实际的图片资源文件

## 必需的资源文件

### 应用图标
- `app_icon.png` - 应用主图标 (108x108px, adaptive icon)
- `app_icon_foreground.png` - 图标前景层
- `app_icon_background.png` - 图标背景层

### 启动窗口
- `start_window_background.png` - 启动窗口背景

### 功能图标 (24x24px, SVG 或 PNG)
- `chevron_right.svg` - 右箭头
- `chevron_left.svg` - 左箭头
- `chevron_down.svg` - 下箭头
- `arrow_back.svg` - 返回箭头
- `search.svg` - 搜索
- `close.svg` - 关闭
- `edit.svg` - 编辑
- `delete.svg` - 删除
- `logout.svg` - 退出
- `settings.svg` - 设置
- `language.svg` - 语言
- `email.svg` - 邮箱
- `person.svg` - 用户
- `crown.svg` - 会员
- `bar_chart.svg` - 统计
- `timer.svg` - 计时
- `book.svg` - 书籍
- `fire.svg` - 火焰
- `notifications.svg` - 通知
- `wifi.svg` - WiFi
- `sync.svg` - 同步
- `help.svg` - 帮助
- `help_center.svg` - 帮助中心
- `feedback.svg` - 反馈
- `info.svg` - 信息
- `check.svg` - 勾选
- `check_circle.svg` - 勾选圆圈
- `uncheck_circle.svg` - 未勾选圆圈
- `more_vert.svg` - 更多
- `play_arrow.svg` - 播放
- `pause.svg` - 暂停
- `skip_previous.svg` - 上一首
- `skip_next.svg` - 下一首
- `replay_10.svg` - 回退 10 秒
- `forward_10.svg` - 前进 10 秒
- `volume_up.svg` - 音量
- `playlist_play.svg` - 播放列表
- `bedtime.svg` - 定时
- `text_fields.svg` - 文本
- `headset.svg` - 耳机
- `headset_off.svg` - 耳机关闭
- `mic.svg` - 麦克风
- `record_voice_over.svg` - 录音
- `list.svg` - 列表
- `bookmark.svg` - 书签
- `highlight.svg` - 高亮
- `media.svg` - 媒体

## 如何添加资源

### 方式 1: 使用 DevEco Studio
1. 右键点击 `media` 目录
2. `New` → `Image Asset`
3. 选择图片或矢量图
4. 自动生成多分辨率版本

### 方式 2: 手动添加
1. 准备 SVG 或 PNG 文件
2. 放置到 `media` 目录
3. 在代码中使用 `$r('app.media.filename')` 引用

## 临时解决方案

开发期间可以使用以下方式绕过资源缺失：

```typescript
// 使用系统图标替代
Image($r('sys.media.ohos_ic_public_search'))

// 或使用纯色 Rectangle 占位
Rectangle()
  .width(24)
  .height(24)
  .fill('#4CAF50')
```

## 资源规范

- **PNG**: 用于图标、插图（支持透明）
- **SVG**: 用于矢量图标（推荐）
- **WebP**: 用于照片、复杂图片（更小体积）
- **GIF**: 不推荐用于生产环境

### 尺寸规范
- 小图标：24x24px
- 中等图标：48x48px
- 大图标：96x96px
- 应用图标：108x108px (adaptive)

---

**最后更新**: 2026-04-26
