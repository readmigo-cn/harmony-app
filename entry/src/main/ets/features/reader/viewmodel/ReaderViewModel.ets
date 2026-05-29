// L3 Feature - Reader - Root ViewModel
// Owns: book/chapters/currentChapter/currentContent/sheets
// Delegates lookup intents → ReaderLookupViewModel
// Delegates highlight/bookmark/progress intents → ReaderProgressViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { AnyIntent, OpenBookIntent, JumpToChapterIntent, JumpToPageIntent, SelectTextIntent } from '../../../core/intent/Intent';
import { ReadingService } from '../service/ReadingService';
import { HighlightService } from '../service/HighlightService';
import { BookmarksService } from '../service/BookmarksService';
import { READER_INTENT_KINDS } from '../intent/ReaderIntents';
import { ReaderLookupViewModel } from './ReaderLookupViewModel';
import { ReaderProgressViewModel } from './ReaderProgressViewModel';
import type { Book } from '../../../model/Book';
import type { Chapter, ChapterContent } from '../../../model/Chapter';
import type { WordExplanation } from '../../ai-tools/service/TranslateService';

// ---------------------------------------------------------------------------
// State types (shape preserved from W4 — backwards-compatible)
// ---------------------------------------------------------------------------

export interface LookupState {
  status: 'idle' | 'loading' | 'streaming' | 'data' | 'error';
  word?: string;
  contextSentence?: string;
  explanation?: WordExplanation;
  streamingText?: string;
  error?: { code: string; message: string };
}

export interface ReaderSheets {
  toc?: boolean;
  settings?: boolean;
  highlights?: boolean;
  wordExplain?: boolean;
}

export interface ReaderData {
  book?: Book;
  chapters?: Chapter[];
  currentChapterIdx?: number;
  currentContent?: ChapterContent;
  currentPageIdx?: number;
  sheets?: ReaderSheets;
  lookup?: LookupState;
}

export type ReaderState =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'data'; data: ReaderData }
  | { status: 'error'; error: { code: string; message: string } };

// ---------------------------------------------------------------------------
// Root ViewModel (fanout: 13 local imports)
// ---------------------------------------------------------------------------

export class ReaderViewModel extends FeatureViewModel<ReaderData> {
  readonly kind = 'reader';

  readonly lookupVm: ReaderLookupViewModel = new ReaderLookupViewModel();
  readonly progressVm: ReaderProgressViewModel = new ReaderProgressViewModel();

  constructor() {
    super(READER_INTENT_KINDS);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    const k = intent.kind;

    // Forward lookup intents
    if (k === 'reader.lookupWord' || k === 'reader.translateSelection') {
      if (this.state.status === 'data') {
        const word = (intent as { payload: { word?: string; text?: string } }).payload.word
          ?? (intent as { payload: { word?: string; text?: string } }).payload.text
          ?? '';
        this.progressVm.recordWordLookup(word);
        const sheets = { ...(this.state.data.sheets ?? {}), wordExplain: true };
        this.state = { status: 'data', data: { ...this.state.data, sheets } };
      }
      return;
    }

    // Forward highlight/bookmark/progress intents
    if (
      k === 'reader.saveHighlight' ||
      k === 'reader.editHighlight' ||
      k === 'reader.deleteHighlight' ||
      k === 'reader.saveBookmark' ||
      k === 'reader.deleteBookmark'
    ) {
      return;
    }

    switch (intent.kind) {
      case 'reader.openBook':
        await this.handleOpenBook(intent as OpenBookIntent);
        break;
      case 'reader.jumpToChapter':
        await this.handleJumpToChapter(intent as JumpToChapterIntent);
        break;
      case 'reader.jumpToPage':
        await this.handleJumpToPage(intent as JumpToPageIntent);
        break;
      case 'reader.selectText':
        void (intent as SelectTextIntent);
        break;
      case 'reader.openHighlightLayer':
        this.handleOpenHighlightLayer();
        break;
      case 'reader.openTocSheet':
        this.handleOpenTocSheet();
        break;
      case 'reader.openSettings':
        this.handleOpenSettings();
        break;
      default:
        break;
    }
  }

  onDestroy(): void {
    this.lookupVm.onDestroy();
    this.progressVm.onDestroy();
    super.onDestroy();
  }

  async closeBook(): Promise<void> {
    await this.progressVm.closeSession();
  }

  private async handleOpenBook(intent: OpenBookIntent): Promise<void> {
    const { bookId } = intent.payload;
    this.state = { status: 'loading' };
    try {
      const book = await ReadingService.loadBook(bookId);
      const chapters = await ReadingService.loadChapters(bookId);
      const currentChapterIdx = 0;

      let currentContent: ChapterContent | undefined;
      if (chapters.length > 0) {
        currentContent = await ReadingService.loadChapterContent(bookId, chapters[0].id);
      }

      const firstChapterId = chapters.length > 0 ? chapters[0].id : '';
      const [highlights, bookmarks] = await Promise.all([
        HighlightService.list(bookId, firstChapterId),
        BookmarksService.list(bookId),
      ]);

      this.progressVm.initSession(bookId, firstChapterId, 0, highlights, bookmarks);
      ReadingService.prefetchAdjacent(bookId, chapters, currentChapterIdx);

      this.state = {
        status: 'data',
        data: {
          book,
          chapters,
          currentChapterIdx,
          currentContent,
          currentPageIdx: 0,
          sheets: {},
          lookup: { status: 'idle' },
        },
      };
    } catch (e) {
      this.state = {
        status: 'error',
        error: { code: 'open_book_failed', message: (e as Error).message },
      };
    }
  }

  private async handleJumpToChapter(intent: JumpToChapterIntent): Promise<void> {
    if (this.state.status !== 'data') return;
    const { chapterId } = intent.payload;
    const data = this.state.data;
    const chapters = data.chapters ?? [];
    const idx = chapters.findIndex((ch) => ch.id === chapterId);
    if (idx < 0) return;

    const bookId = data.book?.id ?? '';

    this.state = {
      status: 'data',
      data: { ...data, currentChapterIdx: idx, currentPageIdx: 0 },
    };

    try {
      const [content, highlights] = await Promise.all([
        ReadingService.loadChapterContent(bookId, chapterId),
        HighlightService.list(bookId, chapterId),
      ]);
      if (this.state.status === 'data') {
        this.state = {
          status: 'data',
          data: { ...this.state.data, currentContent: content },
        };
        this.progressVm.updateContext(bookId, chapterId, 0, highlights);
        ReadingService.prefetchAdjacent(bookId, chapters, idx);
      }
    } catch (_e) {}
  }

  private async handleJumpToPage(intent: JumpToPageIntent): Promise<void> {
    if (this.state.status !== 'data') return;
    const data = this.state.data;
    const pageIdx = intent.payload.pageIdx;
    this.state = { status: 'data', data: { ...data, currentPageIdx: pageIdx } };

    const bookId = data.book?.id ?? '';
    const chapters = data.chapters ?? [];
    const chapterIdx = data.currentChapterIdx ?? 0;
    const chapterId = chapters[chapterIdx]?.id ?? '';
    if (bookId && chapterId) {
      this.progressVm.syncPosition(bookId, chapterId, pageIdx).catch(() => {});
    }
  }

  private handleOpenTocSheet(): void {
    if (this.state.status !== 'data') return;
    const sheets = { ...(this.state.data.sheets ?? {}), toc: true };
    this.state = { status: 'data', data: { ...this.state.data, sheets } };
  }

  private handleOpenSettings(): void {
    if (this.state.status !== 'data') return;
    const sheets = { ...(this.state.data.sheets ?? {}), settings: true };
    this.state = { status: 'data', data: { ...this.state.data, sheets } };
  }

  private handleOpenHighlightLayer(): void {
    if (this.state.status !== 'data') return;
    const sheets = { ...(this.state.data.sheets ?? {}), highlights: true };
    this.state = { status: 'data', data: { ...this.state.data, sheets } };
  }
}
