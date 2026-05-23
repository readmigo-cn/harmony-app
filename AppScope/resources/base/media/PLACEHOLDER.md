# AppScope 媒体资源

应用级别（app-scope）的媒体资源。`AppScope/app.json5` 通过 `$media:app_icon` 引用本目录。

## 当前资源

| 资源名 | 尺寸 | 格式 | 状态 | 来源 |
|--------|------|------|------|------|
| `app_icon.png` | 1024×1024 | PNG | ✅ 已提供 | `readmigo-repos/brand/assets/app-icon/icon-1024.png` |

> 注：HarmonyOS Adaptive Icon 标称尺寸 108×108，运行时由系统从高分辨率源缩放。源图保持 1024×1024 以满足应用市场提交要求。

## 资产更新流程

如海外 `brand/dist/harmony/app-icon/` 目录后续生成，可执行（在 repo 根运行）：

```bash
bash brand/sync-from-brand.sh
```

否则手动同步：

```bash
cp /Users/HONGBGU/Documents/readmigo-repos/brand/assets/app-icon/icon-1024.png \
   AppScope/resources/base/media/app_icon.png
```

## 配置引用

`AppScope/app.json5` 当前已正确引用：

- `"icon": "$media:app_icon"` → 本目录的 `app_icon.png`
- `"label": "$string:app_name"` → 各语言 `element/string.json`（zh_CN="米果智读" / en_US="Readmigo"）

## 验收清单

- [x] 应用图标在启动器中正确显示
- [x] 1024×1024 源图可被系统缩放至所有需要尺寸
- [ ] 真机验证图标显示效果（需在真实华为设备上测试）

## 相关文档

- `brand/README.md` — 品牌资源总览
- `entry/src/main/resources/base/media/PLACEHOLDER.md` — Entry module 媒体资源
- HarmonyOS Adaptive Icon: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/adaptive-icon-0000001667688681
