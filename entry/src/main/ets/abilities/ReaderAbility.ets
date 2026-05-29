import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { StoreKeys } from '../store/StoreKeys';
import { PagePath } from '../core/router/RouteConstants';
import { ContinuationManager } from '../core/atomic/ContinuationManager';

const TAG = 'ReaderAbility';

/**
 * ReaderAbility — 独立阅读器入口，同时也是跨端 Continuation 的发起方。
 *
 * 续读生命周期：
 *   onCreate  → ContinuationManager.register()      — 向系统注册为可接续
 *   onContinue → ContinuationManager.serializeToWant — 序列化当前阅读状态
 *   onCreate (target device, launchReason=CONTINUATION) →
 *               ContinuationManager.restoreFromWant  — 还原到 ReadingSoul
 *   onDestroy → ContinuationManager.unregister()    — 释放 token
 */
export default class ReaderAbility extends UIAbility {
  private bookId: string = '';
  private chapterId: string = '';
  /** 标记本次启动是否为续读恢复（launchReason === CONTINUATION）。 */
  private isContinuation: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (want && want.parameters) {
      const params = want.parameters as Record<string, Object>;
      this.bookId = (params.bookId as string) ?? '';
      this.chapterId = (params.chapterId as string) ?? '';
    }

    // 检测是否为跨端续读恢复
    this.isContinuation = launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION;

    if (this.isContinuation) {
      // 目标设备：从 want.parameters 恢复 ReadingSoul
      ContinuationManager.restoreFromWant(want).then((session) => {
        if (session) {
          this.bookId = session.bookId;
          this.chapterId = session.chapterId;
          AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_BOOK, session.bookId);
          console.info(`${TAG} continuation restored bookId=${session.bookId}`);
        }
      }).catch((e: Error) => {
        console.warn(`${TAG} restoreFromWant failed: ${e.message}`);
      });
    } else {
      if (this.bookId) {
        AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_BOOK, this.bookId);
      }
    }

    // 向 Continuation 框架注册（发起方设备）
    ContinuationManager.register();
    console.info(`${TAG} onCreate bookId=${this.bookId} isContinuation=${this.isContinuation}`);
  }

  /**
   * HarmonyOS Continuation 框架回调（发起方设备）。
   *
   * 用户在设备选择器选定目标设备后，系统在迁移前调用此方法。
   * 返回 AGREE 则框架把 wantParam 中的数据发送到目标设备，
   * 目标设备的 ReaderAbility.onCreate 以 CONTINUATION reason 启动。
   */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    return ContinuationManager.serializeToWant(wantParam);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      ContinuationManager.restoreFromWant(want).then((session) => {
        if (session) {
          this.bookId = session.bookId;
          AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_BOOK, session.bookId);
        }
      }).catch(() => {});
      return;
    }
    if (want && want.parameters) {
      const params = want.parameters as Record<string, Object>;
      const newBookId = (params.bookId as string) ?? '';
      if (newBookId) {
        this.bookId = newBookId;
        AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_BOOK, newBookId);
      }
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent(PagePath.READER, (error) => {
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
    ContinuationManager.unregister();
    console.info(`${TAG} onDestroy`);
  }
}
