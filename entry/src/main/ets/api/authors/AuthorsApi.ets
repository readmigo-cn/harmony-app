// L2 - API - Authors
import { HttpClient } from '../client/HttpClient';

export interface AuthorDto {
  id: string;
  name: string;
  bio: string;
  avatarUrl: string;
  followed: boolean;
  bookCount: number;
}

export interface ReadingProgressDto {
  bookId: string;
  percent: number;
}

export class AuthorsApi {
  static async list(): Promise<AuthorDto[]> {
    return HttpClient.get<AuthorDto[]>('/authors');
  }

  static async getById(authorId: string): Promise<AuthorDto> {
    return HttpClient.get<AuthorDto>(`/authors/${authorId}`);
  }

  static async getRelated(authorId: string): Promise<AuthorDto[]> {
    return HttpClient.get<AuthorDto[]>(`/authors/${authorId}/related`);
  }

  static async follow(authorId: string): Promise<void> {
    return HttpClient.post<void>(`/authors/${authorId}/follow`, {});
  }

  static async getFollowing(): Promise<AuthorDto[]> {
    return HttpClient.get<AuthorDto[]>('/authors/following');
  }

  static async getReadingProgress(authorId: string): Promise<ReadingProgressDto[]> {
    return HttpClient.get<ReadingProgressDto[]>(`/authors/${authorId}/reading-progress`);
  }
}
