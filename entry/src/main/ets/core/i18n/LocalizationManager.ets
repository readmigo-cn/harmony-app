import i18n from '@ohos.i18n';
import { PreferencesManager } from '../persistence/PreferencesManager';

const LANG_KEY = 'app_language_v1';
const DEFAULT_LANG: SupportedLang = 'zh-CN';

export type SupportedLang =
  | 'zh-CN' | 'zh-TW' | 'en-US'
  | 'ja-JP' | 'ko-KR' | 'es-ES' | 'fr-FR' | 'de-DE'
  | 'pt-BR' | 'ru-RU' | 'ar-SA' | 'hi-IN' | 'vi-VN'
  | 'th-TH' | 'id-ID' | 'it-IT';

/** 与 iOS String Catalog 对齐的 16 个核心语种（iOS 总数 29，CN 端先覆盖最常用 16 个）。 */
export const SUPPORTED_LANGS: SupportedLang[] = [
  'zh-CN', 'zh-TW', 'en-US',
  'ja-JP', 'ko-KR', 'es-ES', 'fr-FR', 'de-DE',
  'pt-BR', 'ru-RU', 'ar-SA', 'hi-IN', 'vi-VN',
  'th-TH', 'id-ID', 'it-IT',
];

export type LangChangeListener = (lang: SupportedLang) => void;

/**
 * 应用语种管理：
 * - 持久化用户偏好（PreferencesManager 中 key='app_language_v1'）
 * - 启动时按 [stored > system > 'zh-CN'] 优先级解析
 * - 提供 Accept-Language header 给 HttpClient
 * - 提供 onChange 订阅给 UI 刷新
 *
 * 用法：
 *   await LocalizationManager.init();
 *   const lang = LocalizationManager.getCurrentLang();
 *   const header = LocalizationManager.getAcceptLanguageHeader();
 *   await LocalizationManager.setLang('ja-JP');
 *   const unsub = LocalizationManager.onChange((l) => refreshUI(l));
 */
export class LocalizationManager {
  private static current: SupportedLang = DEFAULT_LANG;
  private static initialized: boolean = false;
  private static listeners: Set<LangChangeListener> = new Set<LangChangeListener>();

  static async init(): Promise<void> {
    if (LocalizationManager.initialized) return;
    const stored = await PreferencesManager.getString(LANG_KEY, '');
    if (stored && SUPPORTED_LANGS.indexOf(stored as SupportedLang) >= 0) {
      LocalizationManager.current = stored as SupportedLang;
    } else {
      LocalizationManager.current = LocalizationManager.detectSystemLang();
    }
    LocalizationManager.applyToSystem();
    LocalizationManager.initialized = true;
  }

  static getCurrentLang(): SupportedLang {
    return LocalizationManager.current;
  }

  static isSupported(lang: string): lang is SupportedLang {
    return SUPPORTED_LANGS.indexOf(lang as SupportedLang) >= 0;
  }

  /**
   * 生成 RFC-7231 Accept-Language header。
   * 当前语种 q=1.0；同主语种 fallback q=0.9；英语兜底 q=0.8。
   * 例：'ja-JP,ja;q=0.9,en;q=0.8'。
   */
  static getAcceptLanguageHeader(): string {
    const cur = LocalizationManager.current;
    const primary = cur.split('-')[0];
    if (cur === 'en-US') return 'en-US,en;q=0.9';
    return `${cur},${primary};q=0.9,en;q=0.8`;
  }

  static async setLang(lang: SupportedLang): Promise<void> {
    if (lang === LocalizationManager.current) return;
    LocalizationManager.current = lang;
    await PreferencesManager.setString(LANG_KEY, lang);
    LocalizationManager.applyToSystem();
    LocalizationManager.notifyListeners();
  }

  static onChange(cb: LangChangeListener): () => void {
    LocalizationManager.listeners.add(cb);
    return () => { LocalizationManager.listeners.delete(cb); };
  }

  // ---------- internals ----------

  private static notifyListeners(): void {
    LocalizationManager.listeners.forEach((cb) => {
      try { cb(LocalizationManager.current); } catch (_e) { /* swallow */ }
    });
  }

  private static detectSystemLang(): SupportedLang {
    try {
      const sysLocale = i18n.System.getSystemLocale();
      const normalized = LocalizationManager.normalizeLocale(sysLocale);
      if (SUPPORTED_LANGS.indexOf(normalized as SupportedLang) >= 0) {
        return normalized as SupportedLang;
      }
      const primary = normalized.split('-')[0];
      const fallback = SUPPORTED_LANGS.find((l) => l.startsWith(primary + '-'));
      return fallback ?? DEFAULT_LANG;
    } catch (_e) {
      return DEFAULT_LANG;
    }
  }

  /** 规范化：'en_US' → 'en-US'；'zh_Hans_CN' → 'zh-CN'；'zh_Hant_TW' → 'zh-TW'。 */
  private static normalizeLocale(raw: string): string {
    let s = raw.replace(/_/g, '-');
    s = s.replace(/-(Hans|Hant)/i, '');
    return s;
  }

  private static applyToSystem(): void {
    try {
      i18n.System.setAppPreferredLanguage(LocalizationManager.current);
    } catch (_e) {
      // 老版本 SDK 可能不支持，资源加载仍按 device locale 走，忽略。
    }
  }
}
