import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';

const TAG = 'ShareWordAbility';

/**
 * 单词分享元服务（W11-C2）
 *
 * 元服务定位：
 *   - 用户从 Reader 划词解释卡里点「分享」 → 拉起本元服务
 *   - 不依赖主 App 是否运行；用户即装即用、低门槛分享
 *   - launchType=singleton：同一时刻只允许一张分享卡片在前台
 *
 * Want 参数约定（want.parameters）：
 *   word        : string  必填，被分享的英文单词 / 词组
 *   context     : string  可选，原文上下文句（最多 200 字符）
 *   contextZh   : string  可选，上下文中文翻译
 *   definition  : string  可选，词义（中文）
 *   phonetic    : string  可选，音标
 *   bookTitle   : string  可选，来源书名（卡片底部「来自 ××」标注）
 *   chapterTitle: string  可选，来源章节
 *
 * UI 渲染交给 `pages/atomic/ShareCardPage.ets`：
 *   - 卡片样式 + 分享 / 保存图片 / 复制 / 关闭
 *   - 用 `componentSnapshot.createFromComponent` 导出 PNG（真机才会成功，模拟器跳到占位）
 *
 * 与 HarmonyOS Share Kit 的衔接：
 *   - 后续接入 `@ohos.share`（系统分享面板）
 *   - 当前先把分享意图写到 AppStorage，由 ShareCardPage 内具体动作消费
 *
 * 与主 App 的隔离：
 *   - 元服务只读接受 want 参数，不依赖主 App Stores 已 init
 *   - 不写入用户数据；保存图片/复制等操作走系统级 API
 */
const STORAGE_KEY_PAYLOAD = 'atomic_share_word_payload';

export interface ShareWordPayload {
  word: string;
  context: string;
  contextZh: string;
  definition: string;
  phonetic: string;
  bookTitle: string;
  chapterTitle: string;
  receivedAt: number;
}

function emptyPayload(): ShareWordPayload {
  return {
    word: '',
    context: '',
    contextZh: '',
    definition: '',
    phonetic: '',
    bookTitle: '',
    chapterTitle: '',
    receivedAt: 0,
  };
}

function pickString(params: Record<string, Object>, key: string): string {
  const v = params[key];
  return typeof v === 'string' ? v : '';
}

function buildPayload(want: Want | undefined): ShareWordPayload {
  if (!want || !want.parameters) {
    return emptyPayload();
  }
  const params = want.parameters as Record<string, Object>;
  return {
    word: pickString(params, 'word'),
    context: pickString(params, 'context'),
    contextZh: pickString(params, 'contextZh'),
    definition: pickString(params, 'definition'),
    phonetic: pickString(params, 'phonetic'),
    bookTitle: pickString(params, 'bookTitle'),
    chapterTitle: pickString(params, 'chapterTitle'),
    receivedAt: Date.now(),
  };
}

export default class ShareWordAbility extends UIAbility {
  private payload: ShareWordPayload = emptyPayload();

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.payload = buildPayload(want);
    AppStorage.SetOrCreate<ShareWordPayload>(STORAGE_KEY_PAYLOAD, this.payload);
    console.info(`${TAG} onCreate word=${this.payload.word}`);
  }

  /**
   * 元服务保活态被复用 → 复用现有窗口，仅刷新 payload。
   * launchType=singleton 下，第二次拉起时会触发 onNewWant。
   */
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.payload = buildPayload(want);
    AppStorage.SetOrCreate<ShareWordPayload>(STORAGE_KEY_PAYLOAD, this.payload);
    console.info(`${TAG} onNewWant word=${this.payload.word}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/atomic/ShareCardPage', (error) => {
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
    // 清理 payload，防止下次冷启动复用旧数据
    AppStorage.SetOrCreate<ShareWordPayload>(STORAGE_KEY_PAYLOAD, emptyPayload());
    console.info(`${TAG} onDestroy`);
  }
}

/**
 * AppStorage key 常量导出，供 ShareCardPage / AtomicLauncher 复用。
 * 不放到 StoreKeys.ets：ShareWordAbility 是元服务范畴的私有 key。
 */
export const SHARE_WORD_STORAGE_KEY = STORAGE_KEY_PAYLOAD;
