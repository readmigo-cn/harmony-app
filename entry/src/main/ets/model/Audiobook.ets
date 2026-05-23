/**
 * Audiobook models - aligned with overseas readmigo-repos/mobile/src/features/audiobook/types
 * 功能对齐：Audiobook types from overseas
 * 
 * Features:
 * - Audiobook chapters with duration
 * - Multiple sources (LibriVox, Internet Archive, TTS)
 * - Playback progress tracking
 * - Whispersync with ebook
 * - Domestic TTS integration (科大讯飞)
 */

// Audiobook source (国内化适配)
export type AudiobookSource = 'LIBRIVOX' | 'INTERNET_ARCHIVE' | 'USER_UPLOAD' | 'TTS_GENERATED';

// Audio quality
export type AudioQuality = 'LOW' | 'STANDARD' | 'HIGH';

// Listening status
export type ListeningStatus = 'NOT_STARTED' | 'IN_PROGRESS' | 'COMPLETED';

// Playback speed options
export type PlaybackSpeed = 0.5 | 0.75 | 1.0 | 1.25 | 1.5 | 1.75 | 2.0 | 2.5 | 3.0;

export const PLAYBACK_SPEEDS: PlaybackSpeed[] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

// Sleep timer options in minutes
export type SleepTimerOption = 5 | 10 | 15 | 30 | 45 | 60 | 'end_of_chapter';

export interface SleepTimerOptionItem {
  label: string;
  value: SleepTimerOption;
}

export const SLEEP_TIMER_OPTIONS: SleepTimerOptionItem[] = [
  { label: '5 分钟', value: 5 },
  { label: '10 分钟', value: 10 },
  { label: '15 分钟', value: 15 },
  { label: '30 分钟', value: 30 },
  { label: '45 分钟', value: 45 },
  { label: '60 分钟', value: 60 },
  { label: '本章结束', value: 'end_of_chapter' },
];

// TTS Voice options (国内化 - 科大讯飞 voices)
export interface TTSVoice {
  id: string;
  name: string;
  gender: 'male' | 'female';
  language: string;
  provider: 'IFLYTEK' | 'ALIYUN' | 'BAIDU';
  sampleUrl?: string;
}

// Audiobook chapter
export interface AudiobookChapter {
  id: string;
  number: number;
  title: string;
  duration: number; // seconds
  audioUrl: string;
  readerName?: string;
  bookChapterId?: string; // Link to ebook chapter for Whispersync
  paragraphs?: AudiobookParagraph[]; // For word-level highlighting
}

// Audiobook paragraph (for word-level highlighting)
export interface AudiobookParagraph {
  id: string;
  text: string;
  startTime: number; // seconds
  endTime: number; // seconds
  words?: AudioWordTimestamp[]; // Word-level timestamps
}

// Word-level timestamp
export interface AudioWordTimestamp {
  word: string;
  startTime: number; // seconds
  endTime: number; // seconds
}

// Audiobook
export interface Audiobook {
  id: string;
  title: string;
  author: string;
  narrator?: string;
  coverUrl?: string;
  coverThumbUrl?: string;
  description?: string;
  totalDuration: number; // seconds
  chapters: AudiobookChapter[];
  source: AudiobookSource;
  language: string;
  bookId?: string; // Associated ebook ID for Whispersync
  hasEbookSync?: boolean; // Whispersync available
  ttsVoiceId?: string; // TTS voice used if TTS_GENERATED
  createdAt: string;
  updatedAt: string;
}

// Audiobook list item (without chapters)
export interface AudiobookListItem {
  id: string;
  title: string;
  author: string;
  narrator?: string;
  coverUrl?: string;
  coverThumbUrl?: string;
  totalDuration: number;
  chapterCount: number;
  source: AudiobookSource;
  language: string;
  bookId?: string;
  hasEbookSync?: boolean;
}

// User's audiobook progress
export interface AudiobookProgress {
  audiobookId: string;
  currentChapter: number;
  currentPosition: number; // seconds within chapter
  totalListened: number; // total seconds listened
  playbackSpeed: PlaybackSpeed;
  status: ListeningStatus;
  lastPlayedAt: string;
}

// Audiobook with progress
export interface AudiobookWithProgress extends Audiobook {
  progress?: AudiobookProgress;
}

// Audio player state
export interface AudioPlayerState {
  // Current audiobook
  audiobook: Audiobook | null;
  currentChapter: AudiobookChapter | null;
  chapterIndex: number;

  // Playback state
  isPlaying: boolean;
  isLoading: boolean;
  isBuffering: boolean;
  currentTime: number; // seconds within chapter
  duration: number; // chapter duration
  playbackSpeed: PlaybackSpeed;
  volume: number; // 0-1

  // UI state
  isMinimized: boolean;
  isVisible: boolean;

  // Sleep timer
  sleepTimer: SleepTimerOption | null;
  sleepTimerEndTime: number | null; // timestamp

  // Error
  error: string | null;
}

// Paginated audiobooks response
export interface PaginatedAudiobooks {
  data: AudiobookListItem[];
  total: number;
  page: number;
  limit: number;
}

// Search audiobooks response
export interface AudiobookSearchResult {
  id: string;
  title: string;
  author: string;
  coverUrl?: string;
  totalDuration: number;
  matchScore?: number;
}
