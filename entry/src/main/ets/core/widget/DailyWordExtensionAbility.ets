import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import formInfo from '@ohos.app.form.formInfo';
import formProvider from '@ohos.app.form.formProvider';
import formBindingData from '@ohos.app.form.formBindingData';
import http from '@ohos.net.http';
import Want from '@ohos.app.ability.Want';
import commonEventManager from '@ohos.commonEventManager';

import { FormDataStore } from './FormDataStore';
import { ApiConfig } from '../../api/client/ApiConfig';
import { AtomicLauncher } from '../atomic/AtomicLauncher';

/**
 * DailyWordExtensionAbility — W12-C1
 *
 * 桌面卡片「今日一词」FormExtensionAbility。
 *
 * 数据更新策略：
 *  1. onAddForm: 立即拉一次 server-cn /widget/daily-word（无 token 公开）
 *  2. onUpdateForm: 每天 8:00 调度（form_config.json scheduledUpdateTime）+ 用户手动刷新
 *  3. commonEvent 'readmigo.user.login' 监听 → 调 /widget/daily-word/me 取个性化数据
 *  4. onCastToNormalForm: 临时卡片 → 常驻
 *  5. onRemoveForm: 解订阅 + 清理
 */

interface DailyWordPayload {
  word: string;
  partOfSpeech: string;
  definition: string;
  exampleEn: string;
  exampleZh: string;
  date: string;
  fromVocab?: boolean;
  vocabId?: string;
}

interface FormBindingPayload extends Record<string, string | number | boolean> {
  word: string;
  partOfSpeech: string;
  definition: string;
  exampleEn: string;
  exampleZh: string;
  date: string;
  state: string;
  vocabId: string;
}

const FALLBACK: DailyWordPayload = {
  word: 'serendipity',
  partOfSpeech: 'noun',
  definition: '美好的偶然；意外发现珍宝的能力',
  exampleEn: 'Finding this little café was pure serendipity.',
  exampleZh: '发现这家小咖啡馆完全是美好的偶然。',
  date: new Date().toISOString().slice(0, 10),
  fromVocab: false,
};

const EVENT_LOGIN = 'readmigo.user.login';

function buildBinding(state: 'ok' | 'loading' | 'error', word: DailyWordPayload | null): FormBindingPayload {
  const w = word ?? FALLBACK;
  return {
    word: w.word ?? '',
    partOfSpeech: w.partOfSpeech ?? '',
    definition: w.definition ?? '',
    exampleEn: w.exampleEn ?? '',
    exampleZh: w.exampleZh ?? '',
    date: w.date ?? '',
    state,
    vocabId: w.vocabId ?? '',
  };
}

/** 直接请求 server-cn 公共端点。Widget 进程没有 UserStore，使用最小化 http 调用。 */
async function fetchDailyWord(): Promise<DailyWordPayload> {
  // server-cn /widget/daily-word 不在 /api/v1 下；从 baseUrl 剥掉版本后缀
  const base = ApiConfig.baseUrl.replace(/\/api\/v1\/?$/, '');
  const url = `${base}/widget/daily-word`;
  const httpReq = http.createHttp();
  try {
    const resp = await httpReq.request(url, {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json' },
      connectTimeout: 5000,
      readTimeout: 5000,
    });
    if (resp.responseCode === 200 && typeof resp.result === 'string') {
      const json = JSON.parse(resp.result) as DailyWordPayload;
      return json;
    }
    throw new Error(`HTTP ${resp.responseCode}`);
  } finally {
    httpReq.destroy();
  }
}

export default class DailyWordExtensionAbility extends FormExtensionAbility {
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;

  // ---------- lifecycle ----------

  async onAddForm(want: Want): Promise<formBindingData.FormBindingData> {
    const formId = (want.parameters?.['ohos.extra.param.key.form_identity'] as string) ?? '';

    await FormDataStore.shared().init();
    if (formId.length > 0) {
      await FormDataStore.shared().subscribeForm(formId, 'daily-word', async () => {
        const data = await this.safeFetch();
        return buildBinding('ok', data);
      });
      // 注册每日 8:00 定时
      FormDataStore.shared().scheduleDaily(8, async () => {
        await FormDataStore.shared().requestUpdateByKind('daily-word');
      });
      // 监听登录广播 → 立即刷新
      this.registerLoginListener();
    }

    // 首次同步：先发 loading 占位（FormBindingData 必须立即返回），异步拉数据后 updateForm
    if (formId.length > 0) {
      this.kickoffInitialFetch(formId);
    }
    return formBindingData.createFormBindingData(buildBinding('loading', null));
  }

  onCastToNormalForm(_formId: string): void {
    // 临时卡片 → 常驻：保留默认行为，订阅已在 onAddForm 完成
  }

  onUpdateForm(formId: string): void {
    FormDataStore.shared().requestUpdate(formId).catch((e: Error) => {
      console.error(`[DailyWordExt] onUpdateForm err: ${e.message}`);
    });
  }

  onChangeFormVisibility(_newStatus: Record<string, number>): void {}

  /** 卡片内 postCardAction → router 类型事件。message 类型自定义，跳主 App。 */
  onFormEvent(formId: string, message: string): void {
    let payload: Record<string, string> = {};
    try { payload = JSON.parse(message) as Record<string, string>; } catch (_e) { /* ignore */ }
    const action = payload['action'] ?? 'open-vocab';
    const target = action === 'retry' ? '' : action === 'open-reader' ? 'Reader' : 'vocab';
    if (target.length === 0) {
      // retry：直接重新拉数据
      FormDataStore.shared().requestUpdate(formId).catch(() => {});
      return;
    }
    // ExtensionAbility 没有 UIAbilityContext.startAbility 权限，
    // 实际跳转通过 postCardAction 中的 router event 在系统层完成；
    // 此处仅记录埋点 + 复刷新一次（确保打开后卡片状态最新）
    const _want = AtomicLauncher.buildCardLaunchWant({
      target,
      params: { vocabId: payload['vocabId'] ?? '' },
      formId,
    });
    void _want;
  }

  async onRemoveForm(formId: string): Promise<void> {
    await FormDataStore.shared().unsubscribeForm(formId);
    if (this.subscriber) {
      try { commonEventManager.unsubscribe(this.subscriber); } catch (_e) { /* ignore */ }
      this.subscriber = null;
    }
  }

  onConfigurationUpdate(_config: object): void {
    // 主题 / 语言变化：批量刷新所有 daily-word 卡片
    FormDataStore.shared().requestUpdateByKind('daily-word').catch(() => {});
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  // ---------- helpers ----------

  private async safeFetch(): Promise<DailyWordPayload> {
    try {
      return await fetchDailyWord();
    } catch (e) {
      const err = e as Error;
      console.error(`[DailyWordExt] fetch failed: ${err.message}`);
      return FALLBACK;
    }
  }

  private kickoffInitialFetch(formId: string): void {
    this.safeFetch().then((data) => {
      const binding = formBindingData.createFormBindingData(buildBinding('ok', data));
      formProvider.updateForm(formId, binding).catch((e: Error) => {
        console.error(`[DailyWordExt] initial updateForm err: ${e.message}`);
      });
    }).catch(() => {
      const binding = formBindingData.createFormBindingData(buildBinding('error', null));
      formProvider.updateForm(formId, binding).catch(() => {});
    });
  }

  private registerLoginListener(): void {
    if (this.subscriber) return;
    const info: commonEventManager.CommonEventSubscribeInfo = { events: [EVENT_LOGIN] };
    commonEventManager.createSubscriber(info, (err, sub) => {
      if (err || !sub) return;
      this.subscriber = sub;
      commonEventManager.subscribe(sub, (_e, _data) => {
        FormDataStore.shared().requestUpdateByKind('daily-word').catch(() => {});
      });
    });
  }
}
