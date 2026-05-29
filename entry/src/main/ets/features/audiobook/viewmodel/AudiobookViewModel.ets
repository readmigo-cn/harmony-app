// L3 Feature - Audiobook - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import type { AnyIntent } from '../../../core/intent/Intent';
import type {
  PlayAudiobookIntent,
  PauseAudiobookIntent,
  SeekAudiobookIntent,
  AdjustPlaybackSpeedIntent,
} from '../../../core/intent/Intent';
import { TtsService } from '../service/TtsService';
import { AUDIOBOOK_INTENT_KINDS } from '../intent/AudiobookIntents';

export interface AudiobookState {
  readonly bookId: string;
  readonly chapterId: string;
  readonly positionMs: number;
  readonly speed: number;
  readonly playing: boolean;
  readonly loading: boolean;
  readonly error: string | null;
}

const INITIAL_STATE: AudiobookState = {
  bookId: '',
  chapterId: '',
  positionMs: 0,
  speed: 1.0,
  playing: false,
  loading: false,
  error: null,
};

export class AudiobookViewModel extends FeatureViewModel<AudiobookState> {
  readonly kind = 'audiobook';

  private readonly ttsService: TtsService = TtsService.getInstance();

  constructor() {
    super(INITIAL_STATE);
  }

  init(): () => void {
    const bus = IntentBus.getInstance();
    const unsubs = AUDIOBOOK_INTENT_KINDS.map((k) =>
      bus.subscribe(k, (intent) => this.handle(intent)),
    );
    return () => unsubs.forEach((u) => u());
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    switch (intent.kind) {
      case 'audiobook/play':
        await this.handlePlay(intent as PlayAudiobookIntent);
        break;
      case 'audiobook/pause':
        this.handlePause(intent as PauseAudiobookIntent);
        break;
      case 'audiobook/seek':
        this.handleSeek(intent as SeekAudiobookIntent);
        break;
      case 'audiobook/adjust-speed':
        this.handleAdjustSpeed(intent as AdjustPlaybackSpeedIntent);
        break;
      default:
        break;
    }
  }

  private async handlePlay(intent: PlayAudiobookIntent): Promise<void> {
    const { bookId, chapterId, positionMs } = intent.payload;
    this.state = { ...this.state, bookId, chapterId, positionMs, loading: true, error: null };
    try {
      this.ttsService.setSpeed(this.state.speed);
      this.state = { ...this.state, playing: true, loading: false };
    } catch (e) {
      this.state = { ...this.state, loading: false, error: (e as Error).message };
    }
  }

  private handlePause(_intent: PauseAudiobookIntent): void {
    this.state = { ...this.state, playing: false };
  }

  private handleSeek(intent: SeekAudiobookIntent): void {
    this.state = { ...this.state, positionMs: intent.payload.positionMs };
  }

  private handleAdjustSpeed(intent: AdjustPlaybackSpeedIntent): void {
    const { speed } = intent.payload;
    this.ttsService.setSpeed(speed);
    this.state = { ...this.state, speed };
  }
}
