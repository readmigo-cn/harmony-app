// L3 Feature - Reader - Progress sub-ViewModel
// Owns: highlights, bookmarks, sessionId, progress tracking
// Handles: saveHighlight / editHighlight / deleteHighlight / saveBookmark / deleteBookmark
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import type {
  SaveHighlightIntent,
  EditHighlightIntent,
  DeleteHighlightIntent,
  SaveBookmarkIntent,
  DeleteBookmarkIntent,
} from '../intent/ReaderIntents';
import { HighlightService } from '../service/HighlightService';
import { BookmarksService } from '../service/BookmarksService';
import type { Bookmark } from '../service/BookmarksService';
import { ReadingSession } from '../service/ReadingSession';
import { ReadingSoul } from '../../../core/distributed-soul/ReadingSoul';
import type { Highlight } from '../../../model/Highlight';

export interface ProgressData {
  highlights: Highlight[];
  bookmarks: Bookmark[];
  sessionId?: string;
  currentChapterId?: string;
  currentBookId?: string;
  currentPageIdx?: number;
}

const PROGRESS_KINDS: ReadonlyArray<string> = [
  'reader.saveHighlight',
  'reader.editHighlight',
  'reader.deleteHighlight',
  'reader.saveBookmark',
  'reader.deleteBookmark',
];

export class ReaderProgressViewModel extends FeatureViewModel<ProgressData> {
  readonly kind = 'reader.progress';

  constructor() {
    super(PROGRESS_KINDS, { status: 'idle' });
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    switch (intent.kind) {
      case 'reader.saveHighlight':
        await this.handleSaveHighlight(intent as SaveHighlightIntent);
        break;
      case 'reader.editHighlight':
        await this.handleEditHighlight(intent as EditHighlightIntent);
        break;
      case 'reader.deleteHighlight':
        await this.handleDeleteHighlight(intent as DeleteHighlightIntent);
        break;
      case 'reader.saveBookmark':
        await this.handleSaveBookmark(intent as SaveBookmarkIntent);
        break;
      case 'reader.deleteBookmark':
        await this.handleDeleteBookmark(intent as DeleteBookmarkIntent);
        break;
      default:
        break;
    }
  }

  initSession(bookId: string, chapterId: string, pageIdx: number, highlights: Highlight[], bookmarks: Bookmark[]): void {
    const sessionId = ReadingSession.start(bookId, chapterId);
    this.state = {
      status: 'data',
      data: { highlights, bookmarks, sessionId, currentBookId: bookId, currentChapterId: chapterId, currentPageIdx: pageIdx },
    };
  }

  updateContext(bookId: string, chapterId: string, pageIdx: number, highlights: Highlight[]): void {
    if (this.state.status !== 'data') return;
    const data = this.state.data;
    if (data.sessionId) ReadingSession.recordChapterChange(data.sessionId, chapterId);
    this.state = {
      status: 'data',
      data: { ...data, currentBookId: bookId, currentChapterId: chapterId, currentPageIdx: pageIdx, highlights },
    };
  }

  recordWordLookup(word: string): void {
    if (this.state.status !== 'data') return;
    const { sessionId } = this.state.data;
    if (sessionId) ReadingSession.recordWordLookup(sessionId, word);
  }

  async syncPosition(bookId: string, chapterId: string, pageIdx: number): Promise<void> {
    await ReadingSoul.setPosition(bookId, chapterId, pageIdx, 0);
  }

  async closeSession(): Promise<void> {
    if (this.state.status !== 'data') return;
    const { sessionId } = this.state.data;
    if (sessionId) await ReadingSession.end(sessionId);
  }

  getProgressData(): ProgressData | null {
    if (this.state.status === 'data') return this.state.data;
    return null;
  }

  private async handleSaveHighlight(intent: SaveHighlightIntent): Promise<void> {
    if (this.state.status !== 'data') return;
    const p = intent.payload;
    try {
      await HighlightService.save({
        bookId: p.bookId,
        chapterId: p.chapterId,
        chapterIndex: p.chapterIndex,
        blockIndex: p.blockIndex,
        charOffset: p.startCharOffset,
        charLength: p.endCharOffset - p.startCharOffset,
        text: p.text,
        color: p.color,
      });
      const highlights = await HighlightService.list(p.bookId, p.chapterId);
      if (this.state.status === 'data') {
        this.state = { status: 'data', data: { ...this.state.data, highlights } };
      }
    } catch (_e) {}
  }

  private async handleEditHighlight(intent: EditHighlightIntent): Promise<void> {
    if (this.state.status !== 'data') return;
    const { highlightId, color, note } = intent.payload;
    try {
      await HighlightService.update(highlightId, { color, note });
      const data = this.state.data;
      const bookId = data.currentBookId ?? '';
      const chapterId = data.currentChapterId ?? '';
      const highlights = await HighlightService.list(bookId, chapterId);
      if (this.state.status === 'data') {
        this.state = { status: 'data', data: { ...this.state.data, highlights } };
      }
    } catch (_e) {}
  }

  private async handleDeleteHighlight(intent: DeleteHighlightIntent): Promise<void> {
    if (this.state.status !== 'data') return;
    try {
      await HighlightService.delete(intent.payload.highlightId);
      const data = this.state.data;
      const bookId = data.currentBookId ?? '';
      const chapterId = data.currentChapterId ?? '';
      const highlights = await HighlightService.list(bookId, chapterId);
      if (this.state.status === 'data') {
        this.state = { status: 'data', data: { ...this.state.data, highlights } };
      }
    } catch (_e) {}
  }

  private async handleSaveBookmark(intent: SaveBookmarkIntent): Promise<void> {
    if (this.state.status !== 'data') return;
    const p = intent.payload;
    try {
      await BookmarksService.save({
        bookId: p.bookId,
        chapterId: p.chapterId,
        pageIdx: p.pageIdx,
        label: p.label,
      });
      const bookmarks = await BookmarksService.list(p.bookId);
      if (this.state.status === 'data') {
        this.state = { status: 'data', data: { ...this.state.data, bookmarks } };
      }
    } catch (_e) {}
  }

  private async handleDeleteBookmark(intent: DeleteBookmarkIntent): Promise<void> {
    if (this.state.status !== 'data') return;
    try {
      await BookmarksService.delete(intent.payload.bookmarkId);
      const bookId = this.state.data.currentBookId ?? '';
      const bookmarks = await BookmarksService.list(bookId);
      if (this.state.status === 'data') {
        this.state = { status: 'data', data: { ...this.state.data, bookmarks } };
      }
    } catch (_e) {}
  }
}
