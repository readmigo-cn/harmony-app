/**
 * VoiceCommand — W16-C1 车机语音命令分发
 *
 * 集成入口：@ohos.ai.assistant.intent（小艺意图框架）— 当前为占位封装。
 * 真实集成时在 attachContext 后调用 intent.subscribe，将 IntentResult.commandName
 * 映射到本类 dispatch()。
 *
 * 命令清单（10 条）：
 *   播放 / 暂停 / 下一章 / 上一章 / 快进 / 倒退 / 换书 / 调速 / 音量 / 停止
 *
 * 命令分发：
 *   1. 解析命令名 + 参数（speed / volume / bookId 等）
 *   2. 调用 audioPlayerStore + TtsService 执行
 *   3. 用 TtsService.speak 播报反馈语（如「已暂停」「已切换到下一章」）
 *   4. 写入 AppStorage 'car_last_command' 供 UI 显示
 *
 * 方向盘按键：
 *   CarAbility 主窗口 onKeyEvent 把 KEYCODE_MEDIA_* 转成命令名，调 dispatchKey()。
 */

import common from '@ohos.app.ability.common';
import { audioPlayerStore } from '../../../store/AudioPlayerStore';
import { TtsService } from '../tts/TtsService';
import { CAR_STORAGE_KEYS } from '../../../abilities/CarAbility';

const TAG = 'VoiceCommand';

/** 标准化的命令名（统一用 snake_case，方便日志检索）。 */
export type CarCommandName =
  | 'play'
  | 'pause'
  | 'next_chapter'
  | 'prev_chapter'
  | 'seek_forward'
  | 'seek_backward'
  | 'switch_book'
  | 'set_speed'
  | 'set_volume'
  | 'stop';

export interface CarCommandPayload {
  /** seek 秒数（默认 15） */
  seconds?: number;
  /** set_speed 倍率 0.5 ~ 2.0 */
  speed?: number;
  /** set_volume 0 ~ 1 */
  volume?: number;
  /** switch_book 目标 audiobookId */
  bookId?: string;
}

type CommandHandler = (payload: CarCommandPayload) => void;

export class VoiceCommand {
  private static instance: VoiceCommand | null = null;
  private context: common.UIAbilityContext | null = null;
  private handlers: Map<CarCommandName, CommandHandler> = new Map();
  /** Intent 框架订阅 token（占位）。 */
  private intentToken: string = '';

  static getInstance(): VoiceCommand {
    if (!VoiceCommand.instance) {
      VoiceCommand.instance = new VoiceCommand();
    }
    return VoiceCommand.instance;
  }

  attachContext(ctx: common.UIAbilityContext): void {
    this.context = ctx;
    TtsService.getInstance().attachContext(ctx);
  }

  /**
   * 注册默认命令集（10 条）。CarAbility.onCreate 调用一次即可。
   * 真实集成时此处还需调 intent.subscribe(intentName, handler)。
   */
  registerDefaultCommands(): void {
    this.handlers.clear();

    this.handlers.set('play', () => {
      audioPlayerStore.play();
      this.feedback('开始播放');
    });
    this.handlers.set('pause', () => {
      audioPlayerStore.pause();
      this.feedback('已暂停');
    });
    this.handlers.set('next_chapter', () => {
      audioPlayerStore.nextChapter();
      this.feedback('已切换到下一章');
    });
    this.handlers.set('prev_chapter', () => {
      audioPlayerStore.previousChapter();
      this.feedback('已切换到上一章');
    });
    this.handlers.set('seek_forward', (p) => {
      audioPlayerStore.seekForward(p.seconds ?? 15);
      this.feedback(`已快进 ${p.seconds ?? 15} 秒`);
    });
    this.handlers.set('seek_backward', (p) => {
      audioPlayerStore.seekBackward(p.seconds ?? 15);
      this.feedback(`已倒退 ${p.seconds ?? 15} 秒`);
    });
    this.handlers.set('switch_book', (p) => {
      // 占位：真实切书走 audioPlayerStore.loadAudiobook(book) — 此处仅打 log + 反馈
      this.feedback(p.bookId ? `正在切换到 ${p.bookId}` : '请说出书名');
    });
    this.handlers.set('set_speed', (p) => {
      const v = Math.max(0.5, Math.min(2.0, p.speed ?? 1.0));
      // PlaybackSpeed 是受限联合类型，强转后由 store 内部校验
      audioPlayerStore.setPlaybackSpeed(v as 0.5 | 0.75 | 1.0 | 1.25 | 1.5 | 1.75 | 2.0);
      this.feedback(`语速调整为 ${v} 倍`);
    });
    this.handlers.set('set_volume', (p) => {
      const v = Math.max(0, Math.min(1, p.volume ?? 0.5));
      audioPlayerStore.volume = v;
      this.feedback(`音量调整为 ${Math.round(v * 100)}%`);
    });
    this.handlers.set('stop', () => {
      audioPlayerStore.pause();
      TtsService.getInstance().stop();
      this.feedback('已停止');
    });

    console.info(`${TAG} registered ${this.handlers.size} commands`);
    this.subscribeIntentFramework();
  }

  /**
   * 主分发入口：语音识别 / 方向盘按键 / Intent callback 都进这里。
   * 不抛异常 —— 行驶安全场景下静默忽略未知命令，只记 log。
   */
  dispatch(name: CarCommandName, payload: CarCommandPayload = {}): void {
    AppStorage.SetOrCreate<string>(CAR_STORAGE_KEYS.LAST_COMMAND, name);
    const handler = this.handlers.get(name);
    if (!handler) {
      console.warn(`${TAG} unknown command: ${name}`);
      return;
    }
    try {
      handler(payload);
      console.info(`${TAG} dispatch ok: ${name}`);
    } catch (err) {
      console.error(`${TAG} dispatch failed: ${name} ${(err as Error).message}`);
    }
  }

  /**
   * 方向盘按键映射。
   * KEYCODE 来源：HarmonyOS 标准媒体键（与 W6 通知栏控件保持一致）。
   */
  dispatchKey(keycode: number): void {
    // 与 @ohos.multimodalInput.keyCode 中常量对齐（占位常量值）
    const KEY_PLAY_PAUSE = 10090;
    const KEY_NEXT = 10091;
    const KEY_PREV = 10092;
    const KEY_FAST_FORWARD = 10093;
    const KEY_REWIND = 10094;
    const KEY_VOLUME_UP = 16;
    const KEY_VOLUME_DOWN = 17;

    switch (keycode) {
      case KEY_PLAY_PAUSE:
        this.dispatch(audioPlayerStore.isPlaying ? 'pause' : 'play');
        break;
      case KEY_NEXT:           this.dispatch('next_chapter'); break;
      case KEY_PREV:           this.dispatch('prev_chapter'); break;
      case KEY_FAST_FORWARD:   this.dispatch('seek_forward', { seconds: 15 }); break;
      case KEY_REWIND:         this.dispatch('seek_backward', { seconds: 15 }); break;
      case KEY_VOLUME_UP:      this.dispatch('set_volume', { volume: Math.min(1, audioPlayerStore.volume + 0.1) }); break;
      case KEY_VOLUME_DOWN:    this.dispatch('set_volume', { volume: Math.max(0, audioPlayerStore.volume - 0.1) }); break;
      default:                 console.info(`${TAG} ignore key=${keycode}`);
    }
  }

  /** 释放：CarAbility.onDestroy 调用，取消 intent 订阅。 */
  shutdown(): void {
    if (this.intentToken) {
      console.info(`${TAG} unsubscribe intent token=${this.intentToken}`);
      this.intentToken = '';
    }
    this.handlers.clear();
  }

  // ---------- 内部 ----------

  /** 占位：与小艺意图框架对接的桩。真实 SDK 调用注释如下。 */
  private subscribeIntentFramework(): void {
    // import intent from '@ohos.ai.assistant.intent';
    // this.intentToken = intent.subscribe({
    //   intents: ['readmigo.car.play', 'readmigo.car.pause', ...],
    //   callback: (result) => this.dispatch(result.commandName as CarCommandName, result.params),
    // });
    this.intentToken = `mock-${Date.now()}`;
    console.info(`${TAG} subscribeIntentFramework token=${this.intentToken} (mock)`);
  }

  /** TTS 反馈：行驶中也允许，因为只听不读。 */
  private feedback(text: string): void {
    TtsService.getInstance().speak(text).catch((err: Error) => {
      console.warn(`${TAG} feedback speak failed: ${err.message}`);
    });
  }
}
