import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { StoreKeys } from '../store/StoreKeys';
import { ReadingStore } from '../store/ReadingStore';
import { UserStore } from '../store/UserStore';
import { PagePath } from '../core/router/RouteConstants';

const TAG = 'ContinueReadingAbility';

/**
 * 阅读接续元服务（W11-C3）
 *
 * 元服务定位：
 *   - 「阅读卡片」点击 → 直接拉起本元服务，跳到 Reader 对应位置
 *   - HarmonyOS 分布式接续：手机阅读到第 5 页 → 自动迁到平板继续
 *   - launchType=specified（每本书一个实例，避免多书互相覆盖）
 *
 * Want 参数约定：
 *   bookId         : string  必填
 *   chapterIndex   : number  可选（默认 0）
 *   pageIndex      : number  可选（默认 0）
 *   percentComplete: number  可选（用于唤起后立即更新进度条）
 *   sourceDeviceId : string  可选（接续来源设备，用于埋点 / UI 显示）
 *
 * 启动顺序：
 *   1. onCreate 解析 want → 写 ReadingStore.currentBook
 *   2. UserStore 守卫：未登录跳 Login（带 redirectTo Reader）
 *   3. onWindowStageCreate 加载 pages/Reader
 *
 * 分布式接续 hook：
 *   - onContinue 把 bookId/chapter/page 序列化到 wantParam，迁移目标设备拉起
 *   - 实际能力依赖 ContinuationManager（占位）
 */

interface ContinueParams {
  bookId: string;
  chapterIndex: number;
  pageIndex: number;
  percentComplete: number;
  sourceDeviceId: string;
}

function emptyParams(): ContinueParams {
  return {
    bookId: '',
    chapterIndex: 0,
    pageIndex: 0,
    percentComplete: 0,
    sourceDeviceId: '',
  };
}

function pickString(params: Record<string, Object>, key: string): string {
  const v = params[key];
  return typeof v === 'string' ? v : '';
}

function pickNumber(params: Record<string, Object>, key: string, fallback: number): number {
  const v = params[key];
  if (typeof v === 'number') return v;
  if (typeof v === 'string') {
    const n = Number(v);
    return Number.isFinite(n) ? n : fallback;
  }
  return fallback;
}

function parseParams(want: Want | undefined): ContinueParams {
  if (!want || !want.parameters) return emptyParams();
  const p = want.parameters as Record<string, Object>;
  return {
    bookId: pickString(p, 'bookId'),
    chapterIndex: pickNumber(p, 'chapterIndex', 0),
    pageIndex: pickNumber(p, 'pageIndex', 0),
    percentComplete: pickNumber(p, 'percentComplete', 0),
    sourceDeviceId: pickString(p, 'sourceDeviceId'),
  };
}

export default class ContinueReadingAbility extends UIAbility {
  private params: ContinueParams = emptyParams();

  /**
   * launchType=specified 配套钩子：根据 want 决定要不要复用既有实例。
   * 同 bookId → 复用；不同 bookId → 新实例。
   */
  onAcceptWant(want: Want): string {
    const next = parseParams(want);
    const key = next.bookId ? `continue-${next.bookId}` : 'continue-default';
    return key;
  }

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.params = parseParams(want);
    this.applyToStore();
    console.info(`${TAG} onCreate bookId=${this.params.bookId} chapter=${this.params.chapterIndex} page=${this.params.pageIndex}`);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.params = parseParams(want);
    this.applyToStore();
    console.info(`${TAG} onNewWant bookId=${this.params.bookId}`);
  }

  /**
   * HarmonyOS Continuation lifecycle：迁移到目标设备前回调。
   * 把进度信息序列化到 wantParam，目标设备的 ContinueReadingAbility.onCreate 解析。
   *
   * 返回 AGREE 接受迁移；MISMATCH/REJECT 取消。
   * @param wantParam 由系统传入的可读写空 map
   */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    if (!this.params.bookId) {
      return AbilityConstant.OnContinueResult.MISMATCH;
    }
    wantParam['bookId'] = this.params.bookId;
    wantParam['chapterIndex'] = this.params.chapterIndex;
    wantParam['pageIndex'] = this.params.pageIndex;
    wantParam['percentComplete'] = this.params.percentComplete;
    wantParam['sourceDeviceId'] = this.context?.config?.deviceTypes?.[0] ?? '';
    console.info(`${TAG} onContinue serializing bookId=${this.params.bookId}`);
    return AbilityConstant.OnContinueResult.AGREE;
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 守卫：未登录 → Login + redirectTo Reader（Login 由 RouterService 解析 redirect）
    const targetPage = UserStore.isLoggedIn() ? PagePath.READER : PagePath.LOGIN;
    if (!UserStore.isLoggedIn()) {
      // 通过 AppStorage 桥接 Login 页：登录成功后跳 Reader
      AppStorage.SetOrCreate<string>('continue_reading_redirect_target', PagePath.READER);
      AppStorage.SetOrCreate<string>('continue_reading_book_id', this.params.bookId);
    }
    windowStage.loadContent(targetPage, (error) => {
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

  // ─────────── private ───────────

  /**
   * 把 want 参数应用到 ReadingStore，让 Reader 页 onPageShow 加载到正确位置。
   *
   * 仅写 currentBook + lastProgress 即可：
   *   Reader.aboutToAppear 会读 currentBook，并 ProgressSync.pull 拿最新位置。
   */
  private applyToStore(): void {
    if (!this.params.bookId) return;
    AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_BOOK, this.params.bookId);
    if (this.params.chapterIndex > 0 || this.params.pageIndex > 0) {
      ReadingStore.setLastProgress({
        bookId: this.params.bookId,
        chapterId: this.params.chapterIndex.toString(),
        position: this.params.pageIndex,
        percent: this.params.percentComplete,
        updatedAt: Date.now(),
      });
    }
  }
}
