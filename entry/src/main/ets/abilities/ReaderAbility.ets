import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { StoreKeys } from '../store/StoreKeys';
import { PagePath } from '../core/router/RouteConstants';

const TAG = 'ReaderAbility';

/**
 * ReaderAbility：独立的阅读器入口。
 *
 * 使用场景：
 *   - 桌面卡片「上次阅读的书」直达
 *   - 元服务（Atomic Service）独立打开阅读器
 *   - 分布式协同：手机 → 平板 拉起阅读器
 *
 * 复用 EntryAbility 已经初始化好的 Stores（同进程，AppStorage 共享）。
 * 若 EntryAbility 还未启动（独立元服务场景），此 ability 也只做最小启动：
 * 由 Index.ets / Reader.ets 自行 lazy-load 数据。
 */
export default class ReaderAbility extends UIAbility {
  private bookId: string = '';
  private chapterId: string = '';

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    // want.parameters 形如 { bookId: 'xxx', chapterId?: 'yyy' }
    if (want && want.parameters) {
      const params = want.parameters as Record<string, Object>;
      this.bookId = (params.bookId as string) ?? '';
      this.chapterId = (params.chapterId as string) ?? '';
    }
    // 把目标书写入 AppStorage，供 Reader 页 onPageShow 消费
    if (this.bookId) {
      AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_BOOK, this.bookId);
    }
    console.info(`${TAG} onCreate bookId=${this.bookId}`);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
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
    // 直接加载 Reader 页（同 main_pages.json 中的 src）
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
    console.info(`${TAG} onDestroy`);
  }
}
