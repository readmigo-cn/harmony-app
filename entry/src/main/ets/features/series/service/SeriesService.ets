// L2 Feature - Series - Service
import { SeriesApi } from '../../../api/series/SeriesApi';
import type { SeriesDto, SeriesBookDto } from '../../../api/series/SeriesApi';

export interface SeriesBook {
  id: string;
  order: number;
  title: string;
}

export interface Series {
  id: string;
  title: string;
  bookCount: number;
  books: SeriesBook[];
}

function toSeriesBook(dto: SeriesBookDto): SeriesBook {
  return { id: dto.id, order: dto.order, title: dto.title };
}

function toSeries(dto: SeriesDto): Series {
  return {
    id: dto.id,
    title: dto.title,
    bookCount: dto.bookCount,
    books: dto.books.map(toSeriesBook),
  };
}

export class SeriesService {
  static async list(): Promise<Series[]> {
    const dtos = await SeriesApi.list();
    return dtos.map(toSeries);
  }

  static async getById(seriesId: string): Promise<Series> {
    const dto = await SeriesApi.getById(seriesId);
    return toSeries(dto);
  }
}
