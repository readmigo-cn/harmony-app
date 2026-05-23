import ServiceExtensionAbility from '@ohos.app.ability.ServiceExtensionAbility';
import Want from '@ohos.app.ability.Want';
import rpc from '@ohos.rpc';

const TAG = 'TtsServiceExtAbility';

/**
 * IPC 命令码：client 通过 sendMessageRequest 发送对应 code 调用 service。
 * Phase 2 接入 W7-W8 讯飞 TTS 后，载荷字段改为讯飞协议。
 */
enum TtsCommand {
  START = 1,
  PAUSE = 2,
  RESUME = 3,
  STOP = 4,
  SET_VOICE = 5,
  SET_SPEED = 6,
}

/**
 * TTS 朗读会话状态。 service 进程内单例，外部通过 IPC 操作。
 */
interface TtsSession {
  bookId: string;
  chapterIndex: number;
  paragraphIndex: number;
  voice: string;
  speed: number;
  state: 'idle' | 'playing' | 'paused';
}

/**
 * TtsServiceExtAbility：后台 TTS 朗读服务。
 *
 * 设计目标：
 *   1) 用户切到后台 / 锁屏，朗读不中断（依赖 ServiceExtension 进程独立保活）
 *   2) 跨 ability 共享朗读状态（AudioAbility 的 UI 是消费方，此 service 是生产方）
 *   3) 通知栏卡片：实时显示当前段落 + 暂停/继续按钮
 *
 * 限制：
 *   - HarmonyOS NEXT 后台音频需声明 ohos.permission.KEEP_BACKGROUND_RUNNING
 *     + backgroundModes: ["audioPlayback"]，在 module.json5 abilityType=service 项配置
 *   - 实际 TTS 引擎调用（讯飞 / 系统 TTS）TODO Phase 2 接入
 */
export default class TtsServiceExtAbility extends ServiceExtensionAbility {
  private session: TtsSession | null = null;

  onCreate(_want: Want): void {
    console.info(`${TAG} onCreate`);
  }

  /**
   * client 通过 connectAbility 建立长连接，service 返回 stub。
   * client 端 sendMessageRequest(code, data, ...) 走到 stub.onRemoteMessageRequest。
   */
  onConnect(_want: Want): rpc.RemoteObject {
    return new TtsServiceStub('TtsService', this);
  }

  onDisconnect(_want: Want): void {
    console.info(`${TAG} onDisconnect`);
  }

  /**
   * 也支持 startServiceExtensionAbility 一次性触发（不建立长连接的场景）。
   */
  onRequest(want: Want, _startId: number): void {
    if (!want || !want.parameters) {
      return;
    }
    const params = want.parameters as Record<string, Object>;
    const cmd = params.cmd as number;
    this.dispatch(cmd, params);
  }

  onDestroy(): void {
    this.stopInternal();
    console.info(`${TAG} onDestroy`);
  }

  // ---- 内部命令调度 ----

  dispatch(cmd: number, payload: Record<string, Object>): void {
    switch (cmd) {
      case TtsCommand.START:
        this.startInternal(payload);
        break;
      case TtsCommand.PAUSE:
        this.pauseInternal();
        break;
      case TtsCommand.RESUME:
        this.resumeInternal();
        break;
      case TtsCommand.STOP:
        this.stopInternal();
        break;
      case TtsCommand.SET_VOICE:
        if (this.session) {
          this.session.voice = (payload.voice as string) ?? this.session.voice;
        }
        break;
      case TtsCommand.SET_SPEED:
        if (this.session) {
          this.session.speed = (payload.speed as number) ?? this.session.speed;
        }
        break;
      default:
        console.warn(`${TAG} unknown cmd ${cmd}`);
    }
  }

  private startInternal(payload: Record<string, Object>): void {
    this.session = {
      bookId: (payload.bookId as string) ?? '',
      chapterIndex: (payload.chapterIndex as number) ?? 0,
      paragraphIndex: (payload.paragraphIndex as number) ?? 0,
      voice: (payload.voice as string) ?? 'zh-CN-female',
      speed: (payload.speed as number) ?? 1.0,
      state: 'playing',
    };
    // TODO(Phase 2): 调用 @ohos.multimedia.audio.AudioRenderer + 讯飞 TTS SDK
    // TODO(Phase 2): 通过 commonEvent 发布进度事件给主 App / AudioAbility UI
    // TODO(Phase 2): 注册前台通知（@ohos.notificationManager），带暂停按钮
    console.info(`${TAG} start ${this.session.bookId}`);
  }

  private pauseInternal(): void {
    if (this.session) {
      this.session.state = 'paused';
    }
    console.info(`${TAG} pause`);
  }

  private resumeInternal(): void {
    if (this.session) {
      this.session.state = 'playing';
    }
    console.info(`${TAG} resume`);
  }

  private stopInternal(): void {
    this.session = null;
    console.info(`${TAG} stop`);
  }
}

/**
 * RemoteObject stub：处理来自 client 的 IPC 调用。
 */
class TtsServiceStub extends rpc.RemoteObject {
  private host: TtsServiceExtAbility;

  constructor(descriptor: string, host: TtsServiceExtAbility) {
    super(descriptor);
    this.host = host;
  }

  onRemoteMessageRequest(
    code: number,
    data: rpc.MessageSequence,
    _reply: rpc.MessageSequence,
    _option: rpc.MessageOption,
  ): boolean {
    try {
      const json = data.readString();
      const payload: Record<string, Object> = json ? JSON.parse(json) : {};
      this.host.dispatch(code, payload);
      return true;
    } catch (err) {
      console.error(`${TAG} stub error: ${(err as Error).message}`);
      return false;
    }
  }
}
