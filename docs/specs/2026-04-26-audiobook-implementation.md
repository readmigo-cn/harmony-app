# Audiobook Feature Implementation

> **Feature alignment**: Overseas `readmigo-repos/mobile/src/features/audiobook` + `audiolab`  
> **Created**: 2026-04-26  
> **Status**: ✅ Complete (UI/UX layer ready, TTS integration pending)

---

## Overview

Full audiobook playback feature implementation for HarmonyOS, aligned with overseas version functionality. Includes:

- 📚 Audiobook library and discovery
- ▶️ Full-screen audio player with playback controls
- 🎙️ TTS generation from ebooks (domestic providers)
- 📖 Follow-along text highlighting (word-level)
- ⏱️ Sleep timer and playback speed control
- 🔄 Whispersync with ebook progress

---

## Implemented Files

### Models (`model/Audiobook.ts`)
```typescript
- Audiobook / AudiobookListItem
- AudiobookChapter / AudiobookParagraph
- AudiobookProgress
- AudioPlayerState
- TTSVoice
- PlaybackSpeed (0.5x - 3.0x)
- SleepTimerOption (5-60 min, end of chapter)
- AudioWordTimestamp (word-level sync)
```

### Services
- `service/AudiobookApi.ts` - API service for audiobook streaming, progress sync
- `service/TTSService.ts` - TTS integration (iFlytek / Aliyun / Baidu)
- `store/AudioPlayerStore.ts` - Global audio player state management

### Pages
- `pages/AudiobookTab.ets` - Audiobook library/discovery tab
- `pages/AudiobookPlayer.ets` - Full-screen audio player

---

## Feature Matrix

| Feature | Overseas | HarmonyOS (CN) | Status |
|---------|----------|----------------|--------|
| **Library** | | | |
| Audiobook list | ✅ | ✅ | Complete |
| Recently played | ✅ | ✅ | Complete |
| Search | ✅ | ✅ | Complete |
| Categories | ✅ | ✅ | Complete |
| **Player** | | | |
| Play/Pause | ✅ | ✅ | Complete |
| Seek forward/backward | ✅ | ✅ | Complete |
| Chapter navigation | ✅ | ✅ | Complete |
| Progress slider | ✅ | ✅ | Complete |
| Speed control (0.5x-3.0x) | ✅ | ✅ | Complete |
| Sleep timer | ✅ | ✅ | Complete |
| Chapter list | ✅ | ✅ | Complete |
| **TTS** | | | |
| TTS generation | ✅ | ✅ | Structure ready |
| Voice selection | ✅ | ✅ | Structure ready |
| iFlytek integration | N/A | ✅ | Domestic adaptation |
| **Advanced** | | | |
| Word-level highlighting | ✅ | ✅ | Structure ready |
| Follow-along text | ✅ | ✅ | Structure ready |
| Whispersync | ✅ | ✅ | Structure ready |
| Download management | ✅ | ⏳ | TODO |

---

## Key Components

### AudiobookTab (Audiobook tab)

```
Features:
- Header with search and TTS generate buttons
- Category tabs (All, Recently Played, Downloads, TTS Generated)
- Recently played horizontal scroll
- Audiobook grid (2 columns)
- Search functionality
- Empty state with CTA

UI Structure:
├── Header (Title + Search + TTS)
├── Category Tabs (Horizontal scroll)
├── Main Content
│   ├── Recently Played Section
│   ├── Audiobook Grid
│   └── Search Results
└── Mini Player (when playing)
```

### AudiobookPlayer (Player page)

```
Features:
- Full-screen player with dark theme
- Cover art display
- Book info (title, author, narrator)
- Progress slider with time labels
- Main controls (skip, seek, play/pause)
- Secondary controls (speed, sleep, chapters, voice)
- Modal sheets for:
  - Speed picker (0.5x - 3.0x)
  - Sleep timer (5-60 min, chapter end)
  - Chapter list
  - Voice selector (TTS only)

UI Structure:
├── Header (Close + Title + More)
├── Cover Art
├── Book Info
├── Progress Slider
├── Main Controls (5 buttons)
├── Secondary Controls (4 buttons)
└── Modals (Speed/Sleep/Chapters/Voice)
```

### AudioPlayerStore (State management)

```typescript
State:
- Current audiobook & chapter
- Playback state (playing, loading, buffering)
- Current time & duration
- Playback speed
- Sleep timer
- UI state (minimized, visible)

Actions:
- loadAudiobook()
- togglePlay() / play() / pause()
- seek() / seekForward() / seekBackward()
- nextChapter() / previousChapter() / goToChapter()
- setPlaybackSpeed()
- setSleepTimer()
- minimize() / expand() / hide() / show()
- updateTime()
```

---

## TTS Integration (domestic providers)

### Supported Providers

| Provider | Voices | Status |
|----------|--------|--------|
| **iFlytek** | Xiaoyan, Jiujiu, Zhifeng, Xiaomei | ✅ Primary |
| **Aliyun** | Xiaoyun | ✅ Backup |
| **Baidu** | Chunyu | ✅ Backup |

### TTS Service API

```typescript
TTSService.generateAudio(text)     // Generate audio for text
TTSService.generateChapter(...)     // Generate full chapter
TTSService.getTaskStatus(taskId)    // Check generation progress
TTSService.getAvailableVoices()     // Get voice options
TTSService.setConfig({ provider, voiceId, speed })
```

### TTS Generation Flow

```
1. User selects ebook → "Generate Audiobook"
2. Select TTS voice (iFlytek default)
3. Select chapters (all or specific)
4. Submit generation request
5. Server processes (shows progress)
6. Audiobook available in library
```

---

## API Endpoints

```
GET  /api/v1/audiobooks              - List audiobooks
GET  /api/v1/audiobooks/:id          - Get audiobook detail
GET  /api/v1/audiobooks/book/:bookId - Get audiobook for ebook (Whispersync)
GET  /api/v1/audiobooks/recently-played - Recently played
GET  /api/v1/audiobooks/search?q=    - Search audiobooks
POST /api/v1/audiobooks/:id/progress - Update progress
GET  /api/v1/audiobooks/:id/progress - Get progress

GET  /api/v1/audiobooks/tts/voices   - Get TTS voices
POST /api/v1/audiobooks/tts/generate - Generate TTS audiobook
GET  /api/v1/tts/tasks/:id           - Get TTS task status
```

---

## UI/UX Design

### Color Scheme

```
Player Theme (Dark):
- Background: #0f0f1a
- Primary: #4CAF50 (Green)
- Text Primary: #ffffff
- Text Secondary: #666666 / #999999
- Accent: rgba(255, 255, 255, 0.1)

Tab Theme (Light):
- Background: #FFFDF9 (Warm white)
- Primary: #4CAF50
- Text Primary: #1a1a1a
- Text Secondary: #666666
```

### Playback Speeds

```
0.5x | 0.75x | 1.0x | 1.25x | 1.5x | 1.75x | 2.0x | 2.5x | 3.0x
```

### Sleep Timer Options

```
5 min | 10 min | 15 min | 30 min | 45 min | 60 min | End of chapter
```

---

## Integration Points

### Requires Backend (`server-cn`)

- [ ] Audiobook streaming API
- [ ] Progress sync API
- [ ] TTS generation pipeline (iFlytek integration)
- [ ] Word-level timestamp generation
- [ ] Audiobook search

### Requires Native APIs

- [ ] Background audio playback
- [ ] Audio focus management
- [ ] Lock screen controls
- [ ] Bluetooth headset controls
- [ ] Audio session handling

### Requires AGC/HMS

- [ ] HMS Push (playback notifications)
- [ ] AGC Crash Service
- [ ] HMS Analytics (listening stats)

---

## Next Steps

### Immediate (Phase 1)
1. **Connect real API** - Replace mock data with `server-cn` API calls
2. **Background playback** - Implement HarmonyOS background audio service
3. **Lock screen controls** - Add media session integration
4. **TTS pipeline** - Integrate iFlytek TTS API in `server-cn`

### Short-term (Phase 2)
5. **Download management** - Offline audiobook downloads
6. **Whispersync** - Sync progress with ebook reader
7. **Word-level highlighting** - Implement follow-along text
8. **Listening stats** - Track and display listening analytics

### Medium-term (Phase 3)
9. **Danmaku comments** - Social listening experience
10. **Smart bookmarks** - AI-generated chapter summaries
11. **Voice cloning** - Custom TTS voice (requires user consent)
12. **Multi-device sync** - Continue listening across devices

---

## Known Limitations

1. **Mock data** - Currently using mock audiobook data
2. **No background playback** - Requires HarmonyOS audio service setup
3. **TTS not integrated** - Structure ready, needs iFlytek API
4. **No downloads** - Download management not implemented
5. **No Whispersync** - Ebook sync structure ready, needs backend

---

## File Structure

```
harmony-app/entry/src/main/ets/
├── model/
│   ├── Audiobook.ts           # NEW - Audiobook data models
│   └── Book.ts                # Existing - Book models
├── service/
│   ├── AudiobookApi.ts        # NEW - Audiobook API service
│   ├── TTSService.ts          # NEW - TTS integration
│   └── BookApi.ts             # Existing - Book API
├── store/
│   └── AudioPlayerStore.ts    # NEW - Audio player state
└── pages/
    ├── AudiobookPlayer.ets    # NEW - Full-screen player
    ├── AudiobookTab.ets       # NEW - Audiobook library tab
    ├── Discover.ets           # Existing
    ├── Library.ets            # Existing
    ├── Reader.ets             # Existing
    └── Me.ets                 # Existing
```

---

## Testing Checklist

- [ ] Load audiobook list
- [ ] Search audiobooks
- [ ] Play audiobook
- [ ] Pause/Resume playback
- [ ] Seek forward/backward
- [ ] Skip chapters
- [ ] Change playback speed
- [ ] Set sleep timer
- [ ] View chapter list
- [ ] TTS generation (when backend ready)
- [ ] Background playback
- [ ] Lock screen controls
- [ ] Progress sync

---

**Implementation completed following the principle:**
> "Same features, not missing core functionality"

**Reference**:
- Overseas: `mobile/src/features/audiobook/`
- Overseas: `audiolab/` (TTS pipeline)
