// L2 Feature - Authors - Service
import { AuthorsApi } from '../../../api/authors/AuthorsApi';
import type { AuthorDto, ReadingProgressDto } from '../../../api/authors/AuthorsApi';

export interface Author {
  id: string;
  name: string;
  bio: string;
  avatarUrl: string;
  followed: boolean;
  bookCount: number;
}

export interface AuthorReadingProgress {
  bookId: string;
  percent: number;
}

function toAuthor(dto: AuthorDto): Author {
  return {
    id: dto.id,
    name: dto.name,
    bio: dto.bio,
    avatarUrl: dto.avatarUrl,
    followed: dto.followed,
    bookCount: dto.bookCount,
  };
}

export class AuthorsService {
  static async getProfile(authorId: string): Promise<Author> {
    const dto = await AuthorsApi.getById(authorId);
    return toAuthor(dto);
  }

  static async getRelated(authorId: string): Promise<Author[]> {
    const dtos = await AuthorsApi.getRelated(authorId);
    return dtos.map(toAuthor);
  }

  static async follow(authorId: string): Promise<void> {
    await AuthorsApi.follow(authorId);
  }

  static async getFollowing(): Promise<Author[]> {
    const dtos = await AuthorsApi.getFollowing();
    return dtos.map(toAuthor);
  }

  static async getReadingProgress(authorId: string): Promise<AuthorReadingProgress[]> {
    const dtos: ReadingProgressDto[] = await AuthorsApi.getReadingProgress(authorId);
    return dtos.map((d) => ({ bookId: d.bookId, percent: d.percent }));
  }
}
