import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { PagePath } from '../core/router/RouteConstants';

const TAG = 'SettingsAbility';

/**
 * SettingsAbility：独立设置入口。
 *
 * 使用场景：
 *   - 元服务「米果智读设置」一键打开
 *   - 系统设置 → App 详情 → 跳本 App 设置（HarmonyOS 5+ deep link）
 *
 * 设置页本身在 pages/Me 内（W4 用 Me 承载设置子项）。这里直接 load Me 即可，
 * Me 页 onPageShow 时根据 want.parameters.section 决定滚动位置（占位 TODO）。
 */
export default class SettingsAbility extends UIAbility {
  private targetSection: string = '';

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (want && want.parameters) {
      const params = want.parameters as Record<string, Object>;
      this.targetSection = (params.section as string) ?? '';
    }
    console.info(`${TAG} onCreate section=${this.targetSection}`);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (want && want.parameters) {
      const params = want.parameters as Record<string, Object>;
      this.targetSection = (params.section as string) ?? '';
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 设置子页位于 pages/Me，按需滚动到 targetSection（实际滚动逻辑由 Me 页内消费）
    windowStage.loadContent(PagePath.ME, (error) => {
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
