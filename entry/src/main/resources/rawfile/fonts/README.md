# Reader Fonts (rawfile/fonts/)

W5-C5 registered the font family-name placeholders; the actual font files are added in the W7 phase.
When files are missing, `FontRegistry.registerFonts()` only emits a warning and does not affect startup.

## File inventory

| Filename | Family | Use | License | Estimated size | Phase |
|---|---|---|---|---|---|
| CrimsonPro-Regular.ttf | CrimsonPro-Regular | English reading serif Regular | SIL OFL 1.1 | ~250 KB | W7 |
| CrimsonPro-Bold.ttf | CrimsonPro-Bold | English reading serif Bold | SIL OFL 1.1 | ~250 KB | W7 |
| SourceHanSansCN-Regular.ttf | SourceHanSansCN | Chinese UI / long-read sans | SIL OFL 1.1 | ~10 MB (~3 MB after subset) | W7 |
| SourceHanSerifCN-Regular.ttf | SourceHanSerifCN | Chinese reading serif | SIL OFL 1.1 | ~10 MB (~3 MB after subset) | W7 |

## Naming rules

- Filename must exactly match the `rawfilePath` in `FontRegistry.FONT_ENTRIES`
- Only `.ttf` / `.otf`; HarmonyOS NEXT `font.registerFont` does not support woff2

## Subsetting recommendation (W7)

Raw Chinese fonts exceed 10 MB and must be subset:
- Use `pyftsubset` to trim to ~3 MB based on the top 7,000 common characters
- Rare characters that appear inside the reader fall back to system fonts (HarmonyOS Sans / system serif)

## System fonts

`HarmonyOS Sans` / `HarmonyOS Mono` are provided by the system and **do not need registration** —
just use `.fontFamily('HarmonyOS Sans')` directly.
