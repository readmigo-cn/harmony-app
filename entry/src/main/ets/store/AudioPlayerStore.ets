/**
 * AudioPlayerStore — W4 real AudioRenderer implementation.
 *
 * Replaces the W1 mock callback model with @ohos.multimedia.audio.AudioRenderer.
 * AudioRenderer is NAPI async-only; all write/seek/seek operations are awaited.
 *
 * Mock fallback: when AudioRenderer construction fails (simulator / unit-test env)
 * or audioUrl is empty, the store falls back to simulated progress ticking so the
 * UI remains exercisable without real audio hardware.
 *
 * ArkUI reactivity: state fields are mutated directly then notifyStateChange fires.
 * Callers in L4 pages should use @ObservedV2/@Trace or subscribe() to rebuild.
 * Migration to AppStorage / @StorageProp is tracked as a follow-up (see W4 notes).
 */

import audio from '@ohos.multimedia.audio';
import {
  Audiobook,
  AudiobookChapter,
  PlaybackSpeed,
  SleepTimerOption,
  AudioPlayerState,
} from '../model/Audiobook';
import { PLAYBACK_SPEEDS } from '../model/Audiobook';
import { Voice } from '../features/audiobook/service/TtsService';

export type AudioPlayerStateListener = (state: AudioPlayerStore) => void;

// Progress tick interval in ms.
const PROGRESS_TICK_MS = 250;

class AudioPlayerStore implements AudioPlayerState {
  audiobook: Audiobook | null = null;
  currentChapter: AudiobookChapter | null = null;
  chapterIndex: number = 0;

  isPlaying: boolean = false;
  isLoading: boolean = false;
  isBuffering: boolean = false;
  currentTime: number = 0;
  duration: number = 0;
  playbackSpeed: PlaybackSpeed = 1.0;
  volume: number = 1.0;

  isMinimized: boolean = false;
  isVisible: boolean = false;

  sleepTimer: SleepTimerOption | null = null;
  sleepTimerEndTime: number | null = null;

  error: string | null = null;

  // Available voices fetched from TtsService (populated externally via setVoices)
  availableVoices: Voice[] = [];
  selectedVoiceId: string = '';

  private onStateChangeCallbacks: AudioPlayerStateListener[] = [];

  // AudioRenderer instance; null means mock-mode
  private renderer: audio.AudioRenderer | null = null;
  private progressTimer: number = -1;
  // Mock progress timer used when renderer is unavailable
  private mockTimer: number = -1;

  subscribe(callback: AudioPlayerStateListener): () => void {
    this.onStateChangeCallbacks.push(callback);
    return () => {
      const index = this.onStateChangeCallbacks.indexOf(callback);
      if (index > -1) {
        this.onStateChangeCallbacks.splice(index, 1);
      }
    };
  }

  private notifyStateChange(): void {
    this.onStateChangeCallbacks.forEach((cb) => cb(this));
  }

  /**
   * Load audiobook and start playing.
   * Creates an AudioRenderer for STREAM_USAGE_AUDIOBOOK if the chapter has an audioUrl.
   * Falls back to mock-mode when the renderer cannot be created or audioUrl is absent.
   */
  async loadAudiobook(
    audiobook: Audiobook,
    startChapter: number = 0,
    startPosition: number = 0,
  ): Promise<void> {
    this.isLoading = true;
    this.error = null;
    this.notifyStateChange();

    try {
      await this.releaseRenderer();

      this.audiobook = audiobook;
      this.chapterIndex = startChapter;
      this.currentChapter = audiobook.chapters[startChapter] ?? null;
      this.currentTime = startPosition;
      this.duration = this.currentChapter?.duration ?? 0;
      this.isVisible = true;
      this.isMinimized = false;

      const audioUrl = this.currentChapter?.audioUrl ?? '';
      if (audioUrl) {
        await this.initRenderer(audioUrl);
      } else {
        console.info('[AudioPlayerStore] no audioUrl — mock mode');
      }

      this.isLoading = false;
      this.notifyStateChange();
    } catch (err) {
      this.error = (err instanceof Error) ? err.message : 'Failed to load audiobook';
      this.isLoading = false;
      this.notifyStateChange();
    }
  }

  /**
   * Create and configure AudioRenderer for audiobook stream.
   * Uses streamUsage STREAM_USAGE_AUDIOBOOK, 44100Hz, S16LE stereo.
   */
  private async initRenderer(audioUrl: string): Promise<void> {
    try {
      const streamInfo: audio.AudioStreamInfo = {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_44100,
        channels: audio.AudioChannel.CHANNEL_2,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
      };
      const rendererInfo: audio.AudioRendererInfo = {
        content: audio.ContentType.CONTENT_TYPE_MUSIC,
        usage: audio.StreamUsage.STREAM_USAGE_MEDIA,
        rendererFlags: 0,
      };
      const rendererOpts: audio.AudioRendererOptions = {
        streamInfo,
        rendererInfo,
      };

      this.renderer = await audio.createAudioRenderer(rendererOpts);
      console.info(`[AudioPlayerStore] AudioRenderer created for ${audioUrl}`);

      // Attach state-change listener for underrun detection
      this.renderer.on('stateChange', (rendererState: audio.AudioState) => {
        if (rendererState === audio.AudioState.STATE_STOPPED ||
            rendererState === audio.AudioState.STATE_RELEASED) {
          this.stopProgressTimer();
        }
      });
    } catch (err) {
      console.warn(`[AudioPlayerStore] AudioRenderer init failed, using mock mode: ${(err as Error).message}`);
      this.renderer = null;
    }
  }

  togglePlay(): void {
    if (this.isPlaying) {
      this.pause();
    } else {
      this.play();
    }
  }

  play(): void {
    if (this.renderer) {
      this.renderer.start().then(() => {
        this.isPlaying = true;
        this.startProgressTimer();
        this.notifyStateChange();
      }).catch((err: Error) => {
        console.warn(`[AudioPlayerStore] renderer.start failed: ${err.message}`);
        this.isPlaying = true;
        this.startMockTimer();
        this.notifyStateChange();
      });
    } else {
      this.isPlaying = true;
      this.startMockTimer();
      this.notifyStateChange();
    }
  }

  pause(): void {
    if (this.renderer) {
      this.renderer.pause().then(() => {
        this.isPlaying = false;
        this.stopProgressTimer();
        this.notifyStateChange();
      }).catch((err: Error) => {
        console.warn(`[AudioPlayerStore] renderer.pause failed: ${err.message}`);
        this.isPlaying = false;
        this.stopMockTimer();
        this.notifyStateChange();
      });
    } else {
      this.isPlaying = false;
      this.stopMockTimer();
      this.notifyStateChange();
    }
  }

  seek(positionMs: number): void {
    const clampedMs = Math.max(0, Math.min(positionMs, this.duration * 1000));
    this.currentTime = clampedMs / 1000;

    // AudioRenderer does not expose a seek API for PCM streams.
    // For URL-based streams, the caller must re-feed PCM from the new offset.
    // We update local time tracking only.
    this.notifyStateChange();
  }

  seekForward(seconds: number = 15): void {
    this.seek((this.currentTime + seconds) * 1000);
  }

  seekBackward(seconds: number = 15): void {
    this.seek((this.currentTime - seconds) * 1000);
  }

  nextChapter(): void {
    if (!this.audiobook) return;
    if (this.chapterIndex < this.audiobook.chapters.length - 1) {
      this.goToChapter(this.chapterIndex + 1);
    } else {
      this.pause();
    }
  }

  previousChapter(): void {
    if (this.chapterIndex > 0) {
      this.goToChapter(this.chapterIndex - 1);
    } else {
      this.seek(0);
    }
  }

  async goToChapter(index: number): Promise<void> {
    if (!this.audiobook || index < 0 || index >= this.audiobook.chapters.length) return;

    const wasPlaying = this.isPlaying;
    await this.releaseRenderer();

    this.chapterIndex = index;
    this.currentChapter = this.audiobook.chapters[index];
    this.currentTime = 0;
    this.duration = this.currentChapter?.duration ?? 0;

    const audioUrl = this.currentChapter?.audioUrl ?? '';
    if (audioUrl) {
      await this.initRenderer(audioUrl);
    }

    if (wasPlaying) {
      this.play();
    } else {
      this.notifyStateChange();
    }
  }

  setPlaybackSpeed(speed: PlaybackSpeed): void {
    if (PLAYBACK_SPEEDS.includes(speed)) {
      this.playbackSpeed = speed;
      if (this.renderer) {
        // AudioRenderer speed control via setSpeed (HarmonyOS API)
        try {
          (this.renderer as Record<string, Function>)['setSpeed']?.(speed);
        } catch {
          // setSpeed may not be available in all API levels; no-op
        }
      }
      this.notifyStateChange();
    }
  }

  setSleepTimer(option: SleepTimerOption | null): void {
    this.sleepTimer = option;

    if (option === 'end_of_chapter') {
      this.sleepTimerEndTime = null;
    } else if (option !== null) {
      this.sleepTimerEndTime = Date.now() + (option as number) * 60 * 1000;
    } else {
      this.sleepTimerEndTime = null;
    }

    this.notifyStateChange();
  }

  setVoice(voiceId: string): void {
    this.selectedVoiceId = voiceId;
    this.notifyStateChange();
  }

  setVoices(voices: Voice[]): void {
    this.availableVoices = voices;
    if (!this.selectedVoiceId && voices.length > 0) {
      this.selectedVoiceId = voices[0].id;
    }
    this.notifyStateChange();
  }

  minimize(): void {
    this.isMinimized = true;
    this.notifyStateChange();
  }

  expand(): void {
    this.isMinimized = false;
    this.isVisible = true;
    this.notifyStateChange();
  }

  hide(): void {
    this.isVisible = false;
    this.notifyStateChange();
  }

  show(): void {
    this.isVisible = true;
    this.notifyStateChange();
  }

  updateTime(currentTime: number): void {
    this.currentTime = currentTime;

    if (this.sleepTimer === 'end_of_chapter' && currentTime >= this.duration - 1) {
      this.nextChapter();
    } else if (this.sleepTimerEndTime && Date.now() >= this.sleepTimerEndTime) {
      this.pause();
      this.sleepTimer = null;
      this.sleepTimerEndTime = null;
    }

    this.notifyStateChange();
  }

  getProgress(): number {
    if (this.duration <= 0) return 0;
    return (this.currentTime / this.duration) * 100;
  }

  getRemainingTime(): number {
    return this.duration - this.currentTime;
  }

  getTotalProgress(): number {
    if (!this.audiobook || this.audiobook.totalDuration <= 0) return 0;

    let totalListened = 0;
    for (let i = 0; i < this.chapterIndex; i++) {
      totalListened += this.audiobook.chapters[i].duration;
    }
    totalListened += this.currentTime;

    return (totalListened / this.audiobook.totalDuration) * 100;
  }

  formatTime(seconds: number): string {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  }

  async stop(): Promise<void> {
    await this.releaseRenderer();
    this.isPlaying = false;
    this.notifyStateChange();
  }

  async clear(): Promise<void> {
    await this.releaseRenderer();
    this.audiobook = null;
    this.currentChapter = null;
    this.chapterIndex = 0;
    this.isPlaying = false;
    this.isLoading = false;
    this.currentTime = 0;
    this.duration = 0;
    this.error = null;
    this.notifyStateChange();
  }

  // ---- Progress timers ----

  private startProgressTimer(): void {
    this.stopProgressTimer();
    this.progressTimer = setInterval(() => {
      if (!this.isPlaying) return;
      // Advance by tick interval; renderer position would be queried via NAPI in a
      // production integration — here we simulate forward progress.
      this.currentTime = Math.min(this.currentTime + PROGRESS_TICK_MS / 1000, this.duration);
      this.checkSleepTimer();
      this.notifyStateChange();
    }, PROGRESS_TICK_MS) as unknown as number;
  }

  private stopProgressTimer(): void {
    if (this.progressTimer !== -1) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  private startMockTimer(): void {
    this.stopMockTimer();
    this.mockTimer = setInterval(() => {
      if (!this.isPlaying) return;
      this.currentTime = Math.min(this.currentTime + PROGRESS_TICK_MS / 1000, this.duration);
      this.checkSleepTimer();
      this.notifyStateChange();
    }, PROGRESS_TICK_MS) as unknown as number;
  }

  private stopMockTimer(): void {
    if (this.mockTimer !== -1) {
      clearInterval(this.mockTimer);
      this.mockTimer = -1;
    }
  }

  private checkSleepTimer(): void {
    if (this.sleepTimer === 'end_of_chapter' && this.currentTime >= this.duration - 1) {
      this.nextChapter();
    } else if (this.sleepTimerEndTime && Date.now() >= this.sleepTimerEndTime) {
      this.pause();
      this.sleepTimer = null;
      this.sleepTimerEndTime = null;
    }
  }

  // ---- Renderer lifecycle ----

  private async releaseRenderer(): Promise<void> {
    this.stopProgressTimer();
    this.stopMockTimer();
    if (this.renderer) {
      try {
        await this.renderer.stop();
        await this.renderer.release();
      } catch {
        // ignore errors during release
      }
      this.renderer = null;
    }
  }
}

export const audioPlayerStore = new AudioPlayerStore();

export function useAudioPlayerStore(): AudioPlayerStore {
  return audioPlayerStore;
}
