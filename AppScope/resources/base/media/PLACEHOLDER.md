# AppScope media resources

App-scope media resources. `AppScope/app.json5` references this directory via `$media:app_icon`.

## Current resources

| Resource | Size | Format | Status | Source |
|--------|------|------|------|------|
| `app_icon.png` | 1024×1024 | PNG | ✅ provided | `readmigo-repos/brand/assets/app-icon/icon-1024.png` |

> Note: HarmonyOS Adaptive Icon's nominal size is 108×108; the system scales from a high-resolution source at runtime. The source image stays at 1024×1024 to satisfy app-store submission requirements.

## Asset update workflow

If the upstream `brand/dist/harmony/app-icon/` directory is generated later, run from the repo root:

```bash
bash brand/sync-from-brand.sh
```

Otherwise sync manually:

```bash
cp /Users/HONGBGU/Documents/readmigo-repos/brand/assets/app-icon/icon-1024.png \
   AppScope/resources/base/media/app_icon.png
```

## Configuration reference

`AppScope/app.json5` already references these correctly:

- `"icon": "$media:app_icon"` → `app_icon.png` in this directory
- `"label": "$string:app_name"` → per-language `element/string.json` (localized strings: zh_CN, zh_TW, en_US — see those resource files for current values)

## Acceptance checklist

- [x] App icon displays correctly in the launcher
- [x] 1024×1024 source can be scaled by the system to every required size
- [ ] Verify the icon on a real Huawei device

## Related docs

- `brand/README.md` — brand assets overview
- `entry/src/main/resources/base/media/PLACEHOLDER.md` — Entry module media resources
- HarmonyOS Adaptive Icon: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/adaptive-icon-0000001667688681
