// L2 Feature - Quotes - Service
import { QuotesApi } from '../../../api/quotes/QuotesApi';
import type { Quote } from '../../../model/Quote';

class QuotesServiceImpl {
  getDaily(): Promise<Quote> {
    return QuotesApi.getDaily();
  }

  getTrending(): Promise<Quote[]> {
    return QuotesApi.getTrending();
  }

  getRandom(): Promise<Quote> {
    return QuotesApi.getRandom();
  }

  getFavorites(): Promise<Quote[]> {
    return QuotesApi.getFavorites();
  }

  getById(id: string): Promise<Quote> {
    return QuotesApi.getById(id);
  }

  likeQuote(id: string): Promise<void> {
    return QuotesApi.likeQuote(id);
  }
}

export const QuotesService = new QuotesServiceImpl();
