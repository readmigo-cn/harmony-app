import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import formInfo from '@ohos.app.form.formInfo';
import formProvider from '@ohos.app.form.formProvider';
import formBindingData from '@ohos.app.form.formBindingData';
import { WidgetApi, AiTipCardData } from '../../api/widget/WidgetApi';

/**
 * AI 助手卡片 FormExtensionAbility（W12-C3）。
 *
 * 数据：调用 /widget/ai-tip 获取 7 天轮换贴士。
 * 缓存：内存里维护一个 7 槽 LRU，避免同一天反复展示同一条；用户手动「换一条」时
 *       从已访问 set 里筛掉再向后端要。
 *
 * 更新：
 *  - 系统定时：form_config.json 每日 09:00 + updateDuration=24（24 小时刷新一次）
 *  - 用户手动：onFormEvent('refresh') → 立即拉新
 *
 * Form 进程间共享：与其它 widget 共用 PreferencesManager namespace 'widget'，
 * 但本卡片本身不写主 App 共享数据，仅本进程内 LRU 即可。
 */

const FALLBACK_TIPS: string[] = [
  '每天坚持阅读 15 分钟，一年可以读完 12 本书。',
  '遇到不认识的单词，先猜测语境含义，再查词典，记忆效果更好。',
  '读完一章后，尝试用自己的话概括主要内容，加深理解。',
  '有声书和电子书搭配使用，通勤时听，睡前读，利用碎片时间。',
  '记读书笔记不必完整，几个关键词或一句感悟就足够。',
  '把书中的金句分享给朋友，讲述是最好的复习方式。',
  '读书时关掉通知，专注 25 分钟（番茄工作法），效率提升 40%。',
];

function fallbackTip(): AiTipCardData {
  const day = new Date().getDay();
  return { tip: FALLBACK_TIPS[day], day };
}

/** 7 槽 LRU：记录最近 7 条 day 编号，避免重复 */
class TipLRU {
  private order: number[] = [];
  private readonly limit: number = 7;

  has(day: number): boolean { return this.order.indexOf(day) >= 0; }

  push(day: number): void {
    const i = this.order.indexOf(day);
    if (i >= 0) this.order.splice(i, 1);
    this.order.push(day);
    if (this.order.length > this.limit) this.order.shift();
  }

  full(): boolean { return this.order.length >= this.limit; }

  reset(): void { this.order = []; }
}

async function fetchTip(): Promise<AiTipCardData> {
  try {
    return await WidgetApi.getAiTip();
  } catch (_e) {
    return fallbackTip();
  }
}

export default class AiTipExtensionAbility extends FormExtensionAbility {
  private readonly lru: TipLRU = new TipLRU();
  private liveFormIds: Set<string> = new Set<string>();

  onAddForm(_want: object): formBindingData.FormBindingData {
    const placeholder = fallbackTip();
    this.lru.push(placeholder.day);
    setTimeout(() => {
      const formId = (_want as Record<string, string>)['ohos.extra.param.key.form_identity'];
      if (formId) {
        this.liveFormIds.add(formId);
        this.pushUpdate(formId);
      }
    }, 0);
    return formBindingData.createFormBindingData(placeholder);
  }

  onCastToNormalForm(_formId: string): void {}

  onUpdateForm(formId: string): void {
    this.liveFormIds.add(formId);
    this.pushUpdate(formId);
  }

  onChangeFormVisibility(_newStatus: Record<string, number>): void {}

  /**
   * Form 内按钮事件：
   *  - 'refresh' / 'next'：换一条贴士
   *  - 'ask'：deeplink 由 wantAgent 处理，这里仅记录
   */
  onFormEvent(formId: string, message: string): void {
    let action = '';
    try {
      const obj = JSON.parse(message) as Record<string, string>;
      action = obj['action'] ?? '';
    } catch (_e) { /* swallow */ }
    if (action === 'refresh' || action === 'next') {
      this.pushUpdate(formId, true);
    }
  }

  onRemoveForm(formId: string): void {
    this.liveFormIds.delete(formId);
  }

  onAcquireFormState(_want: object): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  // ---------- internals ----------

  private async pushUpdate(formId: string, forceNew: boolean = false): Promise<void> {
    let data = await fetchTip();
    // 若本日已展示过且用户要求换新，则尝试用 fallback 池里没用过的
    if (forceNew && this.lru.has(data.day) && !this.lru.full()) {
      for (let i = 0; i < FALLBACK_TIPS.length; i++) {
        if (!this.lru.has(i)) {
          data = { tip: FALLBACK_TIPS[i], day: i };
          break;
        }
      }
    }
    if (this.lru.full() && forceNew) this.lru.reset();
    this.lru.push(data.day);
    try {
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (err) {
      console.error(`ai-tip updateForm err: ${(err as Error).message}`);
    }
  }
}
