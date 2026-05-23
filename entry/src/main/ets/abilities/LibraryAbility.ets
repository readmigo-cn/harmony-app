import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { PagePath } from '../core/router/RouteConstants';

const TAG = 'LibraryAbility';

/**
 * LibraryAbility：独立的书库入口。
 *
 * 使用场景：
 *   - 元服务「我的书架」直接打开 pages/Library
 *   - 桌面快捷方式 → 跳过 Index 路由判定，直达书库
 *
 * 不重复跑 EntryAbility 的初始化（同进程下 Stores 已 init）。
 * 如果是冷启动直接走 LibraryAbility（极端场景），Library 页内部会通过
 * UserStore.isAuthenticated() 守卫并跳 Login。
 */
export default class LibraryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    console.info(`${TAG} onCreate`);
  }

  onNewWant(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    console.info(`${TAG} onNewWant`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent(PagePath.LIBRARY, (error) => {
      if (error.code) {
        console.error(`${TAG} loadContent failed: ${error.code} ${error.message}`);
      }
    });
  }

  onWindowStageDestroy(): void {
    console.info(`${TAG} onWindowStageDestroy`);
  }

  onForeground(): void {
    console.info(`${TAG} onForeground`);
  }

  onBackground(): void {
    console.info(`${TAG} onBackground`);
  }

  onDestroy(): void {
    console.info(`${TAG} onDestroy`);
  }
}
