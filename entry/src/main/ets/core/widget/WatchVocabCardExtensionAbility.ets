/**
 * WatchVocabCardExtensionAbility — W15-C2 表盘卡片
 *
 * 与桌面 DailyWordExtensionAbility 不同：
 *   - 表盘卡片尺寸固定 1×1（约 96vp 圆形）
 *   - 视觉极简：只显示一个单词大字 + 短中文释义
 *   - 数据获取：直接调 WidgetApi.getDailyWord()（个性化生词优先）
 *   - 点击：postCardAction(router) → WatchAbility, target=vocab → 跳到 WatchVocab 复习页
 *   - 更新策略：
 *       scheduledUpdateTime 8:00（表盘卡）
 *       formVisibleNotify=true 时主动 refresh
 */

import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import formInfo from '@ohos.app.form.formInfo';
import formProvider from '@ohos.app.form.formProvider';
import formBindingData from '@ohos.app.form.formBindingData';
import http from '@ohos.net.http';
import Want from '@ohos.app.ability.Want';
import { ApiConfig } from '../../api/client/ApiConfig';

interface WatchVocabPayload {
  word: string;
  definition: string;
  vocabId: string;
}

interface WatchVocabBinding extends Record<string, string> {
  word: string;
  definition: string;
  vocabId: string;
  state: string;
}

const FALLBACK: WatchVocabPayload = {
  word: 'serendipity',
  definition: '美好的偶然',
  vocabId: '',
};

const TAG = 'WatchVocabCardExt';

function buildBinding(state: 'ok' | 'loading' | 'error', p: WatchVocabPayload | null): WatchVocabBinding {
  const w = p ?? FALLBACK;
  return {
    word: w.word ?? '',
    definition: w.definition ?? '',
    vocabId: w.vocabId ?? '',
    state,
  };
}

/** 公共 daily-word（无 token 即可，手表 widget 沙盒同 daily-word card） */
async function fetchWatchVocab(): Promise<WatchVocabPayload> {
  const base = ApiConfig.baseUrl.replace(/\/api\/v1\/?$/, '');
  const url = `${base}/widget/daily-word`;
  const httpReq = http.createHttp();
  try {
    const resp = await httpReq.request(url, {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json' },
      connectTimeout: 4000,
      readTimeout: 4000,
    });
    if (resp.responseCode === 200 && typeof resp.result === 'string') {
      const j = JSON.parse(resp.result) as Record<string, string>;
      return {
        word: j.word ?? '',
        definition: j.definition ?? '',
        vocabId: j.vocabId ?? '',
      };
    }
    throw new Error(`HTTP ${resp.responseCode}`);
  } finally {
    httpReq.destroy();
  }
}

export default class WatchVocabCardExtensionAbility extends FormExtensionAbility {

  async onAddForm(want: Want): Promise<formBindingData.FormBindingData> {
    const formId = (want.parameters?.['ohos.extra.param.key.form_identity'] as string) ?? '';
    if (formId.length > 0) {
      this.kickoffFetch(formId);
    }
    return formBindingData.createFormBindingData(buildBinding('loading', null));
  }

  onUpdateForm(formId: string): void {
    this.kickoffFetch(formId);
  }

  onChangeFormVisibility(_newStatus: Record<string, number>): void {}

  onFormEvent(_formId: string, _message: string): void {
    // 卡片点击通过 router action 直接由系统派发 → WatchAbility，无需在此处理
  }

  onRemoveForm(_formId: string): void {
    // 表盘卡片无需订阅清理
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  // ---------- helpers ----------

  private kickoffFetch(formId: string): void {
    fetchWatchVocab().then((data) => {
      const binding = formBindingData.createFormBindingData(buildBinding('ok', data));
      formProvider.updateForm(formId, binding).catch((e: Error) => {
        console.error(`${TAG} updateForm err: ${e.message}`);
      });
    }).catch((e: Error) => {
      console.warn(`${TAG} fetch failed: ${e.message}`);
      const binding = formBindingData.createFormBindingData(buildBinding('error', null));
      formProvider.updateForm(formId, binding).catch(() => {});
    });
  }
}
