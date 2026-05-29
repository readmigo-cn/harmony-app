// L2 API - Quotes
import { HttpClient } from '../client/HttpClient';
import type { Quote } from '../../model/Quote';

export class QuotesApi {
  static getDaily(): Promise<Quote> {
    return HttpClient.get<Quote>('/api/v1/quotes/daily');
  }

  static getTrending(): Promise<Quote[]> {
    return HttpClient.get<Quote[]>('/api/v1/quotes/trending');
  }

  static getRandom(): Promise<Quote> {
    return HttpClient.get<Quote>('/api/v1/quotes/random');
  }

  static getFavorites(): Promise<Quote[]> {
    return HttpClient.get<Quote[]>('/api/v1/quotes/favorites');
  }

  static getById(id: string): Promise<Quote> {
    return HttpClient.get<Quote>(`/api/v1/quotes/${encodeURIComponent(id)}`);
  }

  static likeQuote(id: string): Promise<void> {
    return HttpClient.post<void>(`/api/v1/quotes/${encodeURIComponent(id)}/like`, {});
  }
}
