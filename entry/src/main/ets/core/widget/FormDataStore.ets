import { PreferencesManager, NamespacedPreferences } from '../persistence/PreferencesManager';
import formProvider from '@ohos.app.form.formProvider';
import formBindingData from '@ohos.app.form.formBindingData';

/**
 * Form data update framework (W12-C5)
 *
 * 通用 Form（卡片）数据更新框架。负责：
 * - formId → kind 持久化映射（重启后恢复）
 * - 按 formId 触发 update（onUpdateForm 调用）
 * - 按 kind 批量 update（如 commonEvent 收到登录后，刷新所有 daily-word 卡片）
 * - 注册每日定时（reminderAgent placeholder）
 *
 * 使用：
 *   FormDataStore.shared().subscribeForm(formId, 'daily-word', async () => fetchDailyWord())
 *   FormDataStore.shared().requestUpdate(formId)
 *   FormDataStore.shared().requestUpdateByKind('daily-word')
 *   FormDataStore.shared().scheduleDaily(8, async () => { ... })
 */

export type FormKind = 'daily-word' | 'reading-progress' | 'ai-tip';

/** 单卡片更新逻辑：返回新的 binding payload。 */
export type FormUpdateFn = () => Promise<Record<string, string | number | boolean>>;

interface FormEntry {
  formId: string;
  kind: FormKind;
  updateFn: FormUpdateFn;
}

/** 持久化结构：仅存 formId → kind，updateFn 在卡片重启后由 ExtensionAbility 重新注册。 */
interface FormMappingRecord {
  formId: string;
  kind: FormKind;
  registeredAt: number;
}

const NS = 'widget';
const KEY_MAPPINGS = 'form_mappings';

export class FormDataStore {
  private static instance: FormDataStore | null = null;
  private entries: Map<string, FormEntry> = new Map<string, FormEntry>();
  private kindIndex: Map<FormKind, Set<string>> = new Map<FormKind, Set<string>>();
  private dailyTimers: Map<number, number> = new Map<number, number>();
  private prefs: NamespacedPreferences | null = null;

  static shared(): FormDataStore {
    if (FormDataStore.instance === null) {
      FormDataStore.instance = new FormDataStore();
    }
    return FormDataStore.instance;
  }

  /** ExtensionAbility onCreate 时调用。从持久层恢复 formId → kind 映射。 */
  async init(): Promise<void> {
    this.prefs = PreferencesManager.createNamespace(NS);
    const records = await this.prefs.getArray<FormMappingRecord>(KEY_MAPPINGS, []);
    for (const r of records) {
      this.indexKind(r.formId, r.kind);
    }
  }

  /** 注册一张卡片的更新逻辑。 */
  async subscribeForm(formId: string, kind: FormKind, updateFn: FormUpdateFn): Promise<void> {
    this.entries.set(formId, { formId, kind, updateFn });
    this.indexKind(formId, kind);
    await this.persist();
  }

  /** 卡片被移除（onRemoveForm）。 */
  async unsubscribeForm(formId: string): Promise<void> {
    const entry = this.entries.get(formId);
    if (entry) {
      const set = this.kindIndex.get(entry.kind);
      if (set) {
        set.delete(formId);
        if (set.size === 0) this.kindIndex.delete(entry.kind);
      }
    }
    this.entries.delete(formId);
    await this.persist();
  }

  /** 主动触发某张卡片更新（调用方一般是 onUpdateForm / 用户手动刷新事件）。 */
  async requestUpdate(formId: string): Promise<void> {
    const entry = this.entries.get(formId);
    if (!entry) return;
    try {
      const payload = await entry.updateFn();
      const binding = formBindingData.createFormBindingData(payload);
      await formProvider.updateForm(formId, binding);
    } catch (e) {
      const err = e as Error;
      console.error(`[FormDataStore] requestUpdate(${formId}) failed: ${err.message}`);
    }
  }

  /** 按 kind 批量刷新（commonEvent 接收登录 / 数据变更广播时使用）。 */
  async requestUpdateByKind(kind: FormKind): Promise<void> {
    const set = this.kindIndex.get(kind);
    if (!set || set.size === 0) return;
    const ids = Array.from(set);
    for (let i = 0; i < ids.length; i++) {
      await this.requestUpdate(ids[i]);
    }
  }

  /**
   * 注册每日定时（hour 0–23）。当前实现用 setInterval 计算下一次触发，
   * 真机量产应替换为 @ohos.reminderAgentManager 持久 reminder。
   */
  scheduleDaily(hour: number, callback: () => Promise<void>): void {
    if (this.dailyTimers.has(hour)) return;
    const fire = async () => {
      try { await callback(); } catch (e) {
        const err = e as Error;
        console.error(`[FormDataStore] daily callback failed: ${err.message}`);
      }
      // 重新排下一次（24h 之后）
      const next = setTimeout(fire, 24 * 60 * 60 * 1000);
      this.dailyTimers.set(hour, next);
    };

    const now = new Date();
    const target = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, 0, 0, 0);
    if (target.getTime() <= now.getTime()) {
      target.setDate(target.getDate() + 1);
    }
    const delay = target.getTime() - now.getTime();
    const handle = setTimeout(fire, delay);
    this.dailyTimers.set(hour, handle);
  }

  /** 取消所有定时（ExtensionAbility 销毁前调用）。 */
  cancelAllSchedules(): void {
    this.dailyTimers.forEach((h) => clearTimeout(h));
    this.dailyTimers.clear();
  }

  // ---------- internals ----------

  private indexKind(formId: string, kind: FormKind): void {
    let set = this.kindIndex.get(kind);
    if (!set) {
      set = new Set<string>();
      this.kindIndex.set(kind, set);
    }
    set.add(formId);
  }

  private async persist(): Promise<void> {
    if (!this.prefs) return;
    const records: FormMappingRecord[] = [];
    this.entries.forEach((entry) => {
      records.push({ formId: entry.formId, kind: entry.kind, registeredAt: Date.now() });
    });
    await this.prefs.setArray(KEY_MAPPINGS, records);
  }
}
