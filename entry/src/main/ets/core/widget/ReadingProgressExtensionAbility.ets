import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import formInfo from '@ohos.app.form.formInfo';
import formProvider from '@ohos.app.form.formProvider';
import formBindingData from '@ohos.app.form.formBindingData';
import commonEventManager from '@ohos.commonEventManager';
import { WidgetApi, ReadingProgressCardData } from '../../api/widget/WidgetApi';

/**
 * 我的阅读 FormExtensionAbility（W12-C2）。
 *
 * 与 DailyWordExtensionAbility 平行结构。数据通过 WidgetApi 拉 /widget/reading-progress；
 * 失败时返回空状态（卡片 UI 自行渲染「去阅读」CTA）。
 *
 * 更新策略：
 *  - 系统定时：form_config.json 里 updateDuration=2（每 30 分钟刷一次，半小时粒度）
 *  - 主 App 翻页：发送 commonEvent "com.readmigo.reading.progress_updated" → widget 立即拉新
 *  - 用户点击：deeplink 跳到 Reader，由 wantAgent 处理（onFormEvent）
 *
 * FormDataStore 注册：与 W12-C1 共用 PreferencesManager namespace 'widget'，
 * 持久化最近一次成功的数据，offline / 首屏使用。
 */

const KEY_LAST_DATA = 'reading_progress_last';
const EVENT_PROGRESS_UPDATED = 'com.readmigo.reading.progress_updated';

function emptyData(): ReadingProgressCardData {
  return {
    bookId: null,
    percentComplete: 0,
    currentChapterIndex: 0,
    totalReadMinutes: 0,
    lastReadAt: null,
  };
}

async function fetchData(): Promise<ReadingProgressCardData> {
  try {
    return await WidgetApi.getReadingProgress();
  } catch (_e) {
    return emptyData();
  }
}

export default class ReadingProgressExtensionAbility extends FormExtensionAbility {
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;
  private liveFormIds: Set<string> = new Set<string>();

  onAddForm(_want: object): formBindingData.FormBindingData {
    // 同步先返回占位 + 异步拉数据更新
    const placeholder = emptyData();
    // 注：onAddForm 必须同步返回，真实数据由 onUpdateForm 异步推送
    setTimeout(() => {
      const formId = (_want as Record<string, string>)['ohos.extra.param.key.form_identity'];
      if (formId) {
        this.liveFormIds.add(formId);
        this.pushUpdate(formId);
      }
    }, 0);
    this.ensureSubscribed();
    return formBindingData.createFormBindingData(placeholder);
  }

  onCastToNormalForm(_formId: string): void {}

  onUpdateForm(formId: string): void {
    this.liveFormIds.add(formId);
    this.pushUpdate(formId);
  }

  onChangeFormVisibility(_newStatus: Record<string, number>): void {}

  onFormEvent(formId: string, _message: string): void {
    // 用户点击「继续阅读」按钮时主 App 通过 router 处理，这里只刷新一次数据
    this.pushUpdate(formId);
  }

  onRemoveForm(formId: string): void {
    this.liveFormIds.delete(formId);
    if (this.liveFormIds.size === 0 && this.subscriber) {
      try {
        commonEventManager.unsubscribe(this.subscriber);
      } catch (_e) { /* swallow */ }
      this.subscriber = null;
    }
  }

  onAcquireFormState(_want: object): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  // ---------- internals ----------

  private async pushUpdate(formId: string): Promise<void> {
    const data = await fetchData();
    try {
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (err) {
      console.error(`reading-progress updateForm err: ${(err as Error).message}`);
    }
  }

  private ensureSubscribed(): void {
    if (this.subscriber) return;
    const info: commonEventManager.CommonEventSubscribeInfo = {
      events: [EVENT_PROGRESS_UPDATED],
    };
    commonEventManager.createSubscriber(info, (err, sub) => {
      if (err || !sub) return;
      this.subscriber = sub;
      commonEventManager.subscribe(sub, (_e, _data) => {
        this.liveFormIds.forEach((id) => this.pushUpdate(id));
      });
    });
  }
}
