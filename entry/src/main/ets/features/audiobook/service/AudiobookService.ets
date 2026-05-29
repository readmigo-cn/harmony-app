// L2 Feature - Audiobook - Service
import { AudiobookApi } from '../../../api/audiobooks/AudiobookApi';
import type {
  AudiobookItem,
  AudiobookDetailItem,
  VoiceItem,
  SessionLogPayload,
} from '../../../api/audiobooks/AudiobookApi';
import { AudioCacheStrategy } from '../../../core/cache/strategies/AudioCacheStrategy';
import { SubscriptionState } from '../../account/service/subscription/SubscriptionState';

const CACHE_TTL_MS = 5 * 60 * 1000; // 5 min in-memory cache

interface CacheEntry<T> {
  data: T;
  expiresAt: number;
}

export class AudiobookService {
  private static instance: AudiobookService | null = null;

  private readonly api = AudiobookApi.getInstance();
  private popularCache: CacheEntry<AudiobookItem[]> | null = null;
  private recentCache: CacheEntry<AudiobookItem[]> | null = null;
  private detailCache: Map<string, CacheEntry<AudiobookDetailItem>> = new Map();

  static getInstance(): AudiobookService {
    if (!AudiobookService.instance) {
      AudiobookService.instance = new AudiobookService();
    }
    return AudiobookService.instance;
  }

  async search(q: string, page: number = 1, pageSize: number = 20): Promise<{ items: AudiobookItem[]; total: number }> {
    return this.api.search(q, page, pageSize);
  }

  async popular(): Promise<AudiobookItem[]> {
    if (this.popularCache && Date.now() < this.popularCache.expiresAt) {
      return this.popularCache.data;
    }
    const data = await this.api.getPopular();
    this.popularCache = { data, expiresAt: Date.now() + CACHE_TTL_MS };
    return data;
  }

  async recentlyListened(): Promise<AudiobookItem[]> {
    if (this.recentCache && Date.now() < this.recentCache.expiresAt) {
      return this.recentCache.data;
    }
    const data = await this.api.getRecentlyListened();
    this.recentCache = { data, expiresAt: Date.now() + CACHE_TTL_MS };
    return data;
  }

  async getDetail(audiobookId: string): Promise<AudiobookDetailItem> {
    const cached = this.detailCache.get(audiobookId);
    if (cached && Date.now() < cached.expiresAt) {
      return cached.data;
    }
    const data = await this.api.getDetail(audiobookId);
    this.detailCache.set(audiobookId, { data, expiresAt: Date.now() + CACHE_TTL_MS });
    AudioCacheStrategy.setActiveBook(audiobookId);
    return data;
  }

  async getForBook(bookId: string): Promise<AudiobookItem | null> {
    return this.api.getForBook(bookId);
  }

  async getVoices(bookId: string): Promise<VoiceItem[]> {
    return this.api.getVoicesForBook(bookId);
  }

  async getTtsV3Voices(): Promise<VoiceItem[]> {
    return this.api.getTtsV3Voices();
  }

  /**
   * Librivox audiobooks are always free.
   * TTS-v3 audiobooks require an active Pro subscription.
   */
  canPlay(audiobook: AudiobookItem): boolean {
    if (audiobook.free || audiobook.provider === 'librivox') return true;
    return SubscriptionState.getInstance().isProActive();
  }

  async download(audiobookId: string): Promise<void> {
    const detail = await this.getDetail(audiobookId);
    for (let i = 0; i < detail.chapters.length; i++) {
      const ch = detail.chapters[i];
      if (ch.audioUrl) {
        await AudioCacheStrategy.download(ch.audioUrl, audiobookId, ch.index);
      }
    }
  }

  async updateProgress(audiobookId: string, positionMs: number): Promise<void> {
    await this.api.updateProgress(audiobookId, positionMs);
  }

  async logSession(payload: SessionLogPayload): Promise<void> {
    await this.api.logSession(payload);
  }

  invalidateCache(): void {
    this.popularCache = null;
    this.recentCache = null;
    this.detailCache.clear();
  }
}
