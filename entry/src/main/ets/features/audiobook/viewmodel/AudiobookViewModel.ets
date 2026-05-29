// L3 Feature - Audiobook - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import type { PlayAudiobookIntent } from '../../../core/intent/Intent';
import { TtsService } from '../service/TtsService';
import { AUDIOBOOK_INTENT_KINDS } from '../intent/AudiobookIntents';

export interface AudiobookData {
  readonly bookId: string;
  readonly chapterId: string;
  readonly playing: boolean;
  readonly speed: number;
}

export type AudiobookState = ViewModelState<AudiobookData>;

export class AudiobookViewModel extends FeatureViewModel<AudiobookData> {
  readonly kind = 'audiobook';

  private readonly ttsService: TtsService = TtsService.getInstance();

  constructor() {
    super(AUDIOBOOK_INTENT_KINDS);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    switch (intent.kind) {
      case 'audiobook.play':
        await this.handlePlay(intent as PlayAudiobookIntent);
        break;
      case 'audiobook.pause':
        this.handlePause();
        break;
      default:
        break;
    }
  }

  private async handlePlay(intent: PlayAudiobookIntent): Promise<void> {
    const { bookId, chapterId } = intent.payload;
    this.state = { status: 'loading' };
    try {
      const currentSpeed = this.state.status === 'data' ? this.state.data.speed : 1.0;
      this.ttsService.setSpeed(currentSpeed);
      this.state = {
        status: 'data',
        data: { bookId, chapterId: chapterId ?? '', playing: true, speed: currentSpeed },
      };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'play_failed', message: (e as Error).message } };
    }
  }

  private handlePause(): void {
    if (this.state.status === 'data') {
      this.state = { status: 'data', data: { ...this.state.data, playing: false } };
    }
  }
}
