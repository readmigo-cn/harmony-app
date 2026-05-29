// L3 Feature - Audiobook - Intent
import type {
  PlayAudiobookIntent,
  PauseAudiobookIntent,
  SeekAudiobookIntent,
  AdjustPlaybackSpeedIntent,
} from '../../../core/intent/Intent';
import { SurfaceKind } from '../../../core/surface/SurfaceKind';

export type {
  PlayAudiobookIntent,
  PauseAudiobookIntent,
  SeekAudiobookIntent,
  AdjustPlaybackSpeedIntent,
};

export type AudiobookIntent =
  | PlayAudiobookIntent
  | PauseAudiobookIntent
  | SeekAudiobookIntent
  | AdjustPlaybackSpeedIntent;

export type AudiobookIntentKind = AudiobookIntent['kind'];

export const AUDIOBOOK_INTENT_KINDS: AudiobookIntentKind[] = [
  'audiobook/play',
  'audiobook/pause',
  'audiobook/seek',
  'audiobook/adjust-speed',
];

function makeKey(kind: string, extra: string): string {
  return `${kind}:${extra}:${Date.now()}`;
}

export function makePlayAudiobookIntent(
  bookId: string,
  chapterId: string,
  positionMs: number = 0,
  source: SurfaceKind = SurfaceKind.Phone,
): PlayAudiobookIntent {
  return {
    kind: 'audiobook/play',
    payload: { bookId, chapterId, positionMs },
    idempotencyKey: makeKey('audiobook/play', `${bookId}:${chapterId}`),
    source,
    tsMs: Date.now(),
  };
}

export function makePauseAudiobookIntent(
  bookId: string,
  source: SurfaceKind = SurfaceKind.Phone,
): PauseAudiobookIntent {
  return {
    kind: 'audiobook/pause',
    payload: { bookId },
    idempotencyKey: makeKey('audiobook/pause', bookId),
    source,
    tsMs: Date.now(),
  };
}

export function makeSeekAudiobookIntent(
  bookId: string,
  positionMs: number,
  source: SurfaceKind = SurfaceKind.Phone,
): SeekAudiobookIntent {
  return {
    kind: 'audiobook/seek',
    payload: { bookId, positionMs },
    idempotencyKey: makeKey('audiobook/seek', `${bookId}:${positionMs}`),
    source,
    tsMs: Date.now(),
  };
}

export function makeAdjustPlaybackSpeedIntent(
  speed: number,
  source: SurfaceKind = SurfaceKind.Phone,
): AdjustPlaybackSpeedIntent {
  return {
    kind: 'audiobook/adjust-speed',
    payload: { speed },
    idempotencyKey: makeKey('audiobook/adjust-speed', String(speed)),
    source,
    tsMs: Date.now(),
  };
}
