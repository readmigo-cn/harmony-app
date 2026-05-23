# Entry media resources

Base media resources for the Entry HAP module. The HarmonyOS qualifier system automatically picks per-device variants such as `dark/` or `large/` (if added later).

## Current resources

| Resource | Size | Format | Status | Source |
|--------|------|------|------|------|
| `app_icon.png` | 1024×1024 | PNG | ✅ provided | Same as AppScope/app_icon |
| `start_window_background.png` | 1080×2400 | PNG | 🟡 programmatically generated placeholder | ImageMagick: brand-green background + centered icon |
| `app_icon.svg` | — | SVG | legacy | Older icon; design may decide whether to keep |

> `start_window_background.png` is currently the simplest programmatically generated splash (solid background + centered icon); replace once the design team delivers the final splash design.

## Icon strategy

**This project does not rely on a large set of UI icon resources.** Code icons fall into two implementations:

1. **Unicode glyphs** — most interactive icons use a single emoji/symbol character, for example the reader's page-style selector:
   ```typescript
   // entry/src/main/ets/features/reader/components/ReaderSettingsSheet.ets
   { value: 'paged',      label: 'Paged',      icon: '⊟' }
   { value: 'horizontal', label: 'Horizontal', icon: '↔' }
   { value: 'scroll',     label: 'Scroll',     icon: '↕' }
   ```

2. **Book-cover fallback** — `app_icon` is reused in exactly one place: the list view's cover when image load fails
   `Image(book.coverUrl ?? $r('app.media.app_icon'))`

Historically this PLACEHOLDER listed 45+ icons (chevron / search / close / play / pause, etc.), but after the PR1–PR7 feature-first refactor the codebase moved to Unicode characters. If SVG icons are needed in the future, update this inventory accordingly.

## Resource update workflow

```bash
# Regenerate the launch window (e.g. to tweak background color or add text)
SRC=/Users/HONGBGU/Documents/readmigo-repos/brand/assets/app-icon/icon-1024.png
magick -size 1080x2400 xc:'#4CAF50' \
  \( "$SRC" -resize 480x480 \) -gravity center -composite \
  entry/src/main/resources/base/media/start_window_background.png
```

For app-icon sync from the brand repo, see [`AppScope/resources/base/media/PLACEHOLDER.md`](../../../../../AppScope/resources/base/media/PLACEHOLDER.md).

## Localized strings

UI strings live under `entry/src/main/resources/{base,zh_CN,zh_TW,en_US}/element/string.json`, not in this directory.

## Acceptance

- [x] Launch window displays normally (not the 1×1 black/white placeholder)
- [x] Book-cover fallback resolves successfully
- [ ] Replace once the design team delivers the final splash
- [ ] Verify launch transition animation on a real device
