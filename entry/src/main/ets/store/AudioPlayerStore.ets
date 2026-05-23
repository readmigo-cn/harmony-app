/**
 * Audio Player Store - Global state management for audiobook playback
 * 功能对齐：mobile/src/features/audiobook/stores/audioPlayerStore.ts
 * 
 * Features:
 * - Playback state management
 * - Progress tracking
 * - Sleep timer
 * - Chapter navigation
 * - Speed control
 */

import {
  Audiobook,
  AudiobookChapter,
  PlaybackSpeed,
  SleepTimerOption,
  AudioPlayerState,
} from '../model/Audiobook';
import { PLAYBACK_SPEEDS } from '../model/Audiobook';

export type AudioPlayerStateListener = (state: AudioPlayerStore) => void;

// Store state
class AudioPlayerStore implements AudioPlayerState {
  // Current audiobook
  audiobook: Audiobook | null = null;
  currentChapter: AudiobookChapter | null = null;
  chapterIndex: number = 0;

  // Playback state
  isPlaying: boolean = false;
  isLoading: boolean = false;
  isBuffering: boolean = false;
  currentTime: number = 0;
  duration: number = 0;
  playbackSpeed: PlaybackSpeed = 1.0;
  volume: number = 1.0;

  // UI state
  isMinimized: boolean = false;
  isVisible: boolean = false;

  // Sleep timer
  sleepTimer: SleepTimerOption | null = null;
  sleepTimerEndTime: number | null = null;

  // Error
  error: string | null = null;

  // Callbacks
  private onStateChangeCallbacks: AudioPlayerStateListener[] = [];

  /**
   * Subscribe to state changes
   */
  subscribe(callback: AudioPlayerStateListener): () => void {
    this.onStateChangeCallbacks.push(callback);
    return () => {
      const index = this.onStateChangeCallbacks.indexOf(callback);
      if (index > -1) {
        this.onStateChangeCallbacks.splice(index, 1);
      }
    };
  }

  /**
   * Notify state change listeners
   */
  private notifyStateChange() {
    this.onStateChangeCallbacks.forEach(callback => callback(this));
  }

  /**
   * Load audiobook and start playing
   */
  async loadAudiobook(
    audiobook: Audiobook,
    startChapter: number = 0,
    startPosition: number = 0
  ) {
    this.isLoading = true;
    this.error = null;

    try {
      this.audiobook = audiobook;
      this.chapterIndex = startChapter;
      this.currentChapter = audiobook.chapters[startChapter];
      this.currentTime = startPosition;
      this.duration = this.currentChapter?.duration || 0;
      this.isVisible = true;
      this.isMinimized = false;

      // TODO: Initialize audio player with chapter URL
      // await this.initializePlayer(this.currentChapter.audioUrl);

      this.isLoading = false;
      this.notifyStateChange();
    } catch (err) {
      this.error = err instanceof Error ? err.message : 'Failed to load audiobook';
      this.isLoading = false;
      this.notifyStateChange();
    }
  }

  /**
   * Toggle play/pause
   */
  togglePlay() {
    if (this.isPlaying) {
      this.pause();
    } else {
      this.play();
    }
  }

  /**
   * Start playback
   */
  play() {
    this.isPlaying = true;
    // TODO: Call native audio player play()
    this.notifyStateChange();
  }

  /**
   * Pause playback
   */
  pause() {
    this.isPlaying = false;
    // TODO: Call native audio player pause()
    this.notifyStateChange();
  }

  /**
   * Seek to position
   */
  seek(position: number) {
    this.currentTime = Math.max(0, Math.min(position, this.duration));
    // TODO: Call native audio player seek(position)
    this.notifyStateChange();
  }

  /**
   * Seek forward by seconds
   */
  seekForward(seconds: number = 15) {
    this.seek(this.currentTime + seconds);
  }

  /**
   * Seek backward by seconds
   */
  seekBackward(seconds: number = 15) {
    this.seek(this.currentTime - seconds);
  }

  /**
   * Go to next chapter
   */
  nextChapter() {
    if (!this.audiobook) return;

    if (this.chapterIndex < this.audiobook.chapters.length - 1) {
      this.goToChapter(this.chapterIndex + 1);
    } else {
      // End of book
      this.pause();
    }
  }

  /**
   * Go to previous chapter
   */
  previousChapter() {
    if (this.chapterIndex > 0) {
      this.goToChapter(this.chapterIndex - 1);
    } else {
      // Beginning of book, restart chapter
      this.seek(0);
    }
  }

  /**
   * Go to specific chapter
   */
  goToChapter(index: number) {
    if (!this.audiobook || index < 0 || index >= this.audiobook.chapters.length) return;

    this.chapterIndex = index;
    this.currentChapter = this.audiobook.chapters[index];
    this.currentTime = 0;
    this.duration = this.currentChapter?.duration || 0;

    // TODO: Load new chapter audio
    // this.initializePlayer(this.currentChapter.audioUrl);

    this.notifyStateChange();
  }

  /**
   * Set playback speed
   */
  setPlaybackSpeed(speed: PlaybackSpeed) {
    if (PLAYBACK_SPEEDS.includes(speed)) {
      this.playbackSpeed = speed;
      // TODO: Call native audio player setSpeed(speed)
      this.notifyStateChange();
    }
  }

  /**
   * Set sleep timer
   */
  setSleepTimer(option: SleepTimerOption | null) {
    this.sleepTimer = option;

    if (option === 'end_of_chapter') {
      // Will stop at end of current chapter
      this.sleepTimerEndTime = null;
    } else if (option !== null) {
      // Set timer for specified minutes
      this.sleepTimerEndTime = Date.now() + (option as number) * 60 * 1000;
    } else {
      this.sleepTimerEndTime = null;
    }

    this.notifyStateChange();
  }

  /**
   * Minimize player
   */
  minimize() {
    this.isMinimized = true;
    this.notifyStateChange();
  }

  /**
   * Expand player
   */
  expand() {
    this.isMinimized = false;
    this.isVisible = true;
    this.notifyStateChange();
  }

  /**
   * Hide player
   */
  hide() {
    this.isVisible = false;
    this.notifyStateChange();
  }

  /**
   * Show player
   */
  show() {
    this.isVisible = true;
    this.notifyStateChange();
  }

  /**
   * Update current time (called by audio player)
   */
  updateTime(currentTime: number) {
    this.currentTime = currentTime;

    // Check sleep timer
    if (this.sleepTimer === 'end_of_chapter' && currentTime >= this.duration - 1) {
      this.nextChapter();
    } else if (this.sleepTimerEndTime && Date.now() >= this.sleepTimerEndTime) {
      this.pause();
      this.sleepTimer = null;
      this.sleepTimerEndTime = null;
    }

    this.notifyStateChange();
  }

  /**
   * Get current progress as percentage
   */
  getProgress(): number {
    if (this.duration <= 0) return 0;
    return (this.currentTime / this.duration) * 100;
  }

  /**
   * Get remaining time in current chapter
   */
  getRemainingTime(): number {
    return this.duration - this.currentTime;
  }

  /**
   * Get total book progress
   */
  getTotalProgress(): number {
    if (!this.audiobook || this.audiobook.totalDuration <= 0) return 0;

    let totalListened = 0;
    for (let i = 0; i < this.chapterIndex; i++) {
      totalListened += this.audiobook.chapters[i].duration;
    }
    totalListened += this.currentTime;

    return (totalListened / this.audiobook.totalDuration) * 100;
  }

  /**
   * Format time for display
   */
  formatTime(seconds: number): string {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  }

  /**
   * Clear current audiobook
   */
  clear() {
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
}

// Singleton instance
export const audioPlayerStore = new AudioPlayerStore();

/**
 * Hook-like function for ArkTS components to get store state
 */
export function useAudioPlayerStore(): AudioPlayerStore {
  return audioPlayerStore;
}

// PHASE 2 FOLLOWUP: replace callback subscribe with @ObservedV2 + @Trace decorators
// or migrate to AppStorage so ArkUI @State / @StorageLink can subscribe directly.
// Current callback model does NOT trigger ArkUI rebuild — UI changes rely on
// upstream wrappers. See docs/specs/2026-05-17-harmony-app-feature-first-design.md §8.
