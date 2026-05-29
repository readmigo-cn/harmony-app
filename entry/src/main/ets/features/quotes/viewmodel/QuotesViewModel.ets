// L3 Feature - Quotes - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import type { Quote } from '../../../model/Quote';
import { QuotesService } from '../service/QuotesService';
import { QUOTES_INTENT_KINDS } from '../intent/QuotesIntents';
import type {
  OpenQuoteDetailIntent,
  LikeQuoteIntent,
} from '../intent/QuotesIntents';

export interface QuotesData {
  readonly daily?: Quote;
  readonly trending?: Quote[];
  readonly random?: Quote;
  readonly favorites?: Quote[];
  readonly selected?: Quote;
}

export type QuotesState = ViewModelState<QuotesData>;

export class QuotesViewModel extends FeatureViewModel<QuotesData> {
  readonly kind = 'quotes';

  @State state: QuotesState = { status: 'idle' };

  constructor() {
    super(QUOTES_INTENT_KINDS);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    switch (intent.kind) {
      case 'quotes.loadDaily':
        await this.handleLoadDaily();
        break;
      case 'quotes.loadTrending':
        await this.handleLoadTrending();
        break;
      case 'quotes.loadRandom':
        await this.handleLoadRandom();
        break;
      case 'quotes.loadFavorites':
        await this.handleLoadFavorites();
        break;
      case 'quotes.openDetail':
        await this.handleOpenDetail(intent as OpenQuoteDetailIntent);
        break;
      case 'quotes.likeQuote':
        await this.handleLikeQuote(intent as LikeQuoteIntent);
        break;
      case 'quotes.shareQuote':
        // share is handled at L4 via platform share sheet
        break;
      default:
        break;
    }
  }

  private async handleLoadDaily(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const daily = await QuotesService.getDaily();
      const current = this.currentData();
      this.state = { status: 'data', data: { ...current, daily } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_daily_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadTrending(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const trending = await QuotesService.getTrending();
      const current = this.currentData();
      this.state = { status: 'data', data: { ...current, trending } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_trending_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadRandom(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const random = await QuotesService.getRandom();
      const current = this.currentData();
      this.state = { status: 'data', data: { ...current, random } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_random_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadFavorites(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const favorites = await QuotesService.getFavorites();
      const current = this.currentData();
      this.state = { status: 'data', data: { ...current, favorites } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_favorites_failed', message: (e as Error).message } };
    }
  }

  private async handleOpenDetail(intent: OpenQuoteDetailIntent): Promise<void> {
    const { quoteId } = intent.payload;
    try {
      const selected = await QuotesService.getById(quoteId);
      const current = this.currentData();
      this.state = { status: 'data', data: { ...current, selected } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'open_detail_failed', message: (e as Error).message } };
    }
  }

  private async handleLikeQuote(intent: LikeQuoteIntent): Promise<void> {
    const { quoteId } = intent.payload;
    try {
      await QuotesService.likeQuote(quoteId);
      const current = this.currentData();
      this.state = {
        status: 'data',
        data: {
          ...current,
          daily: current.daily?.id === quoteId ? { ...current.daily, liked: true } : current.daily,
          selected: current.selected?.id === quoteId ? { ...current.selected, liked: true } : current.selected,
          trending: current.trending?.map((q) => q.id === quoteId ? { ...q, liked: true } : q),
        },
      };
    } catch (e) {
      // like failures are silent — optimistic UI already applied above if needed
    }
  }

  private currentData(): QuotesData {
    return this.state.status === 'data' ? this.state.data : {};
  }
}
