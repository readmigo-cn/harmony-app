import { RoutePath, ReaderRouteParams, AudiobookPlayerParams } from '../router/RouteConstants';
import { RouterService } from '../router/RouterService';
import { UserStore } from '../../store/UserStore';
import { AppColors } from '../theme/AppColors';
import { EffectiveTheme } from '../theme/Theme.types';
import { APP_THEME_STORAGE_KEY, ThemeService } from '../theme/ThemeService';
// W14-C1：自适应布局 —— 平板 / 折叠屏展开态走顶部 TabBar + 双栏内容
import { Breakpoint, STORAGE_KEY_BREAKPOINT } from '../theme/Breakpoints';
import { ResponsiveContainer } from '../../ui/responsive/ResponsiveContainer';
import { Login } from '../../features/account/pages/Login';
import { Onboarding } from '../../features/account/pages/Onboarding';
import { Discover } from '../../features/discover/pages/Discover';
import { Library } from '../../features/library/pages/Library';
import { Reader } from '../../features/reader/pages/Reader';
import { Me } from '../../features/account/pages/Me';
import { AudiobookTab } from '../../features/audiobook/pages/AudiobookTab';
import { AudiobookPlayer } from '../../features/audiobook/pages/AudiobookPlayer';
import { Notes } from '../../features/notes/pages/Notes';
import { StudyPlanPage } from '../../features/study/pages/StudyPlan';
import { ReadingComprehensionPage } from '../../features/ai-tools/pages/ReadingComprehension';
import { FeedbackPage } from '../../features/support/pages/Feedback';
import { TicketListPage } from '../../features/support/pages/TicketList';
import { TicketDetailPage } from '../../features/support/pages/TicketDetail';

@Entry
@Component
struct Index {
  // W2: shell stays at 4 tabs (Discover / Library / Audiobook / Me).
  // New W2 features (agora / stats / badges / quotes / annual-report / authors / series) are reached via deep links + Navigator pushes, not tab bar.
  @State currentTab: number = 0;
  // W5-C4：根组件透传 theme 给所有后代；@StorageProp 触发重渲染
  @StorageProp(APP_THEME_STORAGE_KEY) @Watch('onThemeChange') storageTheme: EffectiveTheme = 'day';
  @Provide('theme') theme: EffectiveTheme = 'day';
  // W14-C1：当前断点 —— 决定 TabBar 是底部（手机）还是顶部（平板/折叠展开）
  @StorageProp(STORAGE_KEY_BREAKPOINT) currentBp: Breakpoint = Breakpoint.MD;
  private navStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    RouterService.bind(this.navStack);
    this.theme = ThemeService.getCurrentTheme();
    if (!UserStore.isLoggedIn()) {
      this.navStack.pushPathByName(RoutePath.LOGIN, null);
    }
  }

  onThemeChange(): void {
    if (this.storageTheme && this.storageTheme !== this.theme) {
      this.theme = this.storageTheme;
    }
  }

  @Builder
  pageMap(name: string, param: object) {
    if (name === RoutePath.LOGIN) {
      Login();
    } else if (name === RoutePath.ONBOARDING) {
      Onboarding();
    } else if (name === RoutePath.READER) {
      Reader({ params: param as ReaderRouteParams });
    } else if (name === RoutePath.AUDIOBOOK_PLAYER) {
      AudiobookPlayer({ params: param as AudiobookPlayerParams });
    } else if (name === RoutePath.NOTES) {
      Notes();
    } else if (name === RoutePath.STUDY_PLAN) {
      StudyPlanPage();
    } else if (name === RoutePath.READING_COMPREHENSION) {
      ReadingComprehensionPage();
    } else if (name === RoutePath.FEEDBACK) {
      FeedbackPage();
    } else if (name === RoutePath.TICKET_LIST) {
      TicketListPage();
    } else if (name === RoutePath.TICKET_DETAIL) {
      TicketDetailPage();
    }
  }

  @Builder
  tabBuilder(index: number, labelRes: Resource, icon: Resource) {
    Column() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(this.currentTab === index ? AppColors.brand : AppColors.textSecondary)
      Text(labelRes)
        .fontSize(11)
        .fontColor(this.currentTab === index ? AppColors.brand : AppColors.textSecondary)
        .margin({ top: 2 })
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
  }

  /** W14-C1: 手机布局 —— 底部 TabBar（原始布局） */
  @Builder
  mobileLayout() {
    Tabs({ index: this.currentTab, barPosition: BarPosition.End }) {
      TabContent() {
        Discover()
      }.tabBar(this.tabBuilder(0, $r('app.string.tab_discover'), $r('app.media.app_icon')))

      TabContent() {
        Library()
      }.tabBar(this.tabBuilder(1, $r('app.string.tab_library'), $r('app.media.app_icon')))

      TabContent() {
        AudiobookTab()
      }.tabBar(this.tabBuilder(2, $r('app.string.tab_audiobook'), $r('app.media.app_icon')))

      TabContent() {
        Me()
      }.tabBar(this.tabBuilder(3, $r('app.string.tab_me'), $r('app.media.app_icon')))
    }
    .barHeight(56)
    .barMode(BarMode.Fixed)
    .onChange((idx: number) => {
      this.currentTab = idx;
    })
  }

  /** W14-C1: 平板 / 折叠屏展开态 —— 顶部 TabBar（更宽屏更习惯） */
  @Builder
  tabletLayout() {
    Tabs({ index: this.currentTab, barPosition: BarPosition.Start }) {
      TabContent() {
        Discover()
      }.tabBar(this.tabBuilder(0, $r('app.string.tab_discover'), $r('app.media.app_icon')))

      TabContent() {
        Library()
      }.tabBar(this.tabBuilder(1, $r('app.string.tab_library'), $r('app.media.app_icon')))

      TabContent() {
        AudiobookTab()
      }.tabBar(this.tabBuilder(2, $r('app.string.tab_audiobook'), $r('app.media.app_icon')))

      TabContent() {
        Me()
      }.tabBar(this.tabBuilder(3, $r('app.string.tab_me'), $r('app.media.app_icon')))
    }
    .barHeight(64)
    .barMode(BarMode.Fixed)
    .vertical(false)
    .onChange((idx: number) => {
      this.currentTab = idx;
    })
  }

  build() {
    Navigation(this.navStack) {
      ResponsiveContainer({
        mobileProvided: true,
        tabletProvided: true,
        desktopProvided: true,
        mobile: () => { this.mobileLayout() },
        tablet: () => { this.tabletLayout() },
        desktop: () => { this.tabletLayout() },
        fallback: () => { this.mobileLayout() },
      })
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor(AppColors.bgPrimary)
  }
}
