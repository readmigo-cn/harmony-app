/**
 * 主题相关类型定义。
 *
 * 与 SettingsStore 的对应关系：
 *   - AppThemeMode (system/light/dark)：影响系统级 UI（导航栏、Tab、卡片）
 *   - ReaderTheme (day/night/sepia/paper/system)：影响阅读器内部
 *
 * W5-C4 ThemeService 暴露的是 "effective reading theme"（day/night/sepia），
 * 即把 'system' 解析后给 UI 使用。
 */

export type ThemeMode = 'day' | 'night' | 'sepia' | 'system';
export type EffectiveTheme = 'day' | 'night' | 'sepia';

/**
 * ColorPair 由 W5-A2 在 AppColors.ets 中定义并导出（{ light, dark }: ResourceColor）。
 * 本文件不再重复定义；如需类型，直接从 AppColors 引入：
 *   import { ColorPair } from './AppColors';
 */

export interface ThemeContext {
  /** 当前生效主题（system 已解析） */
  effective: EffectiveTheme;
  /** 用户在设置里选择的原值 */
  userPreference: ThemeMode;
  /** 系统是否处于深色模式 */
  systemDark: boolean;
}

export type ThemeChangeListener = (theme: EffectiveTheme) => void;
