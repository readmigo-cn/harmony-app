// L3 Feature - Reader - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type {
  AnyIntent,
  OpenBookIntent,
  JumpToChapterIntent,
  JumpToPageIntent,
  SelectTextIntent,
  LookupWordIntent,
} from '../../../core/intent/Intent';
import { ReadingService } from '../service/ReadingService';
import { HighlightService } from '../service/HighlightService';
import { BookmarksService } from '../service/BookmarksService';
import { ReadingSession } from '../service/ReadingSession';
import { ReadingSoul } from '../../../core/distributed-soul/ReadingSoul';
import {
  READER_INTENT_KINDS,
  type SaveHighlightIntent,
  type EditHighlightIntent,
  type DeleteHighlightIntent,
  type SaveBookmarkIntent,
  type DeleteBookmarkIntent,
  type TranslateSelectionIntent,
} from '../intent/ReaderIntents';
import { TranslateService } from '../../ai-tools/service/TranslateService';
import type { WordExplanation } from '../../ai-tools/service/TranslateService';
import type { Book } from '../../../model/Book';
import type { Chapter, ChapterContent } from '../../../model/Chapter';
import type { Highlight } from '../../../model/Highlight';
import type { Bookmark } from '../service/BookmarksService';

// ---------------------------------------------------------------------------
// State types
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
  highlights?: Highlight[];
  bookmarks?: Bookmark[];
  sessionId?: string;
  lookup?: LookupState;
}

export type ReaderState =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'data'; data: ReaderData }
  | { status: 'error'; error: { code: string; message: string } };

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

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
        await this.handleJumpToChapter(intent as JumpToChapterIntent);
        break;
      case 'reader.jumpToPage':
        await this.handleJumpToPage(intent as JumpToPageIntent);
        break;
      case 'reader.selectText':
        this.handleSelectText(intent as SelectTextIntent);
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
      case 'reader.lookupWord':
        await this.handleLookupWord(intent as LookupWordIntent);
        break;
      case 'reader.translateSelection':
        this.handleTranslateSelection(intent as TranslateSelectionIntent);
        break;
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

  // ---------------------------------------------------------------------------
  // lookupWord — end-to-end via TranslateService
  // ---------------------------------------------------------------------------

  private async handleLookupWord(intent: LookupWordIntent): Promise<void> {
    if (this.state.status !== 'data') return;

    const { word, ctxSentence } = intent.payload;
    const data = this.state.data;

    // Record session activity
    if (data.sessionId) ReadingSession.recordWordLookup(data.sessionId, word);

    // Set loading + open sheet
    this.state = {
      status: 'data',
      data: {
        ...data,
        lookup: { status: 'loading', word, contextSentence: ctxSentence ?? '' },
        sheets: { ...(data.sheets ?? {}), wordExplain: true },
      },
    };

    try {
      const explanation = await TranslateService.shared.lookupWord(
        word,
        ctxSentence ?? '',
        'zh',
      );

      if (this.state.status !== 'data') return;
      this.state = {
        status: 'data',
        data: {
          ...this.state.data,
          lookup: { status: 'data', word, contextSentence: ctxSentence ?? '', explanation },
        },
      };
    } catch (e) {
      if (this.state.status !== 'data') return;
      this.state = {
        status: 'data',
        data: {
          ...this.state.data,
          lookup: {
            status: 'error',
            word,
            error: { code: (e as Error).name ?? 'error', message: (e as Error).message },
          },
        },
      };
    }
  }

  // ---------------------------------------------------------------------------
  // translateSelection — streaming via TranslateService.translateSentenceStream
  // ---------------------------------------------------------------------------

  private handleTranslateSelection(intent: TranslateSelectionIntent): void {
    if (this.state.status !== 'data') return;

    const { text, sourceLang, targetLang } = intent.payload;
    const data = this.state.data;

    // Set streaming state + open sheet
    this.state = {
      status: 'data',
      data: {
        ...data,
        lookup: { status: 'streaming', word: text, streamingText: '', contextSentence: text },
        sheets: { ...(data.sheets ?? {}), wordExplain: true },
      },
    };

    const stream = TranslateService.shared.translateSentenceStream(text, { sourceLang, targetLang });
    let accumulated = '';

    const advance = async (): Promise<void> => {
      try {
        for await (const chunk of stream) {
          accumulated += chunk;
          if (this.state.status !== 'data') return;
          this.state = {
            status: 'data',
            data: {
              ...this.state.data,
              lookup: {
                status: 'streaming',
                word: text,
                contextSentence: text,
                streamingText: accumulated,
              },
            },
          };
        }
        // done
        if (this.state.status !== 'data') return;
        this.state = {
          status: 'data',
          data: {
            ...this.state.data,
            lookup: {
              status: 'data',
              word: text,
              contextSentence: text,
              explanation: {
                word: text,
                definition: accumulated,
                partOfSpeech: '',
                examples: [],
                wordFamily: [],
              },
            },
          },
        };
      } catch (e) {
        if (this.state.status !== 'data') return;
        this.state = {
          status: 'data',
          data: {
            ...this.state.data,
            lookup: {
              status: 'error',
              word: text,
              error: { code: (e as Error).name ?? 'error', message: (e as Error).message },
            },
          },
        };
      }
    };

    advance().catch(() => {});
  }

  // ---------------------------------------------------------------------------
  // Existing handlers (unchanged)
  // ---------------------------------------------------------------------------

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
      const sessionId = ReadingSession.start(bookId, firstChapterId);
      const [highlights, bookmarks] = await Promise.all([
        HighlightService.list(bookId, firstChapterId),
        BookmarksService.list(bookId),
      ]);

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
          highlights,
          bookmarks,
          sessionId,
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
    const sessionId = data.sessionId;
    if (sessionId) ReadingSession.recordChapterChange(sessionId, chapterId);

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
          data: { ...this.state.data, currentContent: content, highlights },
        };
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
      ReadingSoul.setPosition(bookId, chapterId, pageIdx, 0).catch(() => {});
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

  private handleSelectText(intent: SelectTextIntent): void {
    void intent;
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
      const bookId = data.book?.id ?? '';
      const chapters = data.chapters ?? [];
      const chapterId = chapters[data.currentChapterIdx ?? 0]?.id ?? '';
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
      const bookId = data.book?.id ?? '';
      const chapters = data.chapters ?? [];
      const chapterId = chapters[data.currentChapterIdx ?? 0]?.id ?? '';
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
      const bookId = this.state.data.book?.id ?? '';
      const bookmarks = await BookmarksService.list(bookId);
      if (this.state.status === 'data') {
        this.state = { status: 'data', data: { ...this.state.data, bookmarks } };
      }
    } catch (_e) {}
  }

  async closeBook(): Promise<void> {
    if (this.state.status !== 'data') return;
    const sessionId = this.state.data.sessionId;
    if (sessionId) await ReadingSession.end(sessionId);
  }
}
