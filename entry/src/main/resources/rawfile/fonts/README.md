# Reader Fonts (rawfile/fonts/)

W5-C5 注册了字体 family 名占位，真正的字体文件由 W7 phase 加入。
缺文件时 `FontRegistry.registerFonts()` 仅打 warning，不影响启动。

## 文件清单

| 文件名 | Family | 用途 | 授权 | 估算大小 | Phase |
|---|---|---|---|---|---|
| CrimsonPro-Regular.ttf | CrimsonPro-Regular | 英文阅读衬线 Regular | SIL OFL 1.1 | ~250 KB | W7 |
| CrimsonPro-Bold.ttf | CrimsonPro-Bold | 英文阅读衬线 Bold | SIL OFL 1.1 | ~250 KB | W7 |
| SourceHanSansCN-Regular.ttf | SourceHanSansCN | 中文 UI / 长阅读无衬线 | SIL OFL 1.1 | ~10 MB（subset 后 ~3 MB） | W7 |
| SourceHanSerifCN-Regular.ttf | SourceHanSerifCN | 中文阅读衬线 | SIL OFL 1.1 | ~10 MB（subset 后 ~3 MB） | W7 |

## 命名规则

- 文件名必须与 `FontRegistry.FONT_ENTRIES` 中的 `rawfilePath` 完全一致
- 仅 `.ttf` / `.otf`；HarmonyOS NEXT 的 `font.registerFont` 不支持 woff2

## 子集化建议（W7）

中文字体原始体积 10 MB+，必须做 subset：
- 用 `pyftsubset` 按常用 7000 字裁剪到 ~3 MB
- 阅读器内出现的稀有字符走系统兜底（HarmonyOS Sans / system serif）

## 系统字体

`HarmonyOS Sans` / `HarmonyOS Mono` 由系统提供，**无需注册**，
直接 `.fontFamily('HarmonyOS Sans')` 即可。
