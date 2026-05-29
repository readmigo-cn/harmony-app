import { HttpClient } from '../client/HttpClient';
import type { TtsManifest, TtsV3Voice } from '../../model/TtsManifest';

/**
 * TtsV3Api — 对齐 iOS readmigo `/v3/tts/*` 端点。
 *
 * iOS 路由：
 *   GET /v3/tts/audiobook?bookId=X&chapterId=Y&voiceId=Z&speed=N → TtsManifest
 *   GET /v3/tts/voices → TtsV3Voice[]
 *
 * **端点状态**：server-cn 是否已开放 `/v3/tts/*` 未确认（沿用 Q2=C 决策：
 * 端点对齐留 P1-B）。当前 ENDPOINT_AVAILABLE=false，方法静默返 null/empty，
 * 调用方降级到 mock TTS 或 LibriVox audioUrl 直拉。
 *
 * P1-B 联调步骤：
 *   1. 把 ENDPOINT_AVAILABLE 翻 true
 *   2. 根据 server-cn 实际响应调整 TtsManifest / TtsV3Voice 字段命名
 *   3. CloudTtsPlayer（C.2.b）自动开始用真 manifest 播放
 */

const ENDPOINT_AVAILABLE: boolean = false;

export interface TtsManifestRequest {
  bookId: string;
  chapterId: string;
  voiceId: string;
  /** 0.5 ~ 2.0 */
  speed: number;
}

export class TtsV3Api {
  static isAvailable(): boolean {
    return ENDPOINT_AVAILABLE;
  }

  /**
   * 拉整章 TTS manifest（预生成 MP3 + 句级 timestamps）。
   * 端点未就绪时返 null，调用方 fallback 到 mock provider。
   */
  static async getManifest(req: TtsManifestRequest): Promise<TtsManifest | null> {
    if (!ENDPOINT_AVAILABLE) return null;
    try {
      return await HttpClient.get<TtsManifest>('/api/v1/v3/tts/audiobook', {
        bookId: req.bookId,
        chapterId: req.chapterId,
        voiceId: req.voiceId,
        speed: req.speed,
      });
    } catch (_e) {
      return null;
    }
  }

  /**
   * 获取所有可用音色（独立于具体书）。
   */
  static async listVoices(): Promise<TtsV3Voice[]> {
    if (!ENDPOINT_AVAILABLE) return [];
    try {
      return await HttpClient.get<TtsV3Voice[]>('/api/v1/v3/tts/voices');
    } catch (_e) {
      return [];
    }
  }
}
