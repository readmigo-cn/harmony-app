import { HttpClient } from '../client/HttpClient';

export interface AudiobookItem {
  id: string;
  title: string;
  narrator: string;
  durationMs: number;
  coverUrl: string;
  provider: 'librivox' | 'tts-v3';
  languages: string[];
  free: boolean;
  bookId?: string;
}

export interface AudiobookChapterItem {
  id: string;
  index: number;
  title: string;
  durationMs: number;
  audioUrl: string;
}

export interface AudiobookDetailItem extends AudiobookItem {
  description: string;
  chapters: AudiobookChapterItem[];
  voiceOptions?: VoiceItem[];
}

export interface VoiceItem {
  id: string;
  name: string;
  gender: 'male' | 'female' | 'neutral';
  language: string;
  sampleUrl?: string;
  isPremium: boolean;
}

export interface AudiobookSearchResponse {
  items: AudiobookItem[];
  total: number;
}

export interface UpdateProgressPayload {
  audiobookId: string;
  positionMs: number;
}

export interface SessionLogPayload {
  audiobookId: string;
  startMs: number;
  endMs: number;
  chapterId?: string;
}

export class AudiobookApi {
  private static instance: AudiobookApi | null = null;

  static getInstance(): AudiobookApi {
    if (!AudiobookApi.instance) {
      AudiobookApi.instance = new AudiobookApi();
    }
    return AudiobookApi.instance;
  }

  search(q: string, page: number = 1, pageSize: number = 20): Promise<AudiobookSearchResponse> {
    return HttpClient.get<AudiobookSearchResponse>('/api/v1/audiobooks', {
      q,
      page,
      pageSize,
    });
  }

  getRecentlyListened(): Promise<AudiobookItem[]> {
    return HttpClient.get<AudiobookItem[]>('/api/v1/audiobooks/recently-listened');
  }

  getPopular(): Promise<AudiobookItem[]> {
    return HttpClient.get<AudiobookItem[]>('/api/v1/audiobooks/popular');
  }

  getDetail(audiobookId: string): Promise<AudiobookDetailItem> {
    return HttpClient.get<AudiobookDetailItem>(`/api/v1/audiobooks/${encodeURIComponent(audiobookId)}`);
  }

  getForBook(bookId: string): Promise<AudiobookItem | null> {
    return HttpClient.get<AudiobookItem | null>(`/api/v1/audiobooks/by-book/${encodeURIComponent(bookId)}`);
  }

  getVoicesForBook(bookId: string): Promise<VoiceItem[]> {
    return HttpClient.get<VoiceItem[]>(`/api/v1/audiobooks/voices/book/${encodeURIComponent(bookId)}`);
  }

  getTtsV3Voices(): Promise<VoiceItem[]> {
    return HttpClient.get<VoiceItem[]>('/api/v1/audiobooks/voices/tts-v3');
  }

  updateProgress(audiobookId: string, positionMs: number): Promise<void> {
    return HttpClient.post<void>('/api/v1/audiobooks/progress', {
      audiobookId,
      positionMs,
    } as unknown as object);
  }

  logSession(payload: SessionLogPayload): Promise<void> {
    return HttpClient.post<void>('/api/v1/audiobooks/sessions', payload as unknown as object);
  }
}
