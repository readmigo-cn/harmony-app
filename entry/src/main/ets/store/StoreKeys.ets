/**
 * AppStorage / 持久化 key 集中管理。
 * 命名约定：模块_字段，全部小写下划线。
 *
 * AppStorage key（运行时）与 Preferences key（持久化）共用，避免双套常量。
 */
export class StoreKeys {
  // user (auth)
  static readonly USER_TOKEN: string = 'user_token';
  static readonly USER_REFRESH_TOKEN: string = 'user_refresh_token';
  static readonly USER_PROFILE: string = 'user_profile';
  static readonly USER_LOGGED_IN: string = 'user_logged_in';
  // user profile fields (拆开存便于做 partial update + 单字段持久化)
  static readonly USER_ID: string = 'user_id';
  static readonly USER_PHONE: string = 'user_phone';
  static readonly USER_EMAIL: string = 'user_email';
  static readonly USER_DISPLAY_NAME: string = 'user_display_name';
  static readonly USER_AVATAR_URL: string = 'user_avatar_url';
  static readonly USER_LOCALE: string = 'user_locale';
  static readonly USER_ENGLISH_LEVEL: string = 'user_english_level';
  static readonly USER_ROLE: string = 'user_role';

  // settings
  static readonly SETTINGS_LOCALE: string = 'settings_locale';
  static readonly SETTINGS_THEME: string = 'settings_theme';
  static readonly SETTINGS_READER_FONT_SIZE: string = 'settings_reader_font_size';
  static readonly SETTINGS_READER_THEME: string = 'settings_reader_theme';
  static readonly SETTINGS_READER_LINE_HEIGHT: string = 'settings_reader_line_height';
  static readonly SETTINGS_READER_FONT_SIZE_LEVEL: string = 'settings_reader_font_size_level';
  static readonly SETTINGS_READER_LINE_HEIGHT_LEVEL: string = 'settings_reader_line_height_level';
  static readonly SETTINGS_READER_PAGE_TURN_MODE: string = 'settings_reader_page_turn_mode';
  static readonly SETTINGS_READER_FONT: string = 'settings_reader_font';
  static readonly SETTINGS_NOTIFICATIONS_DAILY: string = 'settings_notifications_daily';
  static readonly SETTINGS_NOTIFICATIONS_TIME: string = 'settings_notifications_time';
  static readonly SETTINGS_TTS_VOICE: string = 'settings_tts_voice';
  static readonly SETTINGS_TTS_SPEED: string = 'settings_tts_speed';

  // reading
  static readonly READING_CURRENT_BOOK: string = 'reading_current_book';
  static readonly READING_CURRENT_SLUG: string = 'reading_current_slug';
  static readonly READING_CURRENT_TITLE: string = 'reading_current_title';
  static readonly READING_CURRENT_COVER: string = 'reading_current_cover';
  static readonly READING_LAST_PROGRESS: string = 'reading_last_progress';
  static readonly READING_SESSION_ID: string = 'reading_session_id';
  static readonly READING_RECENT_BOOKS: string = 'reading_recent_books';
  // W7-C5/C6 章节状态 + 云端同步
  static readonly READING_CHAPTER_PROGRESS: string = 'reading_chapter_progress';
  static readonly READING_LAST_SYNCED_AT: string = 'reading_last_synced_at';
  static readonly READING_PROGRESS_QUEUE: string = 'reading_progress_queue';

  // app
  static readonly APP_FIRST_LAUNCH: string = 'app_first_launch';
  static readonly APP_NAV_STACK: string = 'globalNavStack';
  static readonly APP_ROUTE_HISTORY: string = 'app_route_history';
  static readonly APP_PENDING_DEEP_LINK: string = 'app_pending_deep_link';
}
