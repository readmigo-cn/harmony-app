// L3 Feature - Reader - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import type { AnyIntent } from '../../../core/intent/Intent';
import type {
  OpenBookIntent,
  JumpToChapterIntent,
  SelectTextIntent,
  LookupWordIntent,
} from '../../../core/intent/Intent';
import { HighlightService } from '../service/HighlightService';
import { ReadingSession } from '../service/ReadingSession';
import { READER_INTENT_KINDS } from '../intent/ReaderIntents';

export interface ReaderState {
  readonly bookId: string;
  readonly chapterId: string;
  readonly charOffset: number;
  readonly selectedText: string;
  readonly lastWordLookedUp: string;
  readonly loading: boolean;
  readonly error: string | null;
}

const INITIAL_STATE: ReaderState = {
  bookId: '',
  chapterId: '',
  charOffset: 0,
  selectedText: '',
  lastWordLookedUp: '',
  loading: false,
  error: null,
};

export class ReaderViewModel extends FeatureViewModel<ReaderState> {
  readonly kind = 'reader';

  constructor() {
    super(INITIAL_STATE);
  }

  init(): () => void {
    const bus = IntentBus.getInstance();
    const unsubs = READER_INTENT_KINDS.map((k) =>
      bus.subscribe(k, (intent) => this.handle(intent)),
    );
    return () => unsubs.forEach((u) => u());
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    switch (intent.kind) {
      case 'reader/open-book':
        await this.handleOpenBook(intent as OpenBookIntent);
        break;
      case 'reader/jump-to-chapter':
        await this.handleJumpToChapter(intent as JumpToChapterIntent);
        break;
      case 'reader/select-text':
        this.handleSelectText(intent as SelectTextIntent);
        break;
      case 'reader/lookup-word':
        this.handleLookupWord(intent as LookupWordIntent);
        break;
      default:
        break;
    }
  }

  private async handleOpenBook(intent: OpenBookIntent): Promise<void> {
    const { bookId } = intent.payload;
    this.state = { ...this.state, bookId, loading: true, error: null };
    try {
      await HighlightService.list(bookId);
      await ReadingSession.start(bookId, 0);
      this.state = { ...this.state, loading: false };
    } catch (e) {
      this.state = { ...this.state, loading: false, error: (e as Error).message };
    }
  }

  private async handleJumpToChapter(intent: JumpToChapterIntent): Promise<void> {
    const { bookId, chapterId, charOffset } = intent.payload;
    this.state = { ...this.state, bookId, chapterId, charOffset };
    ReadingSession.recordChapterChange(0);
  }

  private handleSelectText(intent: SelectTextIntent): void {
    this.state = { ...this.state, selectedText: intent.payload.selectedText };
  }

  private handleLookupWord(intent: LookupWordIntent): void {
    ReadingSession.recordWordLookup();
    this.state = { ...this.state, lastWordLookedUp: intent.payload.word };
  }
}
