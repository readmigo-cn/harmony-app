import { StoreKeys } from './StoreKeys';
import { PreferencesManager } from '../core/persistence/PreferencesManager';

export type AppLocale = 'zh-CN' | 'zh-TW' | 'en-US' | 'en';
export type AppThemeMode = 'system' | 'light' | 'dark';
export type ReaderTheme = 'day' | 'night' | 'paper' | 'sepia' | 'system';
/** 翻页方式：paged=卷页快照动画 / scroll=上下滚动 / horizontal=平滑横向滑动 */
export type PageTurnMode = 'paged' | 'scroll' | 'horizontal';
/** 阅读器字体：sans=HarmonyOS Sans / serif=阅读字体 / system=系统字体 */
export type ReaderFont = 'sans' | 'serif' | 'system';
/** 字号档位：1=极小 / 2=小 / 3=中 / 4=大 / 5=极大 */
export type FontSizeLevel = 1 | 2 | 3 | 4 | 5;
/** 行距档位：1=紧凑 / 2=标准 / 3=宽松 */
export type LineHeightLevel = 1 | 2 | 3;

export interface NotificationSettings {
  dailyReminder: boolean;
  time: string; // 'HH:mm'
}

export interface TtsSettings {
  voice: string;
  speed: number; // 0.5 - 2.0
}

/** W8-C5：TTS provider 选择（持久化用，运行时由 TtsService 持有） */
export type TtsProvider = 'huawei-system' | 'xunfei' | 'aliyun';

const FONT_SIZE_MIN = 14;
const FONT_SIZE_MAX = 24;
const LINE_HEIGHT_MIN = 1.4;
const LINE_HEIGHT_MAX = 2.0;

/**
 * 字号档位 → 实际 sp 字号映射。
 * 与 ReaderSettingsSheet 视觉档位严格对齐：14 / 16 / 18 / 20 / 24。
 */
export const FONT_SIZE_LEVEL_MAP: Record<FontSizeLevel, number> = {
  1: 14,
  2: 16,
  3: 18,
  4: 20,
  5: 24,
};

/** 行距档位 → 实际行高倍数：紧凑 1.4 / 标准 1.6 / 宽松 1.8。 */
export const LINE_HEIGHT_LEVEL_MAP: Record<LineHeightLevel, number> = {
  1: 1.4,
  2: 1.6,
  3: 1.8,
};

/**
 * SettingsStore：阅读/通知/TTS/主题/语言。
 *
 * 持久化策略：所有字段以字符串形式存 PreferencesManager；数值用 toString()/parseFloat。
 * AppStorage 持运行时类型（number/boolean/object），UI 直接读。
 */
export class SettingsStore {
  static async init(): Promise<void> {
    const locale = (await PreferencesManager.getString(StoreKeys.SETTINGS_LOCALE, 'zh-CN')) as AppLocale;
    const theme = (await PreferencesManager.getString(StoreKeys.SETTINGS_THEME, 'system')) as AppThemeMode;
    const fontSize = await PreferencesManager.getString(StoreKeys.SETTINGS_READER_FONT_SIZE, '17');
    const readerTheme = (await PreferencesManager.getString(StoreKeys.SETTINGS_READER_THEME, 'day')) as ReaderTheme;
    const lineHeight = await PreferencesManager.getString(StoreKeys.SETTINGS_READER_LINE_HEIGHT, '1.6');
    const fontSizeLevelStr = await PreferencesManager.getString(StoreKeys.SETTINGS_READER_FONT_SIZE_LEVEL, '3');
    const lineHeightLevelStr = await PreferencesManager.getString(StoreKeys.SETTINGS_READER_LINE_HEIGHT_LEVEL, '2');
    const pageTurnMode = (await PreferencesManager.getString(StoreKeys.SETTINGS_READER_PAGE_TURN_MODE, 'paged')) as PageTurnMode;
    const readerFont = (await PreferencesManager.getString(StoreKeys.SETTINGS_READER_FONT, 'sans')) as ReaderFont;
    const dailyReminder = await PreferencesManager.getBool(StoreKeys.SETTINGS_NOTIFICATIONS_DAILY, false);
    const reminderTime = await PreferencesManager.getString(StoreKeys.SETTINGS_NOTIFICATIONS_TIME, '20:00');
    const ttsVoice = await PreferencesManager.getString(StoreKeys.SETTINGS_TTS_VOICE, 'default');
    const ttsSpeed = await PreferencesManager.getString(StoreKeys.SETTINGS_TTS_SPEED, '1.0');
    // W8-C5：TTS provider 持久化
    const ttsProvider = await PreferencesManager.getString('settings_tts_provider', 'huawei-system');
    AppStorage.SetOrCreate<string>('settings_tts_provider', ttsProvider);

    AppStorage.SetOrCreate<AppLocale>(StoreKeys.SETTINGS_LOCALE, locale);
    AppStorage.SetOrCreate<AppThemeMode>(StoreKeys.SETTINGS_THEME, theme);
    AppStorage.SetOrCreate<number>(
      StoreKeys.SETTINGS_READER_FONT_SIZE,
      SettingsStore.clampInt(parseInt(fontSize, 10), FONT_SIZE_MIN, FONT_SIZE_MAX, 17),
    );
    AppStorage.SetOrCreate<ReaderTheme>(StoreKeys.SETTINGS_READER_THEME, readerTheme);
    AppStorage.SetOrCreate<number>(
      StoreKeys.SETTINGS_READER_LINE_HEIGHT,
      SettingsStore.clampFloat(parseFloat(lineHeight), LINE_HEIGHT_MIN, LINE_HEIGHT_MAX, 1.6),
    );
    AppStorage.SetOrCreate<FontSizeLevel>(
      StoreKeys.SETTINGS_READER_FONT_SIZE_LEVEL,
      SettingsStore.normalizeFontSizeLevel(parseInt(fontSizeLevelStr, 10)),
    );
    AppStorage.SetOrCreate<LineHeightLevel>(
      StoreKeys.SETTINGS_READER_LINE_HEIGHT_LEVEL,
      SettingsStore.normalizeLineHeightLevel(parseInt(lineHeightLevelStr, 10)),
    );
    AppStorage.SetOrCreate<PageTurnMode>(
      StoreKeys.SETTINGS_READER_PAGE_TURN_MODE,
      SettingsStore.normalizePageTurnMode(pageTurnMode),
    );
    AppStorage.SetOrCreate<ReaderFont>(
      StoreKeys.SETTINGS_READER_FONT,
      SettingsStore.normalizeReaderFont(readerFont),
    );
    AppStorage.SetOrCreate<NotificationSettings>(
      StoreKeys.SETTINGS_NOTIFICATIONS_DAILY,
      { dailyReminder, time: reminderTime },
    );
    AppStorage.SetOrCreate<TtsSettings>(StoreKeys.SETTINGS_TTS_VOICE, {
      voice: ttsVoice,
      speed: parseFloat(ttsSpeed) || 1.0,
    });
  }

  // ---- Locale ----
  static getLocale(): AppLocale {
    return AppStorage.Get<AppLocale>(StoreKeys.SETTINGS_LOCALE) ?? 'zh-CN';
  }

  static setLocale(v: AppLocale): void {
    AppStorage.SetOrCreate<AppLocale>(StoreKeys.SETTINGS_LOCALE, v);
    PreferencesManager.setString(StoreKeys.SETTINGS_LOCALE, v);
  }

  // ---- App Theme Mode ----
  static getThemeMode(): AppThemeMode {
    return AppStorage.Get<AppThemeMode>(StoreKeys.SETTINGS_THEME) ?? 'system';
  }

  static setThemeMode(v: AppThemeMode): void {
    AppStorage.SetOrCreate<AppThemeMode>(StoreKeys.SETTINGS_THEME, v);
    PreferencesManager.setString(StoreKeys.SETTINGS_THEME, v);
  }

  // ---- Reader Font Size ----
  static getReaderFontSize(): number {
    return AppStorage.Get<number>(StoreKeys.SETTINGS_READER_FONT_SIZE) ?? 17;
  }

  static setReaderFontSize(v: number): void {
    const clamped = SettingsStore.clampInt(v, FONT_SIZE_MIN, FONT_SIZE_MAX, 17);
    AppStorage.SetOrCreate<number>(StoreKeys.SETTINGS_READER_FONT_SIZE, clamped);
    PreferencesManager.setString(StoreKeys.SETTINGS_READER_FONT_SIZE, clamped.toString());
  }

  // ---- Reader Theme ----
  static getReaderTheme(): ReaderTheme {
    return AppStorage.Get<ReaderTheme>(StoreKeys.SETTINGS_READER_THEME) ?? 'day';
  }

  static setReaderTheme(v: ReaderTheme): void {
    AppStorage.SetOrCreate<ReaderTheme>(StoreKeys.SETTINGS_READER_THEME, v);
    PreferencesManager.setString(StoreKeys.SETTINGS_READER_THEME, v);
  }

  // ---- Reader Line Height ----
  static getReaderLineHeight(): number {
    return AppStorage.Get<number>(StoreKeys.SETTINGS_READER_LINE_HEIGHT) ?? 1.6;
  }

  static setReaderLineHeight(v: number): void {
    const clamped = SettingsStore.clampFloat(v, LINE_HEIGHT_MIN, LINE_HEIGHT_MAX, 1.6);
    AppStorage.SetOrCreate<number>(StoreKeys.SETTINGS_READER_LINE_HEIGHT, clamped);
    PreferencesManager.setString(StoreKeys.SETTINGS_READER_LINE_HEIGHT, clamped.toString());
  }

  // ---- Reader Font Size Level（W7-C1：5 档预设） ----
  static getReaderFontSizeLevel(): FontSizeLevel {
    return AppStorage.Get<FontSizeLevel>(StoreKeys.SETTINGS_READER_FONT_SIZE_LEVEL) ?? 3;
  }

  static setReaderFontSizeLevel(level: FontSizeLevel): void {
    const normalized = SettingsStore.normalizeFontSizeLevel(level);
    AppStorage.SetOrCreate<FontSizeLevel>(StoreKeys.SETTINGS_READER_FONT_SIZE_LEVEL, normalized);
    PreferencesManager.setString(StoreKeys.SETTINGS_READER_FONT_SIZE_LEVEL, normalized.toString());
    // 同步对应的实际字号，保持与字号档位一致
    SettingsStore.setReaderFontSize(FONT_SIZE_LEVEL_MAP[normalized]);
  }

  // ---- Reader Line Height Level（W7-C2：3 档预设） ----
  static getReaderLineHeightLevel(): LineHeightLevel {
    return AppStorage.Get<LineHeightLevel>(StoreKeys.SETTINGS_READER_LINE_HEIGHT_LEVEL) ?? 2;
  }

  static setReaderLineHeightLevel(level: LineHeightLevel): void {
    const normalized = SettingsStore.normalizeLineHeightLevel(level);
    AppStorage.SetOrCreate<LineHeightLevel>(StoreKeys.SETTINGS_READER_LINE_HEIGHT_LEVEL, normalized);
    PreferencesManager.setString(StoreKeys.SETTINGS_READER_LINE_HEIGHT_LEVEL, normalized.toString());
    // 同步实际行高倍数
    SettingsStore.setReaderLineHeight(LINE_HEIGHT_LEVEL_MAP[normalized]);
  }

  // ---- Reader Page Turn Mode（W7-C4） ----
  static getReaderPageTurnMode(): PageTurnMode {
    return AppStorage.Get<PageTurnMode>(StoreKeys.SETTINGS_READER_PAGE_TURN_MODE) ?? 'paged';
  }

  static setReaderPageTurnMode(mode: PageTurnMode): void {
    const normalized = SettingsStore.normalizePageTurnMode(mode);
    AppStorage.SetOrCreate<PageTurnMode>(StoreKeys.SETTINGS_READER_PAGE_TURN_MODE, normalized);
    PreferencesManager.setString(StoreKeys.SETTINGS_READER_PAGE_TURN_MODE, normalized);
  }

  // ---- Reader Font（W7-C：字体选择） ----
  static getReaderFont(): ReaderFont {
    return AppStorage.Get<ReaderFont>(StoreKeys.SETTINGS_READER_FONT) ?? 'sans';
  }

  static setReaderFont(font: ReaderFont): void {
    const normalized = SettingsStore.normalizeReaderFont(font);
    AppStorage.SetOrCreate<ReaderFont>(StoreKeys.SETTINGS_READER_FONT, normalized);
    PreferencesManager.setString(StoreKeys.SETTINGS_READER_FONT, normalized);
  }

  // ---- Notifications ----
  static getNotifications(): NotificationSettings {
    return (
      AppStorage.Get<NotificationSettings>(StoreKeys.SETTINGS_NOTIFICATIONS_DAILY) ?? {
        dailyReminder: false,
        time: '20:00',
      }
    );
  }

  static setNotifications(v: NotificationSettings): void {
    AppStorage.SetOrCreate<NotificationSettings>(StoreKeys.SETTINGS_NOTIFICATIONS_DAILY, v);
    PreferencesManager.setBool(StoreKeys.SETTINGS_NOTIFICATIONS_DAILY, v.dailyReminder);
    PreferencesManager.setString(StoreKeys.SETTINGS_NOTIFICATIONS_TIME, v.time);
  }

  // ---- TTS ----
  static getTts(): TtsSettings {
    return (
      AppStorage.Get<TtsSettings>(StoreKeys.SETTINGS_TTS_VOICE) ?? {
        voice: 'default',
        speed: 1.0,
      }
    );
  }

  static setTts(v: TtsSettings): void {
    AppStorage.SetOrCreate<TtsSettings>(StoreKeys.SETTINGS_TTS_VOICE, v);
    PreferencesManager.setString(StoreKeys.SETTINGS_TTS_VOICE, v.voice);
    PreferencesManager.setString(StoreKeys.SETTINGS_TTS_SPEED, v.speed.toString());
  }

  // ---- TTS Voice / Speed / Provider 单字段访问（W8-C5） ----
  static getTtsVoice(): string {
    return SettingsStore.getTts().voice;
  }

  static setTtsVoice(voice: string): void {
    const cur = SettingsStore.getTts();
    SettingsStore.setTts({ voice, speed: cur.speed });
  }

  static getTtsSpeed(): number {
    return SettingsStore.getTts().speed;
  }

  static setTtsSpeed(speed: number): void {
    const cur = SettingsStore.getTts();
    SettingsStore.setTts({ voice: cur.voice, speed });
  }

  static getTtsProvider(): TtsProvider {
    const v = AppStorage.Get<string>('settings_tts_provider');
    if (v === 'huawei-system' || v === 'xunfei' || v === 'aliyun') return v;
    return 'huawei-system';
  }

  static setTtsProvider(provider: TtsProvider): void {
    AppStorage.SetOrCreate<string>('settings_tts_provider', provider);
    PreferencesManager.setString('settings_tts_provider', provider);
  }

  private static normalizeFontSizeLevel(v: number): FontSizeLevel {
    if (v === 1 || v === 2 || v === 3 || v === 4 || v === 5) return v as FontSizeLevel;
    return 3;
  }

  private static normalizeLineHeightLevel(v: number): LineHeightLevel {
    if (v === 1 || v === 2 || v === 3) return v as LineHeightLevel;
    return 2;
  }

  private static normalizePageTurnMode(v: string): PageTurnMode {
    if (v === 'paged' || v === 'scroll' || v === 'horizontal') return v;
    return 'paged';
  }

  private static normalizeReaderFont(v: string): ReaderFont {
    if (v === 'sans' || v === 'serif' || v === 'system') return v;
    return 'sans';
  }

  private static clampInt(v: number, min: number, max: number, def: number): number {
    if (Number.isNaN(v) || !Number.isFinite(v)) return def;
    if (v < min) return min;
    if (v > max) return max;
    return Math.round(v);
  }

  private static clampFloat(v: number, min: number, max: number, def: number): number {
    if (Number.isNaN(v) || !Number.isFinite(v)) return def;
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }
}
