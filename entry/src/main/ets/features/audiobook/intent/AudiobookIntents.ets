// L3 Feature - Audiobook - Intent
import type { PlayAudiobookIntent, PauseAudiobookIntent } from '../../../core/intent/Intent';

export type { PlayAudiobookIntent, PauseAudiobookIntent };

export type AudiobookIntent = PlayAudiobookIntent | PauseAudiobookIntent;
export type AudiobookIntentKind = AudiobookIntent['kind'];

export const AUDIOBOOK_INTENT_KINDS: AudiobookIntentKind[] = [
  'audiobook.play',
  'audiobook.pause',
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
