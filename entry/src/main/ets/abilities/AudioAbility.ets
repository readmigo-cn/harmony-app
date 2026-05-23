import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { StoreKeys } from '../store/StoreKeys';
import { PagePath } from '../core/router/RouteConstants';

const TAG = 'AudioAbility';

/**
 * AudioAbility：独立的有声书播放入口。
 *
 * 使用场景：
 *   - 通知栏 / 锁屏控件「点击展开播放器」
 *   - 元服务「正在收听」直达
 *   - 与 TtsServiceExtAbility 配合：service 后台播，UI 用此 ability 显示
 *
 * launchType 选择 singleton —— 同时只允许一个有声书前台 UI（避免双播）。
 * 后台保活由 ServiceExtensionAbility (TtsServiceExtAbility) 承担，
 * 此 ability 只负责 UI 渲染。
 */
export default class AudioAbility extends UIAbility {
  private audiobookId: string = '';
  private chapterIndex: number = 0;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (want && want.parameters) {
      const params = want.parameters as Record<string, Object>;
      this.audiobookId = (params.audiobookId as string) ?? '';
      this.chapterIndex = (params.chapterIndex as number) ?? 0;
    }
    if (this.audiobookId) {
      // 写入 AppStorage，AudioPlayerStore 监听后自动加载
      AppStorage.SetOrCreate<string>('audio_current_id', this.audiobookId);
      AppStorage.SetOrCreate<number>('audio_current_chapter', this.chapterIndex);
    }
    console.info(`${TAG} onCreate audiobookId=${this.audiobookId} chapter=${this.chapterIndex}`);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (want && want.parameters) {
      const params = want.parameters as Record<string, Object>;
      const newId = (params.audiobookId as string) ?? '';
      if (newId) {
        this.audiobookId = newId;
        AppStorage.SetOrCreate<string>('audio_current_id', newId);
      }
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent(PagePath.AUDIOBOOK_PLAYER, (error) => {
      if (error.code) {
        console.error(`${TAG} loadContent failed: ${error.code} ${error.message}`);
      }
    });
  }

  onWindowStageDestroy(): void {
    console.info(`${TAG} onWindowStageDestroy`);
  }

  /**
   * 切前台：通知 TtsServiceExtAbility 暂时切回普通模式（占位）。
   * 实际 IPC 见 TtsServiceExtAbility，TODO Phase 2 完成。
   */
  onForeground(): void {
    console.info(`${TAG} onForeground`);
  }

  /**
   * 切后台：UI 不可见，通知 service 提升为前台保活播放。
   */
  onBackground(): void {
    console.info(`${TAG} onBackground - request TTS service stay-alive`);
  }

  onDestroy(): void {
    console.info(`${TAG} onDestroy`);
  }
}
