import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import common from '@ohos.app.ability.common';
import { SettingsStore } from '../../store/SettingsStore';
import { StoreKeys } from '../../store/StoreKeys';
import {
  ThemeMode,
  EffectiveTheme,
  ThemeContext,
  ThemeChangeListener,
} from './Theme.types';

const TAG = 'ThemeService';
const APP_STORAGE_KEY = 'app_theme_mode';

/**
 * ThemeService（W5-C4）：
 *
 * 职责：
 *   1) 读取系统 colorMode（@ohos.app.ability.ConfigurationConstant）
 *   2) 读取 SettingsStore.getReaderTheme() 用户偏好
 *   3) 计算 effectiveTheme（'system' -> 解析为 day/night）
 *   4) 通过 AppStorage.SetOrCreate('app_theme_mode', effectiveTheme) 发布
 *   5) 维护 listener 列表，主动通知组件
 *
 * 系统主题变化通知机制：
 *   - 进程内：EntryAbility.onConfigurationUpdated 调用 onSystemColorModeChange()
 *   - HarmonyOS NEXT 没有像 iOS 那样的 trait change 通知，
 *     必须在 Ability 层捕获 Configuration 更新事件再转发。
 */
export class ThemeService {
  private static initialized: boolean = false;
  private static systemDark: boolean = false;
  private static listeners: Set<ThemeChangeListener> = new Set();
  private static lastEffective: EffectiveTheme = 'day';

  /**
   * 启动期初始化。EntryAbility.onCreate 调用，必须在 SettingsStore.init 之后。
   */
  static init(context: common.UIAbilityContext): void {
    try {
      const config = context.config;
      const colorMode = config?.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      ThemeService.systemDark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;

      const effective = ThemeService.computeEffective();
      ThemeService.lastEffective = effective;
      AppStorage.SetOrCreate<EffectiveTheme>(APP_STORAGE_KEY, effective);

      ThemeService.initialized = true;
      console.info(`${TAG} init: systemDark=${ThemeService.systemDark} effective=${effective}`);
    } catch (err) {
      const e = err as Error;
      console.error(`${TAG} init failed: ${e.message}`);
      // 容错：保持默认 day 主题，不影响 app 启动
      AppStorage.SetOrCreate<EffectiveTheme>(APP_STORAGE_KEY, 'day');
      ThemeService.lastEffective = 'day';
    }
  }

  /**
   * 由 EntryAbility.onConfigurationUpdated 调用。
   * HarmonyOS 在系统暗色模式切换时触发 onConfigurationUpdated 回调。
   */
  static onSystemColorModeChange(colorMode: number): void {
    const isDark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    if (isDark === ThemeService.systemDark) return;
    ThemeService.systemDark = isDark;
    ThemeService.recompute();
  }

  /**
   * 用户在设置里选择主题。写回 SettingsStore，同时触发重算。
   */
  static setUserTheme(theme: ThemeMode): void {
    // SettingsStore 用 ReaderTheme 类型，'day'/'night'/'sepia'/'system' 都在内
    SettingsStore.setReaderTheme(theme);
    ThemeService.recompute();
  }

  static getCurrentTheme(): EffectiveTheme {
    return ThemeService.lastEffective;
  }

  static isDarkMode(): boolean {
    return ThemeService.lastEffective === 'night';
  }

  static getContext(): ThemeContext {
    const userPref = ThemeService.readUserPreference();
    return {
      effective: ThemeService.lastEffective,
      userPreference: userPref,
      systemDark: ThemeService.systemDark,
    };
  }

  /**
   * 命令式订阅。返回 unsubscribe 函数。
   * 用于不便用 @StorageProp 的非 @Component 场景。
   */
  static subscribe(callback: ThemeChangeListener): () => void {
    ThemeService.listeners.add(callback);
    // 立即推一次当前值，方便订阅者初始化
    try {
      callback(ThemeService.lastEffective);
    } catch (err) {
      console.warn(`${TAG} subscribe initial callback threw`);
    }
    return () => {
      ThemeService.listeners.delete(callback);
    };
  }

  // ---- internal ----

  private static readUserPreference(): ThemeMode {
    if (!ThemeService.initialized) {
      // 初始化前 SettingsStore 也未必就绪
      return 'system';
    }
    const raw = SettingsStore.getReaderTheme();
    // ReaderTheme 比 ThemeMode 多一个 'paper'，归一为 sepia
    if (raw === 'paper') return 'sepia';
    if (raw === 'day' || raw === 'night' || raw === 'sepia' || raw === 'system') {
      return raw;
    }
    return 'system';
  }

  private static computeEffective(): EffectiveTheme {
    const pref = ThemeService.readUserPreference();
    if (pref === 'system') {
      return ThemeService.systemDark ? 'night' : 'day';
    }
    return pref;
  }

  private static recompute(): void {
    const next = ThemeService.computeEffective();
    if (next === ThemeService.lastEffective) return;
    ThemeService.lastEffective = next;
    AppStorage.SetOrCreate<EffectiveTheme>(APP_STORAGE_KEY, next);
    ThemeService.notifyListeners(next);
  }

  private static notifyListeners(theme: EffectiveTheme): void {
    ThemeService.listeners.forEach((cb) => {
      try {
        cb(theme);
      } catch (err) {
        const e = err as Error;
        console.warn(`${TAG} listener threw: ${e.message}`);
      }
    });
  }
}

export const APP_THEME_STORAGE_KEY = APP_STORAGE_KEY;
