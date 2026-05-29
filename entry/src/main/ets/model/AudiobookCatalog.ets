/** Catalog-layer Audiobook DTO — aligns with AudiobookApi shape. */
export interface CatalogAudiobook {
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

export interface CatalogAudiobookChapter {
  id: string;
  index: number;
  title: string;
  durationMs: number;
  audioUrl: string;
}

export interface CatalogAudiobookDetail extends CatalogAudiobook {
  description: string;
  chapters: CatalogAudiobookChapter[];
  voiceOptions?: CatalogVoice[];
}

export interface CatalogVoice {
  id: string;
  name: string;
  gender: 'male' | 'female' | 'neutral';
  language: string;
  sampleUrl?: string;
  isPremium: boolean;
}
