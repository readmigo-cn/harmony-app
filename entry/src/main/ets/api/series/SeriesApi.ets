// L2 - API - Series
import { HttpClient } from '../client/HttpClient';

export interface SeriesBookDto {
  id: string;
  order: number;
  title: string;
}

export interface SeriesDto {
  id: string;
  title: string;
  bookCount: number;
  books: SeriesBookDto[];
}

export interface SeriesReadingProgressDto {
  bookId: string;
  percent: number;
}

export class SeriesApi {
  static async list(): Promise<SeriesDto[]> {
    return HttpClient.get<SeriesDto[]>('/series');
  }

  static async getById(seriesId: string): Promise<SeriesDto> {
    return HttpClient.get<SeriesDto>(`/series/${seriesId}`);
  }
}
