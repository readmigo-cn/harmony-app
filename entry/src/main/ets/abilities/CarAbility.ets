/**
 * CarAbility — W16-C1 车机听书模式入口
 *
 * 设计目标：
 *   - 车机端只听不读：默认全屏听书首页（CarHome），不展示长文本
 *   - 安全为先：行驶中（车速 > 5 km/h）UI 完全锁定，仅响应语音命令与方向盘按键
 *   - 极简交互：3 个大按钮（继续上次 / 最近播放 / 我的书架）+ 全局语音入口
 *
 * launchType=singleton：车机仅允许一个听书 UI 实例（防止双播 / 双窗口）
 * deviceTypes=['car']：仅在 HarmonyOS car 设备上分发（在 module.json5 中体现）
 *
 * AppStorage 键约定（与 CarHome / CarPlayer / VoiceCommand 共享）：
 *   - 'car_lock_active'      : boolean — 行驶锁定状态（true 时 UI 仅显示，禁触摸）
 *   - 'car_vehicle_speed'    : number  — 车速 km/h（OEM 接口写入）
 *   - 'car_voice_listening'  : boolean — 是否正在监听语音
 *   - 'car_last_command'     : string  — 最近一次解析出的语音命令名
 *
 * 方向盘按键集成（占位）：
 *   HarmonyOS 车机通过 KeyEvent 把方向盘按键统一映射到 standard key code：
 *     KEYCODE_MEDIA_PLAY_PAUSE / NEXT / PREVIOUS / FAST_FORWARD / REWIND / VOLUME_UP/DOWN
 *   主窗口在 onKeyEvent 中拦截后转交 VoiceCommand.dispatchKey() 执行。
 */

import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { VoiceCommand } from '../features/multi-platform/service/VoiceCommand';

const TAG = 'CarAbility';

/** 行驶锁定阈值：车速 > 5 km/h 即视为行驶中，UI 全锁。 */
export const CAR_LOCK_SPEED_THRESHOLD: number = 5;

/** AppStorage 键集中常量（避免字面量散落各处）。 */
export const CAR_STORAGE_KEYS = {
  LOCK_ACTIVE: 'car_lock_active',
  VEHICLE_SPEED: 'car_vehicle_speed',
  VOICE_LISTENING: 'car_voice_listening',
  LAST_COMMAND: 'car_last_command',
} as const;

export default class CarAbility extends UIAbility {
  /** 上次启动时透传的入口（继续上次 / 最近播放 / 默认 home） */
  private entryMode: string = 'home';
  /** 车速轮询定时器：占位实现，真实环境改为订阅 OEM CAN bus。 */
  private speedPollTimer: number = -1;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (want && want.parameters) {
      const params = want.parameters as Record<string, Object>;
      this.entryMode = (params.mode as string) ?? 'home';
    }
    // 初始化 AppStorage 默认值（防止首次读取拿到 undefined）
    AppStorage.SetOrCreate<boolean>(CAR_STORAGE_KEYS.LOCK_ACTIVE, false);
    AppStorage.SetOrCreate<number>(CAR_STORAGE_KEYS.VEHICLE_SPEED, 0);
    AppStorage.SetOrCreate<boolean>(CAR_STORAGE_KEYS.VOICE_LISTENING, false);
    AppStorage.SetOrCreate<string>(CAR_STORAGE_KEYS.LAST_COMMAND, '');

    // 启动语音命令服务（注册命令、绑定 TTS 反馈）
    VoiceCommand.getInstance().attachContext(this.context);
    VoiceCommand.getInstance().registerDefaultCommands();

    console.info(`${TAG} onCreate mode=${this.entryMode}`);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (want && want.parameters) {
      const params = want.parameters as Record<string, Object>;
      this.entryMode = (params.mode as string) ?? this.entryMode;
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 车机默认全屏听书首页
    const target: string = this.entryMode === 'player' ? 'pages/car/CarPlayer' : 'pages/car/CarHome';
    windowStage.loadContent(target, (error) => {
      if (error.code) {
        console.error(`${TAG} loadContent failed: ${error.code} ${error.message}`);
        return;
      }
      this.startSpeedMonitor();
    });
  }

  onWindowStageDestroy(): void {
    this.stopSpeedMonitor();
    console.info(`${TAG} onWindowStageDestroy`);
  }

  onForeground(): void {
    console.info(`${TAG} onForeground (resume voice listening)`);
    AppStorage.SetOrCreate<boolean>(CAR_STORAGE_KEYS.VOICE_LISTENING, true);
  }

  onBackground(): void {
    console.info(`${TAG} onBackground (keep playback alive via TtsServiceExtAbility)`);
    AppStorage.SetOrCreate<boolean>(CAR_STORAGE_KEYS.VOICE_LISTENING, false);
  }

  onDestroy(): void {
    VoiceCommand.getInstance().shutdown();
    console.info(`${TAG} onDestroy`);
  }

  /**
   * 启动车速监控。
   * 占位实现：500ms 轮询 AppStorage 中的车速值（真机改为订阅 @ohos.vehicle.* CAN 信号）。
   * 一旦车速 > CAR_LOCK_SPEED_THRESHOLD，写入 LOCK_ACTIVE=true，UI 层 @StorageLink 自动锁定。
   */
  private startSpeedMonitor(): void {
    if (this.speedPollTimer !== -1) return;
    this.speedPollTimer = setInterval(() => {
      const speed = AppStorage.Get<number>(CAR_STORAGE_KEYS.VEHICLE_SPEED) ?? 0;
      const shouldLock = speed > CAR_LOCK_SPEED_THRESHOLD;
      const current = AppStorage.Get<boolean>(CAR_STORAGE_KEYS.LOCK_ACTIVE) ?? false;
      if (shouldLock !== current) {
        AppStorage.SetOrCreate<boolean>(CAR_STORAGE_KEYS.LOCK_ACTIVE, shouldLock);
        console.info(`${TAG} speed=${speed} -> lock=${shouldLock}`);
      }
    }, 500) as unknown as number;
  }

  private stopSpeedMonitor(): void {
    if (this.speedPollTimer !== -1) {
      clearInterval(this.speedPollTimer);
      this.speedPollTimer = -1;
    }
  }
}
