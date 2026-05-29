// L3 Feature - Reader - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import type {
  OpenBookIntent,
  JumpToChapterIntent,
  JumpToPageIntent,
  SelectTextIntent,
  LookupWordIntent,
} from '../../../core/intent/Intent';
import { HighlightService } from '../service/HighlightService';
import { ReadingSession } from '../service/ReadingSession';
import { READER_INTENT_KINDS } from '../intent/ReaderIntents';

export interface ReaderData {
  readonly bookId: string;
  readonly chapterId: string;
  readonly pageIdx: number;
  readonly selectedText: string;
  readonly lastWordLookedUp: string;
}

export type ReaderState = ViewModelState<ReaderData>;

export class ReaderViewModel extends FeatureViewModel<ReaderData> {
  readonly kind = 'reader';

  constructor() {
    super(READER_INTENT_KINDS);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    switch (intent.kind) {
      case 'reader.openBook':
        await this.handleOpenBook(intent as OpenBookIntent);
        break;
      case 'reader.jumpToChapter':
        this.handleJumpToChapter(intent as JumpToChapterIntent);
        break;
      case 'reader.jumpToPage':
        this.handleJumpToPage(intent as JumpToPageIntent);
        break;
      case 'reader.selectText':
        this.handleSelectText(intent as SelectTextIntent);
        break;
      case 'reader.openHighlightLayer':
      case 'reader.openTocSheet':
      case 'reader.openSettings':
        // UI sheet intents — adapters will handle these via direct callbacks in W2
        break;
      case 'reader.lookupWord':
        this.handleLookupWord(intent as LookupWordIntent);
        break;
      default:
        break;
    }
  }

  private async handleOpenBook(intent: OpenBookIntent): Promise<void> {
    const { bookId } = intent.payload;
    this.state = { status: 'loading' };
    try {
      await HighlightService.list(bookId);
      await ReadingSession.start(bookId, 0);
      this.state = {
        status: 'data',
        data: { bookId, chapterId: '', pageIdx: 0, selectedText: '', lastWordLookedUp: '' },
      };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'open_book_failed', message: (e as Error).message } };
    }
  }

  private handleJumpToChapter(intent: JumpToChapterIntent): void {
    const { chapterId } = intent.payload;
    ReadingSession.recordChapterChange(0);
    if (this.state.status === 'data') {
      this.state = { status: 'data', data: { ...this.state.data, chapterId, pageIdx: 0 } };
    }
  }

  private handleJumpToPage(intent: JumpToPageIntent): void {
    if (this.state.status === 'data') {
      this.state = { status: 'data', data: { ...this.state.data, pageIdx: intent.payload.pageIdx } };
    }
  }

  private handleSelectText(intent: SelectTextIntent): void {
    const text = `${intent.payload.range.startCharOffset}-${intent.payload.range.endCharOffset}`;
    if (this.state.status === 'data') {
      this.state = { status: 'data', data: { ...this.state.data, selectedText: text } };
    }
  }

  private handleLookupWord(intent: LookupWordIntent): void {
    ReadingSession.recordWordLookup();
    if (this.state.status === 'data') {
      this.state = { status: 'data', data: { ...this.state.data, lastWordLookedUp: intent.payload.word } };
    }
  }
}
