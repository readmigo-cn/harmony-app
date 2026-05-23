import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { StoreKeys } from '../store/StoreKeys';
import { RemoteController } from '../features/multi-platform/service/RemoteController';

const TAG = 'SmartScreenAbility';

/**
 * SmartScreenAbility — W15-C3 智慧屏 (TV) 入口
 *
 * 使用场景：
 *   - HarmonyOS 智慧屏（华为智慧屏 / Vision）— 大屏阅读 + 听书
 *   - 客厅多人共享 — 大字号、高对比度、遥控器交互
 *   - 离手机环境 — 单纯听书时可全屏沉浸
 *
 * launchType=singleton：电视屏幕同时只展示一个会话窗口；
 * 通过 onNewWant 接收主 App / 遥控器 want.parameters.target 切换页面。
 *
 * 三页 fragment（路由由 AppStorage 中的 SmartScreen target 驱动，由
 * SmartScreenHomePage 内部 if/else 渲染对应组件）：
 *   - home       默认大屏首页（banner + 分类 + 最近阅读）
 *   - reader     全屏 48-72pt 阅读 + 自动滚动
 *   - audiobook  书封大图 + waveform + 控制按钮
 *
 * 遥控器：
 *   - 启动时统一注册 RemoteController.attach(window) 监听全局 KeyEvent
 *   - DPAD 走 ArkUI focus chain；MENU/BACK 由各页面自行 hook
 *   - PLAY_PAUSE 始终广播给 AudioPlayerStore（无论当前在哪个 fragment）
 */
export default class SmartScreenAbility extends UIAbility {
  private targetPage: string = 'home';
  private remote: RemoteController | null = null;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (want && want.parameters) {
      const params = want.parameters as Record<string, Object>;
      this.targetPage = (params.target as string) ?? 'home';
      const bookId = (params.bookId as string) ?? '';
      const audiobookId = (params.audiobookId as string) ?? '';
      if (bookId) {
        AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_BOOK, bookId);
      }
      if (audiobookId) {
        AppStorage.SetOrCreate<string>('audio_current_id', audiobookId);
      }
    }
    AppStorage.SetOrCreate<string>('smart_screen_target', this.targetPage);
    AppStorage.SetOrCreate<boolean>('smart_screen_active', true);
    console.info(`${TAG} onCreate target=${this.targetPage}`);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (want && want.parameters) {
      const params = want.parameters as Record<string, Object>;
      const next = (params.target as string) ?? '';
      if (next) {
        this.targetPage = next;
        AppStorage.SetOrCreate<string>('smart_screen_target', next);
      }
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/tv/SmartScreenHome', (error, data) => {
      if (error.code) {
        console.error(`${TAG} loadContent failed: ${error.code} ${error.message}`);
        return;
      }
      // 全屏 + 横屏，关闭系统状态栏（智慧屏一般无状态栏，这里兜底）
      try {
        const win = windowStage.getMainWindowSync();
        win.setWindowLayoutFullScreen(true);
        win.setPreferredOrientation(window.Orientation.LANDSCAPE);
        // 注册遥控器监听
        this.remote = new RemoteController();
        this.remote.attach(win);
        console.info(`${TAG} window ready, remote attached`);
      } catch (e) {
        console.warn(`${TAG} window config failed: ${(e as Error).message}`);
      }
    });
  }

  onWindowStageDestroy(): void {
    if (this.remote) {
      this.remote.detach();
      this.remote = null;
    }
    AppStorage.SetOrCreate<boolean>('smart_screen_active', false);
    console.info(`${TAG} onWindowStageDestroy`);
  }

  onForeground(): void {
    AppStorage.SetOrCreate<boolean>('smart_screen_active', true);
    console.info(`${TAG} onForeground`);
  }

  onBackground(): void {
    console.info(`${TAG} onBackground`);
  }

  onDestroy(): void {
    console.info(`${TAG} onDestroy`);
  }
}
