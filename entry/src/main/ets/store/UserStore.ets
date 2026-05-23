import { StoreKeys } from './StoreKeys';
import { PreferencesManager } from '../core/persistence/PreferencesManager';

export interface UserProfile {
  id: string;
  phone?: string;
  email?: string;
  nickname: string;          // 兼容历史字段
  displayName?: string;
  avatarUrl?: string;
  locale?: string;
  cefr?: string;             // 兼容历史字段
  englishLevel?: string;
  role?: string;
}

/**
 * UserStore 全局用户态。
 * 双层存储：
 *   - AppStorage（运行时，UI 通过 @StorageLink 监听响应式刷新）
 *   - PreferencesManager（持久化，重启 app 后由 init() 回填到 AppStorage）
 *
 * 使用流程：
 *   1) EntryAbility.onCreate 调 PreferencesManager.init -> UserStore.init
 *   2) 业务侧用 setAuth / setProfile / clear，AppStorage 自动同步并异步落盘
 */
export class UserStore {
  /**
   * 从 Preferences 加载所有用户字段到 AppStorage。
   * 仅 EntryAbility.onCreate 调一次。
   */
  static async init(): Promise<void> {
    const token = await PreferencesManager.getString(StoreKeys.USER_TOKEN, '');
    const refresh = await PreferencesManager.getString(StoreKeys.USER_REFRESH_TOKEN, '');
    const id = await PreferencesManager.getString(StoreKeys.USER_ID, '');
    const phone = await PreferencesManager.getString(StoreKeys.USER_PHONE, '');
    const email = await PreferencesManager.getString(StoreKeys.USER_EMAIL, '');
    const displayName = await PreferencesManager.getString(StoreKeys.USER_DISPLAY_NAME, '');
    const avatarUrl = await PreferencesManager.getString(StoreKeys.USER_AVATAR_URL, '');
    const locale = await PreferencesManager.getString(StoreKeys.USER_LOCALE, '');
    const englishLevel = await PreferencesManager.getString(StoreKeys.USER_ENGLISH_LEVEL, '');
    const role = await PreferencesManager.getString(StoreKeys.USER_ROLE, '');

    AppStorage.SetOrCreate<string>(StoreKeys.USER_TOKEN, token);
    AppStorage.SetOrCreate<string>(StoreKeys.USER_REFRESH_TOKEN, refresh);
    AppStorage.SetOrCreate<string>(StoreKeys.USER_ID, id);
    AppStorage.SetOrCreate<string>(StoreKeys.USER_PHONE, phone);
    AppStorage.SetOrCreate<string>(StoreKeys.USER_EMAIL, email);
    AppStorage.SetOrCreate<string>(StoreKeys.USER_DISPLAY_NAME, displayName);
    AppStorage.SetOrCreate<string>(StoreKeys.USER_AVATAR_URL, avatarUrl);
    AppStorage.SetOrCreate<string>(StoreKeys.USER_LOCALE, locale);
    AppStorage.SetOrCreate<string>(StoreKeys.USER_ENGLISH_LEVEL, englishLevel);
    AppStorage.SetOrCreate<string>(StoreKeys.USER_ROLE, role);
    AppStorage.SetOrCreate<boolean>(StoreKeys.USER_LOGGED_IN, token.length > 0);

    if (id.length > 0 || displayName.length > 0) {
      const profile: UserProfile = {
        id,
        phone: phone || undefined,
        email: email || undefined,
        nickname: displayName,
        displayName: displayName || undefined,
        avatarUrl: avatarUrl || undefined,
        locale: locale || undefined,
        englishLevel: englishLevel || undefined,
        role: role || undefined,
      };
      AppStorage.SetOrCreate<UserProfile>(StoreKeys.USER_PROFILE, profile);
    }
  }

  /** 写入 token/refreshToken，并标记登录态。同步落盘。 */
  static setToken(token: string, refreshToken?: string): void {
    AppStorage.SetOrCreate<string>(StoreKeys.USER_TOKEN, token);
    PreferencesManager.setString(StoreKeys.USER_TOKEN, token);
    if (refreshToken) {
      AppStorage.SetOrCreate<string>(StoreKeys.USER_REFRESH_TOKEN, refreshToken);
      PreferencesManager.setString(StoreKeys.USER_REFRESH_TOKEN, refreshToken);
    }
    AppStorage.SetOrCreate<boolean>(StoreKeys.USER_LOGGED_IN, true);
  }

  /** 一次性写入 auth + 基础 profile（登录回调用）。 */
  static setAuth(token: string, refreshToken: string, userId: string, phone?: string): void {
    UserStore.setToken(token, refreshToken);
    AppStorage.SetOrCreate<string>(StoreKeys.USER_ID, userId);
    PreferencesManager.setString(StoreKeys.USER_ID, userId);
    if (phone) {
      AppStorage.SetOrCreate<string>(StoreKeys.USER_PHONE, phone);
      PreferencesManager.setString(StoreKeys.USER_PHONE, phone);
    }
  }

  static getToken(): string {
    return AppStorage.Get<string>(StoreKeys.USER_TOKEN) ?? '';
  }

  static getRefreshToken(): string {
    return AppStorage.Get<string>(StoreKeys.USER_REFRESH_TOKEN) ?? '';
  }

  static isLoggedIn(): boolean {
    return AppStorage.Get<boolean>(StoreKeys.USER_LOGGED_IN) === true;
  }

  /** Phase 4 router auth-guard 用：兼容命名。 */
  static isAuthenticated(): boolean {
    return UserStore.isLoggedIn() && UserStore.getToken().length > 0;
  }

  static getAuthHeader(): string {
    const t = UserStore.getToken();
    return t.length > 0 ? `Bearer ${t}` : '';
  }

  /** 完整覆盖 profile（兼容旧调用）。 */
  static setProfile(profile: UserProfile): void {
    AppStorage.SetOrCreate<UserProfile>(StoreKeys.USER_PROFILE, profile);
    UserStore.persistProfile(profile);
  }

  /** 部分更新 profile，缺省字段保留原值。 */
  static updateProfile(patch: Partial<UserProfile>): void {
    const cur = UserStore.getProfile();
    const next: UserProfile = {
      id: patch.id ?? cur?.id ?? '',
      phone: patch.phone ?? cur?.phone,
      email: patch.email ?? cur?.email,
      nickname: patch.nickname ?? patch.displayName ?? cur?.nickname ?? '',
      displayName: patch.displayName ?? cur?.displayName,
      avatarUrl: patch.avatarUrl ?? cur?.avatarUrl,
      locale: patch.locale ?? cur?.locale,
      cefr: patch.cefr ?? patch.englishLevel ?? cur?.cefr,
      englishLevel: patch.englishLevel ?? cur?.englishLevel,
      role: patch.role ?? cur?.role,
    };
    AppStorage.SetOrCreate<UserProfile>(StoreKeys.USER_PROFILE, next);
    UserStore.persistProfile(next);
  }

  static getProfile(): UserProfile | undefined {
    return AppStorage.Get<UserProfile>(StoreKeys.USER_PROFILE);
  }

  static clear(): void {
    AppStorage.Delete(StoreKeys.USER_TOKEN);
    AppStorage.Delete(StoreKeys.USER_REFRESH_TOKEN);
    AppStorage.Delete(StoreKeys.USER_PROFILE);
    AppStorage.Delete(StoreKeys.USER_ID);
    AppStorage.Delete(StoreKeys.USER_PHONE);
    AppStorage.Delete(StoreKeys.USER_EMAIL);
    AppStorage.Delete(StoreKeys.USER_DISPLAY_NAME);
    AppStorage.Delete(StoreKeys.USER_AVATAR_URL);
    AppStorage.Delete(StoreKeys.USER_LOCALE);
    AppStorage.Delete(StoreKeys.USER_ENGLISH_LEVEL);
    AppStorage.Delete(StoreKeys.USER_ROLE);
    AppStorage.SetOrCreate<boolean>(StoreKeys.USER_LOGGED_IN, false);

    PreferencesManager.remove(StoreKeys.USER_TOKEN);
    PreferencesManager.remove(StoreKeys.USER_REFRESH_TOKEN);
    PreferencesManager.remove(StoreKeys.USER_ID);
    PreferencesManager.remove(StoreKeys.USER_PHONE);
    PreferencesManager.remove(StoreKeys.USER_EMAIL);
    PreferencesManager.remove(StoreKeys.USER_DISPLAY_NAME);
    PreferencesManager.remove(StoreKeys.USER_AVATAR_URL);
    PreferencesManager.remove(StoreKeys.USER_LOCALE);
    PreferencesManager.remove(StoreKeys.USER_ENGLISH_LEVEL);
    PreferencesManager.remove(StoreKeys.USER_ROLE);
  }

  private static persistProfile(p: UserProfile): void {
    PreferencesManager.setString(StoreKeys.USER_ID, p.id ?? '');
    PreferencesManager.setString(StoreKeys.USER_PHONE, p.phone ?? '');
    PreferencesManager.setString(StoreKeys.USER_EMAIL, p.email ?? '');
    PreferencesManager.setString(
      StoreKeys.USER_DISPLAY_NAME,
      (p.displayName ?? p.nickname) ?? '',
    );
    PreferencesManager.setString(StoreKeys.USER_AVATAR_URL, p.avatarUrl ?? '');
    PreferencesManager.setString(StoreKeys.USER_LOCALE, p.locale ?? '');
    PreferencesManager.setString(
      StoreKeys.USER_ENGLISH_LEVEL,
      (p.englishLevel ?? p.cefr) ?? '',
    );
    PreferencesManager.setString(StoreKeys.USER_ROLE, p.role ?? '');
  }
}
