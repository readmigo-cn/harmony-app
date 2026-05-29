// L3 Feature - Audiobook - Intent
import type { PlayAudiobookIntent, PauseAudiobookIntent } from '../../../core/intent/Intent';
import type { Intent } from '../../../core/intent/Intent';
import type { PlaybackSpeed, SleepTimerOption } from '../../../model/Audiobook';

export type { PlayAudiobookIntent, PauseAudiobookIntent };

// Module-local intents (W3 TTS additions).
export type SetSpeedIntent = Intent<'audiobook.setSpeed', { speed: PlaybackSpeed }>;
export type SetSleepTimerIntent = Intent<'audiobook.setSleepTimer', { option: SleepTimerOption | null }>;
export type SetVoiceIntent = Intent<'audiobook.setVoice', { voiceId: string }>;

// Module-local intents (W4 catalog additions — not added to AnyIntent in core/intent/Intent.ets).
export type AudiobookSearchIntent = Intent<'audiobook.search', { query: string }>;
export type AudiobookLoadPopularIntent = Intent<'audiobook.loadPopular', Record<string, never>>;
export type AudiobookLoadRecentlyListenedIntent = Intent<'audiobook.loadRecentlyListened', Record<string, never>>;
export type AudiobookOpenDetailIntent = Intent<'audiobook.openDetail', { audiobookId: string }>;
export type AudiobookRequestDownloadIntent = Intent<'audiobook.requestDownload', { audiobookId: string }>;
export type AudiobookContinueListeningIntent = Intent<'audiobook.continueListening', Record<string, never>>;

export type AudiobookIntent =
  | PlayAudiobookIntent
  | PauseAudiobookIntent
  | SetSpeedIntent
  | SetSleepTimerIntent
  | SetVoiceIntent
  | AudiobookSearchIntent
  | AudiobookLoadPopularIntent
  | AudiobookLoadRecentlyListenedIntent
  | AudiobookOpenDetailIntent
  | AudiobookRequestDownloadIntent
  | AudiobookContinueListeningIntent;

export type AudiobookIntentKind = AudiobookIntent['kind'];

export const AUDIOBOOK_INTENT_KINDS: AudiobookIntentKind[] = [
  'audiobook.play',
  'audiobook.pause',
  'audiobook.setSpeed',
  'audiobook.setSleepTimer',
  'audiobook.setVoice',
  'audiobook.search',
  'audiobook.loadPopular',
  'audiobook.loadRecentlyListened',
  'audiobook.openDetail',
  'audiobook.requestDownload',
  'audiobook.continueListening',
];

export function makePlayAudiobookIntent(bookId: string, chapterId?: string): PlayAudiobookIntent {
  return {
    kind: 'audiobook.play',
    payload: { bookId, chapterId },
    idempotencyKey: `audiobook.play:${bookId}:${chapterId ?? ''}:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makePauseAudiobookIntent(): PauseAudiobookIntent {
  return {
    kind: 'audiobook.pause',
    payload: {},
    idempotencyKey: `audiobook.pause:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeSetSpeedIntent(speed: PlaybackSpeed): SetSpeedIntent {
  return {
    kind: 'audiobook.setSpeed',
    payload: { speed },
    idempotencyKey: `audiobook.setSpeed:${speed}:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeSetSleepTimerIntent(option: SleepTimerOption | null): SetSleepTimerIntent {
  return {
    kind: 'audiobook.setSleepTimer',
    payload: { option },
    idempotencyKey: `audiobook.setSleepTimer:${option}:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeSetVoiceIntent(voiceId: string): SetVoiceIntent {
  return {
    kind: 'audiobook.setVoice',
    payload: { voiceId },
    idempotencyKey: `audiobook.setVoice:${voiceId}:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeSearchIntent(query: string): AudiobookSearchIntent {
  return {
    kind: 'audiobook.search',
    payload: { query },
    idempotencyKey: `audiobook.search:${query}:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadPopularIntent(): AudiobookLoadPopularIntent {
  return {
    kind: 'audiobook.loadPopular',
    payload: {},
    idempotencyKey: `audiobook.loadPopular:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeLoadRecentlyListenedIntent(): AudiobookLoadRecentlyListenedIntent {
  return {
    kind: 'audiobook.loadRecentlyListened',
    payload: {},
    idempotencyKey: `audiobook.loadRecentlyListened:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeOpenDetailIntent(audiobookId: string): AudiobookOpenDetailIntent {
  return {
    kind: 'audiobook.openDetail',
    payload: { audiobookId },
    idempotencyKey: `audiobook.openDetail:${audiobookId}:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeRequestDownloadIntent(audiobookId: string): AudiobookRequestDownloadIntent {
  return {
    kind: 'audiobook.requestDownload',
    payload: { audiobookId },
    idempotencyKey: `audiobook.requestDownload:${audiobookId}:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}

export function makeContinueListeningIntent(): AudiobookContinueListeningIntent {
  return {
    kind: 'audiobook.continueListening',
    payload: {},
    idempotencyKey: `audiobook.continueListening:${Date.now()}`,
    source: 'phone' as never,
    tsMs: Date.now(),
  };
}
