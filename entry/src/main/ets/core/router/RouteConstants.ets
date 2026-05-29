/**
 * 路由常量集中管理。NavPathStack push 时只用这里的 key，禁止字面量。
 *
 * 两类常量：
 *   - RoutePath.*：NavPathStack 的命名路由（@Builder 在 Index.ets 内通过 navDestination 解析）
 *   - PagePath.*：windowStage.loadContent / router.pushUrl 用的 main_pages.json 路径
 *
 * 本文件按 feature 分组组织（PR-7 引入），便于 rebase / 新增路由不冲突。
 */
export class RoutePath {
  // ─── shell ──────────────────────────────────────────────
  static readonly MAIN: string = 'Main';

  // ─── account ────────────────────────────────────────────
  static readonly LOGIN: string = 'Login';
  static readonly ONBOARDING: string = 'Onboarding';
  static readonly ME: string = 'Me';
  static readonly SETTINGS: string = 'Settings';
  /**
   * 忘记密码 / 重置密码（未登录可访问，无 auth guard）。
   * router.pushUrl 用 PASSWORD_RESET_URL；name key 保留用于将来切换到 NavPathStack。
   */
  static readonly PASSWORD_RESET: string = 'password-reset';
  static readonly PASSWORD_RESET_URL: string = 'features/account/pages/PasswordReset';
  /**
   * W17-C5：订阅管理页（auth required）。
   */
  static readonly SUBSCRIPTIONS: string = 'Subscriptions';
  static readonly SUBSCRIPTIONS_URL: string = 'features/account/pages/Subscriptions';
  /**
   * W17-C6：退款申请流程页（auth required）。
   */
  static readonly REFUND_FLOW: string = 'RefundFlow';
  static readonly REFUND_FLOW_URL: string = 'features/account/pages/RefundFlow';
  static readonly CONTACT: string = 'Contact';
  static readonly CONTACT_URL: string = 'features/account/pages/Contact';

  // ─── discover ───────────────────────────────────────────
  static readonly DISCOVER: string = 'Discover';

  // ─── library ────────────────────────────────────────────
  static readonly LIBRARY: string = 'Library';

  // ─── reader ─────────────────────────────────────────────
  static readonly READER: string = 'Reader';

  // ─── audiobook ──────────────────────────────────────────
  static readonly AUDIOBOOK_TAB: string = 'AudiobookTab';
  static readonly AUDIOBOOK_PLAYER: string = 'AudiobookPlayer';

  // ─── notes ──────────────────────────────────────────────
  static readonly NOTES: string = 'Notes';

  // ─── vocab ──────────────────────────────────────────────
  /**
   * W9-C5：词汇量统计 dashboard。
   */
  static readonly VOCAB_STATS: string = 'vocab-stats';
  static readonly VOCAB_STATS_URL: string = 'features/vocab/pages/VocabStats';
  /**
   * W9-C3：单词联想 mind-map 页。
   */
  static readonly WORD_ASSOCIATION: string = 'word-association';
  static readonly WORD_ASSOCIATION_URL: string = 'features/vocab/pages/WordAssociation';
  /**
   * W9-C4：词族分析页。
   */
  static readonly WORD_FAMILY: string = 'word-family';
  static readonly WORD_FAMILY_URL: string = 'features/vocab/pages/WordFamily';
  /**
   * W9-C1：生词本主页（auth required，NavPathStack 命名路由）。
   */
  static readonly VOCAB: string = 'vocab';
  static readonly VOCAB_URL: string = 'features/vocab/pages/Vocab';
  /**
   * W9-C2：闪卡 SRS 复习页（auth required，NavPathStack 命名路由）。
   */
  static readonly FLASHCARD_SESSION: string = 'flashcard-session';
  static readonly FLASHCARD_SESSION_URL: string = 'features/vocab/pages/FlashcardSession';

  // ─── ai-tools ───────────────────────────────────────────
  /**
   * W9-C8：弱点分析报告。
   */
  static readonly WEAKNESS_ANALYSIS: string = 'weakness-analysis';
  static readonly WEAKNESS_ANALYSIS_URL: string = 'features/ai-tools/pages/WeaknessAnalysis';
  /**
   * W9-C7：阅读理解题页（书内 toolbar 触发，传 bookId / chapterIndex）。
   */
  static readonly READING_COMPREHENSION: string = 'ReadingComprehension';
  static readonly READING_COMPREHENSION_URL: string = 'features/ai-tools/pages/ReadingComprehension';

  // ─── study ──────────────────────────────────────────────
  /**
   * W9-C6：AI 个性化学习计划页。
   */
  static readonly STUDY_PLAN: string = 'StudyPlan';
  static readonly STUDY_PLAN_URL: string = 'features/study/pages/StudyPlan';

  // ─── support ────────────────────────────────────────────
  /**
   * W19-C1：反馈表单页（提交后跳 TicketDetail）。
   */
  static readonly FEEDBACK: string = 'Feedback';
  static readonly FEEDBACK_URL: string = 'features/support/pages/Feedback';
  /**
   * W19-C2：工单列表页（auth required）。
   */
  static readonly TICKET_LIST: string = 'TicketList';
  static readonly TICKET_LIST_URL: string = 'features/support/pages/TicketList';
  /**
   * W19-C2：工单详情页（聊天时间线 + 追问 + 关闭 + 评分）。
   */
  static readonly TICKET_DETAIL: string = 'TicketDetail';
  static readonly TICKET_DETAIL_URL: string = 'features/support/pages/TicketDetail';
  /**
   * W19-C3：常见问题（FAQ）页。
   */
  static readonly FAQ: string = 'Faq';
  static readonly FAQ_URL: string = 'features/support/pages/Faq';
  /**
   * W19-C4：关于页（版本号、公司、ICP）。
   */
  static readonly ABOUT: string = 'About';
  static readonly ABOUT_URL: string = 'features/support/pages/About';
  /**
   * W19-C5：用户协议 / 隐私政策 / 第三方开源声明 / 联系我们。
   */
  static readonly USER_AGREEMENT: string = 'UserAgreement';
  static readonly USER_AGREEMENT_URL: string = 'features/support/pages/UserAgreement';
  static readonly PRIVACY_POLICY: string = 'PrivacyPolicy';
  static readonly PRIVACY_POLICY_URL: string = 'features/support/pages/PrivacyPolicy';
  static readonly OSS_LICENSES: string = 'OssLicenses';
  static readonly OSS_LICENSES_URL: string = 'features/support/pages/OssLicenses';

  // ─── notification ───────────────────────────────────────
  /**
   * W18-C6：通知中心页（历史通知列表 + 筛选 + 操作）。
   */
  static readonly NOTIFICATION_CENTER: string = 'notification-center';
  static readonly NOTIFICATION_CENTER_URL: string = 'features/notification/pages/NotificationCenter';

  // ─── multi-platform ─────────────────────────────────────
  /**
   * 开发者工具：原生组件 demo（W2-C5）。
   * 实际页路径：pages/native/XComponentDemo（router.pushUrl 使用）。
   */
  static readonly XCOMPONENT_DEMO: string = 'xcomponent-demo';
  static readonly XCOMPONENT_DEMO_URL: string = 'features/multi-platform/pages/native/XComponentDemo';
  /** 别名：与任务命名对齐。 */
  static readonly NATIVE_DEMO: string = 'xcomponent-demo';

  // ─── dev ────────────────────────────────────────────────
  /**
   * 开发者工具：W6 组件演示页（W6-C10）。
   * 实际页路径：pages/dev/ComponentGallery（router.pushUrl 使用）。
   */
  static readonly COMPONENT_GALLERY: string = 'component-gallery';
  static readonly COMPONENT_GALLERY_URL: string = 'features/dev/pages/dev/ComponentGallery';

  // ─── agora (W2) ─────────────────────────────────────────
  /** W2：社区主页（动态流）。 */
  static readonly AGORA: string = 'Agora';
  static readonly AGORA_URL: string = 'features/agora/pages/AgoraPage';
  /** W2：帖子详情页。 */
  static readonly AGORA_POST_DETAIL: string = 'AgoraPostDetail';
  static readonly AGORA_POST_DETAIL_URL: string = 'features/agora/pages/PostDetailPage';
  /** W2：发帖页（auth required）。 */
  static readonly AGORA_CREATE_POST: string = 'AgoraCreatePost';
  static readonly AGORA_CREATE_POST_URL: string = 'features/agora/pages/CreatePostPage';
  /** W2：评论详情页（楼中楼）。 */
  static readonly AGORA_COMMENT_DETAIL: string = 'AgoraCommentDetail';
  static readonly AGORA_COMMENT_DETAIL_URL: string = 'features/agora/pages/CommentDetailPage';

  // ─── stats (W2) ─────────────────────────────────────────
  /** W2：阅读统计 dashboard。 */
  static readonly STATS: string = 'Stats';
  static readonly STATS_URL: string = 'features/stats/pages/StatsPage';
  /** W2：单本书阅读统计详情。 */
  static readonly STATS_BOOK_DETAIL: string = 'StatsBookDetail';
  static readonly STATS_BOOK_DETAIL_URL: string = 'features/stats/pages/BookStatsDetailPage';

  // ─── badges (W2) ────────────────────────────────────────
  /** W2：3D 勋章成就墙。 */
  static readonly BADGES: string = 'Badges';
  static readonly BADGES_URL: string = 'features/badges/pages/BadgesPage';
  /** W2：勋章详情 + 分享卡。 */
  static readonly BADGES_DETAIL: string = 'BadgesDetail';
  static readonly BADGES_DETAIL_URL: string = 'features/badges/pages/BadgeDetailPage';

  // ─── quotes (W2) ────────────────────────────────────────
  /** W2：每日金句 / 热门金句合集。 */
  static readonly QUOTES: string = 'Quotes';
  static readonly QUOTES_URL: string = 'features/quotes/pages/QuotesPage';
  /** W2：金句详情。 */
  static readonly QUOTES_DETAIL: string = 'QuotesDetail';
  static readonly QUOTES_DETAIL_URL: string = 'features/quotes/pages/QuoteDetailPage';

  // ─── annual-report (W2) ─────────────────────────────────
  /** W2：年度阅读报告（沉浸式翻页）。 */
  static readonly ANNUAL_REPORT: string = 'AnnualReport';
  static readonly ANNUAL_REPORT_URL: string = 'features/annual-report/pages/AnnualReportPage';
  /** W2：历年年度报告列表。 */
  static readonly ANNUAL_REPORT_HISTORY: string = 'AnnualReportHistory';
  static readonly ANNUAL_REPORT_HISTORY_URL: string = 'features/annual-report/pages/AnnualReportHistoryPage';

  // ─── authors (W2) ───────────────────────────────────────
  /** W2：作者主页。 */
  static readonly AUTHORS_PROFILE: string = 'AuthorsProfile';
  static readonly AUTHORS_PROFILE_URL: string = 'features/authors/pages/AuthorProfilePage';
  /** W2：我关注的作者列表（auth required）。 */
  static readonly AUTHORS_FOLLOWING: string = 'AuthorsFollowing';
  static readonly AUTHORS_FOLLOWING_URL: string = 'features/authors/pages/FollowingAuthorsPage';

  // ─── series (W2) ────────────────────────────────────────
  /** W2：丛书 / 系列列表。 */
  static readonly SERIES_LIST: string = 'SeriesList';
  static readonly SERIES_LIST_URL: string = 'features/series/pages/SeriesListPage';
  /** W2：系列详情（含书目顺序）。 */
  static readonly SERIES_DETAIL: string = 'SeriesDetail';
  static readonly SERIES_DETAIL_URL: string = 'features/series/pages/SeriesDetailPage';

  // ── new entries below ──
  // (rebase-friendly anchor for future routes)
}

/**
 * windowStage.loadContent / router.pushUrl 使用的页面相对路径。
 * 必须与 main_pages.json 中的 src 项一致。
 * 按 feature 分组（PR-7 引入）。
 */
export class PagePath {
  // ─── shell ──────────────────────────────────────────────
  static readonly INDEX: string = 'core/shell/Index';

  // ─── account ────────────────────────────────────────────
  static readonly LOGIN: string = 'features/account/pages/Login';
  static readonly ONBOARDING: string = 'features/account/pages/Onboarding';
  static readonly ME: string = 'features/account/pages/Me';
  static readonly SUBSCRIPTIONS: string = 'features/account/pages/Subscriptions';
  static readonly REFUND_FLOW: string = 'features/account/pages/RefundFlow';
  static readonly CONTACT: string = 'features/account/pages/Contact';

  // ─── discover ───────────────────────────────────────────
  static readonly DISCOVER: string = 'features/discover/pages/Discover';

  // ─── library ────────────────────────────────────────────
  static readonly LIBRARY: string = 'features/library/pages/Library';

  // ─── reader ─────────────────────────────────────────────
  static readonly READER: string = 'features/reader/pages/Reader';

  // ─── audiobook ──────────────────────────────────────────
  static readonly AUDIOBOOK_TAB: string = 'features/audiobook/pages/AudiobookTab';
  static readonly AUDIOBOOK_PLAYER: string = 'features/audiobook/pages/AudiobookPlayer';

  // ─── notes ──────────────────────────────────────────────
  static readonly NOTES: string = 'features/notes/pages/Notes';

  // ─── vocab ──────────────────────────────────────────────
  static readonly VOCAB_STATS: string = 'features/vocab/pages/VocabStats';
  static readonly WORD_ASSOCIATION: string = 'features/vocab/pages/WordAssociation';
  static readonly WORD_FAMILY: string = 'features/vocab/pages/WordFamily';
  static readonly VOCAB: string = 'features/vocab/pages/Vocab';
  static readonly FLASHCARD_SESSION: string = 'features/vocab/pages/FlashcardSession';

  // ─── ai-tools ───────────────────────────────────────────
  static readonly WEAKNESS_ANALYSIS: string = 'features/ai-tools/pages/WeaknessAnalysis';
  static readonly READING_COMPREHENSION: string = 'features/ai-tools/pages/ReadingComprehension';

  // ─── study ──────────────────────────────────────────────
  static readonly STUDY_PLAN: string = 'features/study/pages/StudyPlan';

  // ─── support ────────────────────────────────────────────
  static readonly FEEDBACK: string = 'features/support/pages/Feedback';
  static readonly TICKET_LIST: string = 'features/support/pages/TicketList';
  static readonly TICKET_DETAIL: string = 'features/support/pages/TicketDetail';
  static readonly FAQ: string = 'features/support/pages/Faq';
  static readonly ABOUT: string = 'features/support/pages/About';
  static readonly USER_AGREEMENT: string = 'features/support/pages/UserAgreement';
  static readonly PRIVACY_POLICY: string = 'features/support/pages/PrivacyPolicy';
  static readonly OSS_LICENSES: string = 'features/support/pages/OssLicenses';

  // ─── notification ───────────────────────────────────────
  static readonly NOTIFICATION_CENTER: string = 'features/notification/pages/NotificationCenter';

  // ─── agora (W2) ─────────────────────────────────────────
  static readonly AGORA: string = 'features/agora/pages/AgoraPage';
  static readonly AGORA_POST_DETAIL: string = 'features/agora/pages/PostDetailPage';
  static readonly AGORA_CREATE_POST: string = 'features/agora/pages/CreatePostPage';
  static readonly AGORA_COMMENT_DETAIL: string = 'features/agora/pages/CommentDetailPage';

  // ─── stats (W2) ─────────────────────────────────────────
  static readonly STATS: string = 'features/stats/pages/StatsPage';
  static readonly STATS_BOOK_DETAIL: string = 'features/stats/pages/BookStatsDetailPage';

  // ─── badges (W2) ────────────────────────────────────────
  static readonly BADGES: string = 'features/badges/pages/BadgesPage';
  static readonly BADGES_DETAIL: string = 'features/badges/pages/BadgeDetailPage';

  // ─── quotes (W2) ────────────────────────────────────────
  static readonly QUOTES: string = 'features/quotes/pages/QuotesPage';
  static readonly QUOTES_DETAIL: string = 'features/quotes/pages/QuoteDetailPage';

  // ─── annual-report (W2) ─────────────────────────────────
  static readonly ANNUAL_REPORT: string = 'features/annual-report/pages/AnnualReportPage';
  static readonly ANNUAL_REPORT_HISTORY: string = 'features/annual-report/pages/AnnualReportHistoryPage';

  // ─── authors (W2) ───────────────────────────────────────
  static readonly AUTHORS_PROFILE: string = 'features/authors/pages/AuthorProfilePage';
  static readonly AUTHORS_FOLLOWING: string = 'features/authors/pages/FollowingAuthorsPage';

  // ─── series (W2) ────────────────────────────────────────
  static readonly SERIES_LIST: string = 'features/series/pages/SeriesListPage';
  static readonly SERIES_DETAIL: string = 'features/series/pages/SeriesDetailPage';

  // ── new entries below ──
  // (rebase-friendly anchor for future page paths)
}

/** 需要登录态才能进的路由（router auth-guard 使用）。 */
export const AUTH_REQUIRED_ROUTES: ReadonlySet<string> = new Set<string>([
  RoutePath.LIBRARY,
  RoutePath.READER,
  RoutePath.ME,
  RoutePath.NOTES,
  RoutePath.AUDIOBOOK_PLAYER,
  RoutePath.VOCAB,
  RoutePath.FLASHCARD_SESSION,
  RoutePath.TICKET_LIST,
  RoutePath.TICKET_DETAIL,
  RoutePath.SUBSCRIPTIONS,
  RoutePath.REFUND_FLOW,
  // W2：发帖、关注列表需要登录态
  RoutePath.AGORA_CREATE_POST,
  RoutePath.AUTHORS_FOLLOWING,
]);

// ---- Route param 类型 ----

export interface ReaderRouteParams {
  bookId: string;
  chapterId?: string;
}

export interface AudiobookPlayerParams {
  audiobookId: string;
  chapterIndex?: number;
}

export interface LoginRouteParams {
  /** 登录成功后跳转的目标路由名（可选）。 */
  redirectTo?: string;
  redirectParams?: object;
}

export interface OnboardingRouteParams {
  step?: number;
}

export interface NotesRouteParams {
  bookId?: string;
}

export interface DiscoverRouteParams {
  category?: string;
}

export interface ComprehensionRouteParams {
  bookId: string;
  chapterIndex: number;
}

export interface StudyPlanRouteParams {}

export interface MeRouteParams {}
export interface LibraryRouteParams {}
export interface AudiobookTabRouteParams {}
export interface NativeDemoRouteParams {}

/** Deep link 解析结果。 */
export interface DeepLinkTarget {
  route: string;
  params: object | null;
}

// ---- W19-C1+C2 反馈 / 工单 ----

export interface FeedbackRouteParams {
  /** 预填类别（从 paywall / reader 等触发时可指定） */
  category?: string;
  /** 触发反馈时所在路由（自动附加，用户可勾去） */
  fromRoute?: string;
}

export interface TicketListRouteParams {}

export interface TicketDetailRouteParams {
  ticketId: string;
}
