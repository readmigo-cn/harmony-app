import media from '@ohos.multimedia.media';
import {
  TtsManifest,
  findSentenceAt,
} from '../../../model/TtsManifest';
import type { TtsHandle, TtsStatus } from './TtsService';

const POLL_INTERVAL_MS = 200;
const INIT_TIMEOUT_MS = 60_000;

/**
 * CloudTtsPlayer — TTS v3 真播放器：流式拉 server 预生成 MP3，
 * 按 manifest.sentences 时间戳实时驱动 sentence-level 高亮。
 *
 * 流程：
 *   constructor(manifest) → init(speed) → 内部建立 AVPlayer → prepare → play
 *   200ms 轮询 player.currentTime → findSentenceAt() → 句子变化时 emit
 *
 * 与 MockTtsHandle 平行实现 TtsHandle 接口；TtsService.speak() 按 provider 路由：
 *   - provider='tts-v3' + manifest 可拉到 → CloudTtsPlayer
 *   - 其它 / manifest=null → MockTtsHandle（保留原行为）
 *
 * 失败安全：init 任何环节抛错都向上传播让 TtsService 降级 mock；
 * AVPlayer API 在 HarmonyOS NEXT 各版本签名略有差异，关键调用包 try/catch。
 */
export class CloudTtsPlayer implements TtsHandle {
  id: string;
  status: TtsStatus = 'playing';
  text: string;
  currentCharIndex: number = 0;

  private readonly manifest: TtsManifest;
  private readonly totalChars: number;
  private player: media.AVPlayer | null = null;
  private pollTimer: number = -1;
  private currentSentenceIdx: number = -1;

  private progressCb: (charIndex: number, total: number) => void = () => {};
  private completeCb: () => void = () => {};
  private errorCb: (err: Error) => void = () => {};
  private sentenceChangeCb: (idx: number) => void = () => {};

  constructor(id: string, manifest: TtsManifest) {
    this.id = id;
    this.manifest = manifest;
    // 章节全文 = sentences 顺序拼接，供 UI 取 totalChars / text。
    const buf: string[] = [];
    for (let i = 0; i < manifest.sentences.length; i++) buf.push(manifest.sentences[i].text);
    this.text = buf.join('');
    this.totalChars = this.text.length;
  }

  /**
   * 必须在 constructor 后异步调用。
   * 失败时 status='error'，调用方应 fallback 到 mock 路径。
   */
  async init(speed: number): Promise<void> {
    try {
      this.player = await media.createAVPlayer();
      const player = this.player;
      (player as unknown as Record<string, string>)['url'] = this.manifest.audioUrl;

      await new Promise<void>((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('av_player_init_timeout'));
        }, INIT_TIMEOUT_MS) as unknown as number;
        const cleanup = (): void => { clearTimeout(timeout); };

        player.on('stateChange', async (state: string, _reason: number) => {
          try {
            if (state === 'initialized') {
              await player.prepare();
              return;
            }
            if (state === 'prepared') {
              this.applySpeedSafe(speed);
              cleanup();
              resolve();
              return;
            }
            if (state === 'error') {
              cleanup();
              reject(new Error('av_player_state_error'));
            }
          } catch (e) {
            cleanup();
            reject(e as Error);
          }
        });
        player.on('error', (err: { message?: string }) => {
          cleanup();
          reject(new Error(err.message ?? 'av_player_error'));
        });
      });

      // 完播回调
      this.player.on('completed', () => {
        if (this.status === 'playing' || this.status === 'paused') {
          this.status = 'completed';
          this.stopPolling();
          try { this.completeCb(); } catch (_e) { /* swallow */ }
        }
      });

      await this.player.play();
      this.startPolling();
    } catch (err) {
      this.status = 'error';
      this.releasePlayer();
      try { this.errorCb(err as Error); } catch (_e) { /* swallow */ }
      throw err;
    }
  }

  // ---------- TtsHandle interface ----------

  pause(): void {
    if (this.status !== 'playing' || !this.player) return;
    this.status = 'paused';
    try { this.player.pause().catch(() => {}); } catch (_e) { /* swallow */ }
    this.stopPolling();
  }

  resume(): void {
    if (this.status !== 'paused' || !this.player) return;
    this.status = 'playing';
    try { this.player.play().catch(() => {}); } catch (_e) { /* swallow */ }
    this.startPolling();
  }

  cancel(): void {
    if (this.status === 'completed' || this.status === 'stopped') return;
    this.status = 'stopped';
    this.stopPolling();
    this.releasePlayer();
  }

  onProgress(callback: (charIndex: number, total: number) => void): void {
    this.progressCb = callback;
  }

  onComplete(callback: () => void): void {
    this.completeCb = callback;
  }

  onError(callback: (err: Error) => void): void {
    this.errorCb = callback;
  }

  /** CloudTtsPlayer 独有：句级高亮事件。MockTtsHandle 无此能力。 */
  onSentenceChange(callback: (sentenceIdx: number) => void): void {
    this.sentenceChangeCb = callback;
  }

  getCurrentSentenceIdx(): number {
    return this.currentSentenceIdx;
  }

  // ---------- internals ----------

  private startPolling(): void {
    if (this.pollTimer !== -1) return;
    this.pollTimer = setInterval(() => {
      if (!this.player || this.status !== 'playing') return;
      const currentMs = this.readCurrentTimeMs();
      if (currentMs < 0) return;
      const idx = findSentenceAt(this.manifest.sentences, currentMs);
      if (idx >= 0 && idx !== this.currentSentenceIdx) {
        this.currentSentenceIdx = idx;
        const s = this.manifest.sentences[idx];
        this.currentCharIndex = s.charStart;
        try { this.sentenceChangeCb(idx); } catch (_e) { /* swallow */ }
        try { this.progressCb(s.charStart, this.totalChars); } catch (_e) { /* swallow */ }
      }
    }, POLL_INTERVAL_MS) as unknown as number;
  }

  private stopPolling(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private readCurrentTimeMs(): number {
    try {
      const v = (this.player as unknown as { currentTime?: number }).currentTime;
      return typeof v === 'number' ? v : -1;
    } catch (_e) {
      return -1;
    }
  }

  /** setSpeed API 在不同 HarmonyOS 版本签名不同；失败不致命。 */
  private applySpeedSafe(speed: number): void {
    if (!this.player) return;
    try {
      const fn = (this.player as unknown as Record<string, (n: number) => Promise<void> | void>)['setSpeed'];
      if (typeof fn === 'function') {
        const r = fn.call(this.player, speed);
        if (r && typeof (r as Promise<void>).catch === 'function') {
          (r as Promise<void>).catch(() => {});
        }
      }
    } catch (_e) { /* swallow */ }
  }

  private releasePlayer(): void {
    if (!this.player) return;
    try {
      const r = this.player.release();
      if (r && typeof r.catch === 'function') r.catch(() => {});
    } catch (_e) { /* swallow */ }
    this.player = null;
  }
}
