/**
 * TtsService.ets — W8-C5 TTS 服务抽象
 *
 * 定位：朗读 / 暂停 / 续播 / 停止 / 切换音色 + 速度，统一对外接口；底层 provider 可切换。
 *
 * Provider：
 *   - 'huawei-system' 默认，HarmonyOS 系统 TTS（@ohos.text-to-speech）
 *                     真实 SDK 调用占位，Phase 2 W7 接入 AudioRenderer + 系统 TTS
 *   - 'xunfei'        Phase 4：讯飞云 TTS WebSocket 流式
 *   - 'aliyun'        Phase 4：阿里云 TTS REST 接口
 *
 * 当前所有 provider 均为 mock：
 *   - 内部启动一个 setInterval（10 chars/sec）模拟 TTS 渲染进度
 *   - onProgress(charIndex, total) 触发，用于 SentenceHighlight 实时同步
 *   - onComplete 在 charIndex 到 total 时触发
 *
 * 后台播放：
 *   - 通过 W5 TtsServiceExtAbility 的 RPC IPC 通信（startServiceExtensionAbility / connectServiceExtensionAbility）
 *   - Mock 实现下仅打印 log，不阻塞主线程
 *
 * 与 SettingsStore：
 *   - voice / speed 持久化到 SettingsStore.tts.{voice, speed}
 *   - provider 持久化到 AppStorage（settings_tts_provider）
 */

import common from '@ohos.app.ability.common';
import Want from '@ohos.app.ability.Want';
import { SsmlBuilder } from '../../../features/audiobook/components/SsmlBuilder';
import { SettingsStore } from '../../../store/SettingsStore';

// ---------- 公共类型 ----------

export type TtsProvider = 'huawei-system' | 'xunfei' | 'aliyun';

export interface Voice {
  id: string;
  name: string;
  lang: string;
  gender: 'male' | 'female' | 'neutral';
  provider: TtsProvider;
}

export interface TtsSpeakOptions {
  /** 强制 voice，覆盖 setVoice */
  voice?: string;
  /** 强制 speed，覆盖 setSpeed */
  speed?: number;
  /** 关联书籍 + 段落，用于 ServiceExt 后台栏与会话恢复 */
  bookId?: string;
  chapterIndex?: number;
  paragraphIndex?: number;
}

export type TtsStatus = 'playing' | 'paused' | 'stopped' | 'completed' | 'error';

/** 朗读句柄：调用方持有，外部通过它操控播放状态。 */
export interface TtsHandle {
  id: string;
  status: TtsStatus;
  text: string;
  currentCharIndex: number;
  cancel(): void;
  pause(): void;
  resume(): void;
  onProgress(callback: (charIndex: number, total: number) => void): void;
  onComplete(callback: () => void): void;
  onError(callback: (err: Error) => void): void;
}

// ---------- IPC 命令码（与 TtsServiceExtAbility 对齐） ----------

const TTS_IPC_CMD = {
  START: 1,
  PAUSE: 2,
  RESUME: 3,
  STOP: 4,
  SET_VOICE: 5,
  SET_SPEED: 6,
};

// ---------- Mock 默认音色清单 ----------

const DEFAULT_VOICES: Voice[] = [
  { id: 'huawei-female-cn',  name: '小薇 (女声)',     lang: 'zh-CN', gender: 'female', provider: 'huawei-system' },
  { id: 'huawei-male-cn',    name: '小华 (男声)',     lang: 'zh-CN', gender: 'male',   provider: 'huawei-system' },
  { id: 'huawei-female-en',  name: 'Sophia (English)', lang: 'en-US', gender: 'female', provider: 'huawei-system' },
  { id: 'xunfei-xiaoyan',    name: '晓燕 (讯飞)',     lang: 'zh-CN', gender: 'female', provider: 'xunfei' },
  { id: 'aliyun-xiaomei',    name: '小美 (阿里)',     lang: 'zh-CN', gender: 'female', provider: 'aliyun' },
];

// ---------- TtsHandle 默认实现 ----------

class MockTtsHandle implements TtsHandle {
  id: string;
  status: TtsStatus = 'playing';
  text: string;
  currentCharIndex: number = 0;
  private total: number;
  private speed: number;
  private timer: number = -1;
  private progressCb: (i: number, t: number) => void = () => {};
  private completeCb: () => void = () => {};
  private errorCb: (e: Error) => void = () => {};
  private onCancelInternal: () => void;
  private onPauseInternal: () => void;
  private onResumeInternal: () => void;

  constructor(
    id: string,
    text: string,
    speed: number,
    onCancel: () => void,
    onPause: () => void,
    onResume: () => void,
  ) {
    this.id = id;
    this.text = text;
    this.total = text.length;
    this.speed = speed;
    this.onCancelInternal = onCancel;
    this.onPauseInternal = onPause;
    this.onResumeInternal = onResume;
    this.startTicking();
  }

  private startTicking(): void {
    if (this.timer !== -1) return;
    // 模拟 10 chars/sec * speed
    const intervalMs = Math.max(20, Math.round(1000 / (10 * this.speed)));
    this.timer = setInterval(() => {
      // W11 Critical 修复：每次 callback 前都重新校验 status，避免 cancel 后回调污染
      if (this.status !== 'playing') return;
      this.currentCharIndex += 1;
      // 再次校验：在自增和回调之间 cancel 的极小窗口
      if (this.status === 'playing') this.progressCb(this.currentCharIndex, this.total);
      if (this.currentCharIndex >= this.total && this.status === 'playing') {
        this.status = 'completed';
        this.stopTicking();
        // 仅 completed 状态触发 complete 回调（避免与 cancel 竞争）
        if (this.status === 'completed') this.completeCb();
      }
    }, intervalMs) as unknown as number;
  }

  private stopTicking(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  cancel(): void {
    if (this.status === 'completed' || this.status === 'stopped') return;
    this.status = 'stopped';
    this.stopTicking();
    this.onCancelInternal();
  }

  pause(): void {
    if (this.status !== 'playing') return;
    this.status = 'paused';
    this.onPauseInternal();
  }

  resume(): void {
    if (this.status !== 'paused') return;
    this.status = 'playing';
    this.onResumeInternal();
    this.startTicking();
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

  failWith(err: Error): void {
    this.status = 'error';
    this.stopTicking();
    this.errorCb(err);
  }
}

// ---------- 主服务 ----------

export class TtsService {
  private static instance: TtsService | null = null;

  private provider: TtsProvider = 'huawei-system';
  private voice: string = 'huawei-female-cn';
  private speed: number = 1.0;
  private currentHandle: MockTtsHandle | null = null;
  private nextId: number = 1;
  private context: common.UIAbilityContext | null = null;

  static getInstance(): TtsService {
    if (!TtsService.instance) {
      TtsService.instance = new TtsService();
      TtsService.instance.hydrateFromSettings();
    }
    return TtsService.instance;
  }

  /** Reader 启动时把 UIAbility context 传进来，用于跨进程拉起 ServiceExt。 */
  attachContext(ctx: common.UIAbilityContext): void {
    this.context = ctx;
  }

  // ---------- 配置 ----------

  setProvider(provider: TtsProvider): void {
    this.provider = provider;
    AppStorage.SetOrCreate<string>('settings_tts_provider', provider);
  }

  getProvider(): TtsProvider {
    return this.provider;
  }

  setVoice(voice: string): void {
    this.voice = voice;
    const cur = SettingsStore.getTts();
    SettingsStore.setTts({ voice, speed: cur.speed });
    this.sendIpc(TTS_IPC_CMD.SET_VOICE, { voice });
  }

  setSpeed(speed: number): void {
    const clamped = Math.max(0.5, Math.min(2.0, speed));
    this.speed = clamped;
    const cur = SettingsStore.getTts();
    SettingsStore.setTts({ voice: cur.voice, speed: clamped });
    this.sendIpc(TTS_IPC_CMD.SET_SPEED, { speed: clamped });
  }

  getAvailableVoices(): Voice[] {
    // 仅返回当前 provider 的音色（Mock：huawei-system 时回三条系统 voice）
    return DEFAULT_VOICES.filter((v) => v.provider === this.provider);
  }

  // ---------- 朗读控制 ----------

  /**
   * 启动 TTS 朗读。如果当前已有 handle 在播放，则先取消旧的。
   * 返回的 handle 暴露 pause/resume/cancel + 事件回调。
   */
  async speak(text: string, opts?: TtsSpeakOptions): Promise<TtsHandle> {
    if (!text || !text.trim()) {
      throw new Error('empty_text');
    }
    if (this.currentHandle) {
      this.currentHandle.cancel();
      this.currentHandle = null;
    }
    const useVoice = opts?.voice ?? this.voice;
    const useSpeed = opts?.speed ?? this.speed;

    // 生成 SSML（虽然 Mock 不会真送给 SDK，但保持完整链路）
    const ssml = SsmlBuilder.fromPlainText(text, {
      lang: this.guessLang(text),
      voice: useVoice,
      prosody: { rate: this.rateToken(useSpeed) },
    });
    console.info(`[TtsService] speak ssml.len=${ssml.length} voice=${useVoice} speed=${useSpeed}`);

    // 拉起后台 ServiceExt（Mock：仅打 log）
    this.sendIpc(TTS_IPC_CMD.START, {
      bookId: opts?.bookId ?? '',
      chapterIndex: opts?.chapterIndex ?? 0,
      paragraphIndex: opts?.paragraphIndex ?? 0,
      voice: useVoice,
      speed: useSpeed,
      ssml,
    });

    const id = `tts-${this.nextId++}`;
    const handle = new MockTtsHandle(
      id,
      text,
      useSpeed,
      () => this.sendIpc(TTS_IPC_CMD.STOP, {}),
      () => this.sendIpc(TTS_IPC_CMD.PAUSE, {}),
      () => this.sendIpc(TTS_IPC_CMD.RESUME, {}),
    );
    this.currentHandle = handle;
    return handle;
  }

  pause(handle?: TtsHandle): void {
    const h = handle ?? this.currentHandle;
    if (!h) return;
    h.pause();
  }

  resume(handle?: TtsHandle): void {
    const h = handle ?? this.currentHandle;
    if (!h) return;
    h.resume();
  }

  stop(handle?: TtsHandle): void {
    const h = handle ?? this.currentHandle;
    if (!h) return;
    h.cancel();
    if (h === this.currentHandle) {
      this.currentHandle = null;
    }
  }

  /** 返回当前活跃的 handle，UI 层订阅进度时使用。 */
  getCurrent(): TtsHandle | null {
    return this.currentHandle;
  }

  // ---------- 内部 ----------

  private hydrateFromSettings(): void {
    const tts = SettingsStore.getTts();
    if (tts.voice) this.voice = tts.voice;
    if (tts.speed) this.speed = tts.speed;
    const stored = AppStorage.Get<string>('settings_tts_provider');
    if (stored === 'huawei-system' || stored === 'xunfei' || stored === 'aliyun') {
      this.provider = stored;
    }
  }

  private guessLang(text: string): string {
    return /[一-鿿]/.test(text) ? 'zh-CN' : 'en-US';
  }

  /** speed 数值映射成 SSML rate token：0.5 -> "x-slow", 2.0 -> "x-fast"，其它做百分比。 */
  private rateToken(speed: number): string {
    if (speed <= 0.6)  return 'x-slow';
    if (speed <= 0.85) return 'slow';
    if (speed <= 1.15) return 'medium';
    if (speed <= 1.6)  return 'fast';
    return 'x-fast';
  }

  /**
   * 通过 startServiceExtensionAbility 一次性触发 TtsServiceExtAbility 命令。
   * 真实 IPC 长连接（connectServiceExtensionAbility + sendMessageRequest）TODO Phase 2。
   */
  private sendIpc(cmd: number, payload: Record<string, Object>): void {
    const ctx = this.context;
    if (!ctx) {
      console.info(`[TtsService] sendIpc cmd=${cmd} (no context, mock-only)`);
      return;
    }
    const want: Want = {
      bundleName: ctx.abilityInfo.bundleName,
      abilityName: 'TtsServiceExtAbility',
      parameters: { cmd, ...payload },
    };
    try {
      ctx.startServiceExtensionAbility(want).catch((err: Error) => {
        console.warn(`[TtsService] startServiceExtensionAbility failed: ${err.message}`);
      });
    } catch (err) {
      console.warn(`[TtsService] sendIpc throw: ${(err as Error).message}`);
    }
  }
}
