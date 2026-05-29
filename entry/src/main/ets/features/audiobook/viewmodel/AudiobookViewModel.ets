// L3 Feature - Audiobook - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import type { PlayAudiobookIntent } from '../../../core/intent/Intent';
import { TtsService } from '../service/TtsService';
import { AudiobookService } from '../service/AudiobookService';
import { audioPlayerStore } from '../../../store/AudioPlayerStore';
import { AUDIOBOOK_INTENT_KINDS } from '../intent/AudiobookIntents';
import type {
  SetSpeedIntent,
  SetSleepTimerIntent,
  SetVoiceIntent,
  AudiobookSearchIntent,
  AudiobookOpenDetailIntent,
  AudiobookRequestDownloadIntent,
} from '../intent/AudiobookIntents';
import type { PlaybackSpeed, SleepTimerOption } from '../../../model/Audiobook';
import type { AudiobookItem, AudiobookDetailItem, VoiceItem } from '../../../api/audiobooks/AudiobookApi';

export interface AudiobookCatalogState {
  // playback
  readonly bookId: string;
  readonly chapterId: string;
  readonly playing: boolean;
  readonly speed: PlaybackSpeed;
  readonly sleepTimer: SleepTimerOption | null;
  readonly voiceId: string;
  // catalog
  readonly searchResults?: AudiobookItem[];
  readonly popular?: AudiobookItem[];
  readonly recentlyListened?: AudiobookItem[];
  readonly selected?: AudiobookDetailItem;
  readonly voices?: VoiceItem[];
  readonly downloadProgress?: Map<string, number>;
  readonly paywallVisible?: boolean;
}

export type AudiobookState = ViewModelState<AudiobookCatalogState>;

export type AudiobookStateListener = (state: ViewModelState<AudiobookCatalogState>) => void;

export class AudiobookViewModel extends FeatureViewModel<AudiobookCatalogState> {
  readonly kind = 'audiobook';

  private readonly ttsService: TtsService = TtsService.getInstance();
  private readonly catalogService: AudiobookService = AudiobookService.getInstance();
  private stateListeners: AudiobookStateListener[] = [];

  constructor() {
    super(AUDIOBOOK_INTENT_KINDS as never);
  }

  subscribeState(cb: AudiobookStateListener): () => void {
    this.stateListeners.push(cb);
    try { cb(this.getState()); } catch (_e) { /* swallow */ }
    return () => {
      const idx = this.stateListeners.indexOf(cb);
      if (idx > -1) this.stateListeners.splice(idx, 1);
    };
  }

  private notifyListeners(): void {
    const s = this.getState();
    for (let i = 0; i < this.stateListeners.length; i++) {
      try { this.stateListeners[i](s); } catch (_e) { /* swallow */ }
    }
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    // Module-local intent kinds handled via string comparison since they are
    // not part of AnyIntent union (hard constraint: don't touch core/intent/Intent.ets).
    const k = intent.kind as string;
    switch (k) {
      case 'audiobook.play':
        await this.handlePlay(intent as PlayAudiobookIntent);
        break;
      case 'audiobook.pause':
        this.handlePause();
        break;
      case 'audiobook.setSpeed':
        this.handleSetSpeed(intent as unknown as SetSpeedIntent);
        break;
      case 'audiobook.setSleepTimer':
        this.handleSetSleepTimer(intent as unknown as SetSleepTimerIntent);
        break;
      case 'audiobook.setVoice':
        this.handleSetVoice(intent as unknown as SetVoiceIntent);
        break;
      case 'audiobook.search':
        await this.handleSearch(intent as unknown as AudiobookSearchIntent);
        break;
      case 'audiobook.loadPopular':
        await this.handleLoadPopular();
        break;
      case 'audiobook.loadRecentlyListened':
        await this.handleLoadRecentlyListened();
        break;
      case 'audiobook.openDetail':
        await this.handleOpenDetail(intent as unknown as AudiobookOpenDetailIntent);
        break;
      case 'audiobook.requestDownload':
        await this.handleRequestDownload(intent as unknown as AudiobookRequestDownloadIntent);
        break;
      case 'audiobook.continueListening':
        this.handleContinueListening();
        break;
      default:
        break;
    }
    this.notifyListeners();
  }

  private async handlePlay(intent: PlayAudiobookIntent): Promise<void> {
    const { bookId, chapterId } = intent.payload;
    const prev = this.state.status === 'data' ? this.state.data : null;
    this.state = { status: 'loading' };

    try {
      const speed: PlaybackSpeed = prev?.speed ?? 1.0;
      const voiceId = prev?.voiceId ?? this.ttsService.getAvailableVoices()[0]?.id ?? '';

      this.ttsService.setSpeed(speed);
      if (voiceId) this.ttsService.setVoice(voiceId);

      audioPlayerStore.play();

      this.state = {
        status: 'data',
        data: {
          bookId,
          chapterId: chapterId ?? '',
          playing: true,
          speed,
          sleepTimer: prev?.sleepTimer ?? null,
          voiceId,
          popular: prev?.popular,
          recentlyListened: prev?.recentlyListened,
          searchResults: prev?.searchResults,
          selected: prev?.selected,
          voices: prev?.voices,
          downloadProgress: prev?.downloadProgress,
          paywallVisible: false,
        },
      };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'play_failed', message: (e as Error).message },
      };
    }
  }

  private handlePause(): void {
    audioPlayerStore.pause();
    if (this.state.status === 'data') {
      this.state = { status: 'data', data: { ...this.state.data, playing: false } };
    }
  }

  private handleSetSpeed(intent: SetSpeedIntent): void {
    const { speed } = intent.payload;
    this.ttsService.setSpeed(speed);
    audioPlayerStore.setPlaybackSpeed(speed);
    if (this.state.status === 'data') {
      this.state = { status: 'data', data: { ...this.state.data, speed } };
    }
  }

  private handleSetSleepTimer(intent: SetSleepTimerIntent): void {
    const { option } = intent.payload;
    audioPlayerStore.setSleepTimer(option);
    if (this.state.status === 'data') {
      this.state = { status: 'data', data: { ...this.state.data, sleepTimer: option } };
    }
  }

  private handleSetVoice(intent: SetVoiceIntent): void {
    const { voiceId } = intent.payload;
    this.ttsService.setVoice(voiceId);
    audioPlayerStore.setVoice(voiceId);
    if (this.state.status === 'data') {
      this.state = { status: 'data', data: { ...this.state.data, voiceId } };
    }
  }

  private async handleSearch(intent: AudiobookSearchIntent): Promise<void> {
    const prev = this.state.status === 'data' ? this.state.data : null;
    const base = AudiobookViewModel.emptyBase(prev);
    this.state = { status: 'loading' };
    try {
      const result = await this.catalogService.search(intent.payload.query);
      this.state = {
        status: 'data',
        data: { ...base, searchResults: result.items },
      };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'search_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadPopular(): Promise<void> {
    const prev = this.state.status === 'data' ? this.state.data : null;
    const base = AudiobookViewModel.emptyBase(prev);
    this.state = { status: 'loading' };
    try {
      const popular = await this.catalogService.popular();
      this.state = { status: 'data', data: { ...base, popular } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_popular_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadRecentlyListened(): Promise<void> {
    const prev = this.state.status === 'data' ? this.state.data : null;
    const base = AudiobookViewModel.emptyBase(prev);
    this.state = { status: 'loading' };
    try {
      const recentlyListened = await this.catalogService.recentlyListened();
      this.state = { status: 'data', data: { ...base, recentlyListened } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_recent_failed', message: (e as Error).message } };
    }
  }

  private async handleOpenDetail(intent: AudiobookOpenDetailIntent): Promise<void> {
    const prev = this.state.status === 'data' ? this.state.data : null;
    const base = AudiobookViewModel.emptyBase(prev);
    this.state = { status: 'loading' };
    try {
      const selected = await this.catalogService.getDetail(intent.payload.audiobookId);
      const voices = selected.voiceOptions ?? [];
      this.state = { status: 'data', data: { ...base, selected, voices } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'open_detail_failed', message: (e as Error).message } };
    }
  }

  private async handleRequestDownload(intent: AudiobookRequestDownloadIntent): Promise<void> {
    const prev = this.state.status === 'data' ? this.state.data : null;
    if (!prev) return;
    const { audiobookId } = intent.payload;

    // Subscription gate
    const mockItem = prev.selected?.id === audiobookId
      ? prev.selected
      : prev.popular?.find((a) => a.id === audiobookId)
        ?? prev.recentlyListened?.find((a) => a.id === audiobookId);
    if (mockItem && !this.catalogService.canPlay(mockItem)) {
      this.state = { status: 'data', data: { ...prev, paywallVisible: true } };
      return;
    }

    const progressMap = new Map(prev.downloadProgress ?? []);
    progressMap.set(audiobookId, 0);
    this.state = { status: 'data', data: { ...prev, downloadProgress: progressMap } };

    try {
      await this.catalogService.download(audiobookId);
      const done = new Map(progressMap);
      done.set(audiobookId, 100);
      if (this.state.status === 'data') {
        this.state = { status: 'data', data: { ...this.state.data, downloadProgress: done } };
      }
    } catch (e) {
      this.state = { status: 'error', error: { code: 'download_failed', message: (e as Error).message } };
    }
  }

  private handleContinueListening(): void {
    const store = audioPlayerStore;
    if (store.audiobook && store.audiobook.id) {
      store.play();
    }
  }

  /** Build a base data object from previous state, preserving catalog fields. */
  private static emptyBase(prev: AudiobookCatalogState | null): AudiobookCatalogState {
    return {
      bookId: prev?.bookId ?? '',
      chapterId: prev?.chapterId ?? '',
      playing: prev?.playing ?? false,
      speed: prev?.speed ?? 1.0,
      sleepTimer: prev?.sleepTimer ?? null,
      voiceId: prev?.voiceId ?? '',
      popular: prev?.popular,
      recentlyListened: prev?.recentlyListened,
      searchResults: prev?.searchResults,
      selected: prev?.selected,
      voices: prev?.voices,
      downloadProgress: prev?.downloadProgress,
      paywallVisible: false,
    };
  }

  loadVoices(): void {
    const voices = this.ttsService.getAvailableVoices();
    audioPlayerStore.setVoices(voices);
  }
}
