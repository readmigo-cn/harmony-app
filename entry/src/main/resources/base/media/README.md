# Media resource files

> **Important**: this directory needs actual image resource files to be added.

## Required resource files

### App icons
- `app_icon.png` — main app icon (108x108px, adaptive icon)
- `app_icon_foreground.png` — icon foreground layer
- `app_icon_background.png` — icon background layer

### Launch window
- `start_window_background.png` — launch window background

### Functional icons (24x24px, SVG or PNG)
- `chevron_right.svg` — right chevron
- `chevron_left.svg` — left chevron
- `chevron_down.svg` — down chevron
- `arrow_back.svg` — back arrow
- `search.svg` — search
- `close.svg` — close
- `edit.svg` — edit
- `delete.svg` — delete
- `logout.svg` — logout
- `settings.svg` — settings
- `language.svg` — language
- `email.svg` — email
- `person.svg` — user
- `crown.svg` — pro membership
- `bar_chart.svg` — stats
- `timer.svg` — timer
- `book.svg` — book
- `fire.svg` — streak / hot
- `notifications.svg` — notifications
- `wifi.svg` — wifi
- `sync.svg` — sync
- `help.svg` — help
- `help_center.svg` — help center
- `feedback.svg` — feedback
- `info.svg` — info
- `check.svg` — check
- `check_circle.svg` — checked circle
- `uncheck_circle.svg` — unchecked circle
- `more_vert.svg` — more
- `play_arrow.svg` — play
- `pause.svg` — pause
- `skip_previous.svg` — previous track
- `skip_next.svg` — next track
- `replay_10.svg` — rewind 10s
- `forward_10.svg` — forward 10s
- `volume_up.svg` — volume
- `playlist_play.svg` — playlist
- `bedtime.svg` — sleep timer
- `text_fields.svg` — text
- `headset.svg` — headset
- `headset_off.svg` — headset off
- `mic.svg` — microphone
- `record_voice_over.svg` — voice recording
- `list.svg` — list
- `bookmark.svg` — bookmark
- `highlight.svg` — highlight
- `media.svg` — media

## How to add resources

### Option 1: Use DevEco Studio
1. Right-click the `media` directory
2. `New` → `Image Asset`
3. Select an image or vector graphic
4. Multi-resolution variants are generated automatically

### Option 2: Add manually
1. Prepare an SVG or PNG file
2. Drop it into the `media` directory
3. Reference it in code via `$r('app.media.filename')`

## Temporary workaround

During development, you can bypass missing resources via:

```typescript
// Use a system icon instead
Image($r('sys.media.ohos_ic_public_search'))

// Or use a solid-color Rectangle as a placeholder
Rectangle()
  .width(24)
  .height(24)
  .fill('#4CAF50')
```

## Resource conventions

- **PNG**: icons, illustrations (alpha supported)
- **SVG**: vector icons (recommended)
- **WebP**: photos, complex images (smaller footprint)
- **GIF**: not recommended for production

### Size conventions
- Small icon: 24x24px
- Medium icon: 48x48px
- Large icon: 96x96px
- App icon: 108x108px (adaptive)

---

**Last updated**: 2026-04-26
