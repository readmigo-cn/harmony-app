/**
 * WatchAbility — W15-C1 手表 UIAbility 入口
 *
 * 适配 HarmonyOS NEXT 的 wearable 设备（圆形屏 / 表冠输入）。
 * 与 phone/tablet 入口完全独立：
 *   - module.json5 deviceTypes 仅声明 ['wearable']
 *   - launchType=singleton：手表只允许单一 UI 前台实例（避免 launcher 多开）
 *   - 启动后渲染 pages/watch/WatchHome
 *
 * 启动入口：
 *   1. 表盘卡片 (WatchVocabCard) postCardAction(router) → 携带 target=vocab/stats/audio
 *   2. 手表桌面图标直接拉起（无 want）
 *   3. 手机端通过 distributedSchedule.startRemoteAbility 跨端拉起（W10 SyncEngine）
 *
 * 集成 @ohos.vibrator：所有交互（按钮/翻卡/答对）均触发短振动反馈，弥补手表无声学习场景。
 *
 * 注：本 ability 不复用 EntryAbility 的 ResourceManager / Navigation Stack；
 *     手表 App 走极简单 Page 模式，由 WatchHome 内部管理 sub-route。
 */

import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import vibrator from '@ohos.vibrator';

const TAG = 'WatchAbility';

/** AppStorage key：手表当前 sub-page */
export const WATCH_CURRENT_PAGE_KEY: string = 'watch_current_page';
/** AppStorage key：今日阅读分钟（由 WatchSync 同步过来） */
export const WATCH_TODAY_MINUTES_KEY: string = 'watch_today_minutes';
/** AppStorage key：今日目标分钟（默认 30） */
export const WATCH_DAILY_GOAL_KEY: string = 'watch_daily_goal';
/** AppStorage key：来源（cold/card/remote） */
export const WATCH_LAUNCH_SOURCE_KEY: string = 'watch_launch_source';

/** 振动模式 — 手表交互 */
export type WatchHapticKind = 'tap' | 'success' | 'fail';

export class WatchHaptic {
  /** 触发简短振动，封装 @ohos.vibrator 的兼容差异 */
  static fire(kind: WatchHapticKind): void {
    let duration = 12;
    if (kind === 'success') duration = 30;
    if (kind === 'fail') duration = 60;
    try {
      vibrator.startVibration({ type: 'time', duration }, { usage: 'touch' }, (err) => {
        if (err) {
          console.warn(`${TAG} vibrator.startVibration err: ${err.message}`);
        }
      });
    } catch (e) {
      console.warn(`${TAG} vibrator unavailable: ${(e as Error).message}`);
    }
  }
}

export default class WatchAbility extends UIAbility {
  private launchSource: string = 'cold';
  private targetPage: string = 'home';

  // ---------- lifecycle ----------

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.parseWant(want);
    this.publishToAppStorage();
    console.info(`${TAG} onCreate source=${this.launchSource} target=${this.targetPage}`);
  }

  /**
   * singleton 二次拉起（用户在 home 页时点了卡片再次进入）。
   * 直接更新 AppStorage 触发 WatchHome 内部路由跳转。
   */
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.parseWant(want);
    this.publishToAppStorage();
    WatchHaptic.fire('tap');
    console.info(`${TAG} onNewWant target=${this.targetPage}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 手表 App 全屏沉浸（没有状态栏）
    try {
      windowStage.getMainWindow().then((win) => {
        win.setWindowLayoutFullScreen(true).catch(() => {});
      });
    } catch (_e) { /* 旧 API：忽略 */ }

    windowStage.loadContent('pages/watch/WatchHome', (error) => {
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

  // ---------- want 解析 ----------

  private parseWant(want: Want | undefined): void {
    if (!want) {
      this.launchSource = 'cold';
      this.targetPage = 'home';
      return;
    }
    const params = (want.parameters ?? {}) as Record<string, Object>;
    this.targetPage = (params.target as string) ?? 'home';
    const fromCard = params.fromCard as string | undefined;
    const fromRemote = params.fromRemote as string | undefined;
    if (fromCard) this.launchSource = 'card';
    else if (fromRemote) this.launchSource = 'remote';
    else this.launchSource = 'cold';
  }

  private publishToAppStorage(): void {
    AppStorage.SetOrCreate<string>(WATCH_CURRENT_PAGE_KEY, this.targetPage);
    AppStorage.SetOrCreate<string>(WATCH_LAUNCH_SOURCE_KEY, this.launchSource);
    // 默认目标 30 分钟（用户在 phone 端可改，由 WatchSync 拉来）
    if (AppStorage.Get<number>(WATCH_DAILY_GOAL_KEY) === undefined) {
      AppStorage.SetOrCreate<number>(WATCH_DAILY_GOAL_KEY, 30);
    }
  }
}
