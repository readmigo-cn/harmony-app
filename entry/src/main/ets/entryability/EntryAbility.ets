import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import Configuration from '@ohos.app.ability.Configuration';
import { PreferencesManager } from '../core/persistence/PreferencesManager';
import { DatabaseManager } from '../core/persistence/DatabaseManager';
import { UserStore } from '../store/UserStore';
import { ReadingStore } from '../store/ReadingStore';
import { SettingsStore } from '../store/SettingsStore';
import { StoreKeys } from '../store/StoreKeys';
import { RouterService } from '../core/router/RouterService';
import { PagePath } from '../core/router/RouteConstants';
import { ThemeService } from '../core/theme/ThemeService';
import { FontRegistry } from '../core/theme/FontRegistry';
import { LocalizationManager } from '../core/i18n/LocalizationManager';
import { ProgressSync } from '../features/multi-device/service/ProgressSync';
// W14-C1：自适应布局 / 折叠屏感知。需要 windowStage，因此在 onWindowStageCreate 里初始化
import { initBreakpoints, disposeBreakpoints } from '../core/theme/Breakpoints';
// W13-C1 / W13-C3：分布式设备发现 + 接续生命周期
import { DeviceManager } from '../features/multi-device/service/distributed/DeviceManager';
import { ContinuationManager } from '../core/atomic/ContinuationManager';
// W13-C2：跨端剪贴板订阅（接收其它设备分享的 vocab / highlight）
import { DistributedClipboard, IncomingEntry } from '../features/multi-device/service/distributed/DistributedClipboard';
// W13-C4：多端通知协调器
import { MultiDeviceNotifier } from '../features/notification/service/notification/MultiDeviceNotifier';
// W18-C1 / C2 / C3：埋点 + 双轨崩溃监控
import { Analytics } from '../core/analytics/AnalyticsProvider';
import { SensorsAnalytics, SaEvents } from '../core/analytics/SensorsAnalytics';
import { AgcCrashReporter } from '../core/monitoring/AgcCrashReporter';
import { SentryClient } from '../core/monitoring/SentryClient';
import { CrashHandler } from '../core/monitoring/CrashHandler';
// W18-C4 / C5 / C7：HMS Push + 通知通道 + 远程配置 / A/B
import { HmsPushService } from '../features/notification/service/push/HmsPushService';
import { NotificationChannel } from '../features/notification/service/push/NotificationChannel';
import { RemoteConfig } from '../core/experiments/RemoteConfig';
// W20-C3：性能监控 + 异步启动框架 + 内存守卫
import { PerformanceMonitor } from '../core/performance/PerformanceMonitor';
import { StartupOptimizer, TaskPriority } from '../core/performance/StartupOptimizer';
import { MemoryGuard } from '../core/performance/MemoryGuard';
// W6：支付 deeplink 回调（alipays:// / weixin://）
import { PaymentDeepLinkHandler } from '../features/account/service/payment/PaymentDeepLinkHandler';
// W6 CN-compliance: runtime config + auth providers
import { SA_SERVER_URL, SA_PROJECT_NAME, AGC_APP_ID, SENTRY_DSN, SENTRY_ENV } from '../core/config/CnConfig';
import { WeChatAuthProvider } from '../features/account/service/WeChatAuthProvider';

const TAG = 'EntryAbility';

/**
 * EntryAbility：app 进程入口。
 *
 * 责任：
 *   1) 启动期初始化：通过 StartupOptimizer 按优先级分级调度所有 init 任务
 *   2) 决定首页：first launch -> Onboarding；未登录 -> Login（W4 已在 Index.ets 内做二次保护）
 *   3) Deep link：从 cold-launch want.uri 提取，待 NavPathStack 就绪后跳转
 *   4) Lifecycle：onForeground / onBackground 触发 reading session 暂停/恢复
 *   5) onMemoryLevel：委托 MemoryGuard 分级清理内存
 *
 * W20-C3 启动任务优先级分配：
 *   CRITICAL（< 430ms 目标）：
 *     prefs_db_init → stores_init → theme_init → first_launch_flag → deeplink_parse
 *   HIGH（首屏后立即）：
 *     crash_monitor_init（AGC/Sentry/CrashHandler） → sa_analytics_init → memory_guard_start
 *   NORMAL（100ms 延迟，空闲期）：
 *     font_register → sync_engine_init → device_manager → remote_config → hms_push → notification_channel
 *   LOW（1000ms 延迟，懒加载）：
 *     agc_crash_queue_flush → sa_queue_replay → distributed_clipboard_subscribe
 */
export default class EntryAbility extends UIAbility {
  private pendingDeepLink: string = '';
  private isFirstLaunch: boolean = false;

  async onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): Promise<void> {
    // W20-C3：性能监控最先初始化，记录 app_start 起点
    const monitor = PerformanceMonitor.getInstance();
    monitor.init();

    const optimizer = StartupOptimizer.getInstance();
    // 保存 want 引用，供 CRITICAL 任务内访问
    const capturedWant = want;

    // ========== CRITICAL：首屏渲染前必须完成 ==========

    // Preferences + RDB 必须最先，其它所有初始化依赖此二者
    optimizer.registerTask('prefs_db_init', TaskPriority.CRITICAL, async () => {
      await PreferencesManager.init(this.context);
      await DatabaseManager.init(this.context);
    });

    // 三个 Store 回灌 AppStorage（依赖 prefs_db_init，串行调度保证顺序）
    optimizer.registerTask('stores_init', TaskPriority.CRITICAL, async () => {
      await UserStore.init();
      await ReadingStore.init();
      await SettingsStore.init();
    });

    // P0-A: i18n 在 PreferencesManager 之后（拉取持久化语种偏好），UI 渲染前
    optimizer.registerTask('i18n_init', TaskPriority.CRITICAL, async () => {
      await LocalizationManager.init();
    });

    // 主题必须在 SettingsStore 之后，首帧渲染需要正确主题色
    optimizer.registerTask('theme_init', TaskPriority.CRITICAL, () => {
      ThemeService.init(this.context);
    });

    // 首次启动标记（影响首页路由决策）
    optimizer.registerTask('first_launch_flag', TaskPriority.CRITICAL, async () => {
      const seen = await PreferencesManager.getBool(StoreKeys.APP_FIRST_LAUNCH, false);
      this.isFirstLaunch = !seen;
      if (this.isFirstLaunch) {
        await PreferencesManager.setBool(StoreKeys.APP_FIRST_LAUNCH, true);
      }
    });

    // Deep link 解析（cold launch want.uri，首帧后 RouterService 消费）
    optimizer.registerTask('deeplink_parse', TaskPriority.CRITICAL, () => {
      if (capturedWant && capturedWant.uri) {
        this.pendingDeepLink = capturedWant.uri;
        AppStorage.SetOrCreate<string>(StoreKeys.APP_PENDING_DEEP_LINK, capturedWant.uri);
      }
    });

    // ========== HIGH：首屏渲染后立即调度 ==========

    // 崩溃监控必须早于业务代码执行（仅次于 CRITICAL，确保 CRITICAL 异常也能被拦截）
    optimizer.registerTask('crash_monitor_init', TaskPriority.HIGH, () => {
      AgcCrashReporter.init(AGC_APP_ID);
      SentryClient.init(SENTRY_DSN, SENTRY_ENV);
      CrashHandler.init();
    });

    // 神策埋点：CRITICAL 完成后立即初始化，确保后续用户行为不丢失
    optimizer.registerTask('sa_analytics_init', TaskPriority.HIGH, async () => {
      const sa = SensorsAnalytics.getInstance();
      await sa.init(SA_SERVER_URL, SA_PROJECT_NAME);
      sa.registerSuperProperties({
        '$os': 'HarmonyOS',
        '$lib': 'harmony',
        'app_channel': 'cn',
      });
      Analytics.register(sa);
      // 已登录态 → 关联 userId 到崩溃监控 + 埋点
      if (UserStore.isAuthenticated()) {
        const profile = UserStore.getProfile();
        if (profile && profile.id) {
          AgcCrashReporter.setUserId(profile.id);
          SentryClient.setUser({ id: profile.id, email: profile.email });
          Analytics.identify(profile.id);
        }
      }
    });

    // W20-C3：内存守卫启动（HIGH 级，尽早开始轮询）
    optimizer.registerTask('memory_guard_start', TaskPriority.HIGH, () => {
      MemoryGuard.getInstance().start();
    });

    // ========== NORMAL：100ms 延迟，空闲期执行 ==========

    // 字体注册：缺文件容错，不影响首屏文字渲染（系统字体兜底）
    optimizer.registerTask('font_register', TaskPriority.NORMAL, async () => {
      await FontRegistry.registerFonts(this.context);
    });

    // W7-C6：进度同步队列恢复（崩溃续传，非首屏必需）
    optimizer.registerTask('sync_engine_init', TaskPriority.NORMAL, async () => {
      await ProgressSync.init();
    });

    // W13-C1：分布式设备管理器（bundleName 与 module.json5 一致）
    optimizer.registerTask('device_manager_init', TaskPriority.NORMAL, async () => {
      await DeviceManager.init('cn.readmigo.app');
    });

    // W18-C7：远程配置 + A/B 实验（先于 push，保证 push topic 决策用最新配置）
    optimizer.registerTask('remote_config_init', TaskPriority.NORMAL, async () => {
      await RemoteConfig.init();
    });

    // W6：WeChat AppID registration (must run before any WeChat auth call)
    optimizer.registerTask('wechat_register', TaskPriority.NORMAL, () => {
      WeChatAuthProvider.register();
    });

    // W18-C4：HMS Push Kit（远程配置之后）
    optimizer.registerTask('hms_push_init', TaskPriority.NORMAL, async () => {
      await HmsPushService.init();
      // 已登录态 → 上报 token 绑定 userId
      if (UserStore.isAuthenticated()) {
        const profile = UserStore.getProfile();
        if (profile && profile.id) {
          HmsPushService.reportToken(profile.id).catch(() => {});
        }
      }
    });

    // W18-C5：通知通道（6 类）
    optimizer.registerTask('notification_channel_init', TaskPriority.NORMAL, async () => {
      await NotificationChannel.init();
    });

    // W13-C4：多端通知协调器
    optimizer.registerTask('multi_device_notifier_init', TaskPriority.NORMAL, async () => {
      await MultiDeviceNotifier.init();
    });

    // ========== LOW：1000ms 延迟，懒加载 ==========

    // AGC 崩溃队列 flush（上次崩溃补发，无时效性要求）
    optimizer.registerTask('agc_crash_queue_flush', TaskPriority.LOW, async () => {
      await CrashHandler.checkPendingCrashOnLaunch();
    });

    // 神策失败队列 replay（上次 flush 失败的事件重发）
    optimizer.registerTask('sa_queue_replay', TaskPriority.LOW, async () => {
      await Analytics.flush();
    });

    // W13-C2：跨端剪贴板订阅（用户操作触发，不影响启动）
    optimizer.registerTask('distributed_clipboard_subscribe', TaskPriority.LOW, () => {
      DistributedClipboard.subscribeIncoming((entry: IncomingEntry) => {
        if (entry.kind === 'vocab' || entry.kind === 'highlight') {
          AppStorage.SetOrCreate<IncomingEntry>('paste_incoming_entry', entry);
          AppStorage.SetOrCreate<boolean>('paste_incoming_visible', true);
        }
      });
    });

    // 执行所有已注册任务（CRITICAL 任务串行等待，其余异步调度）
    try {
      await optimizer.run();
    } catch (err) {
      const e = err as Error;
      console.error(`${TAG} startup optimizer failed: ${e.message}`);
    }

    // CRITICAL 阶段完成后上报启动耗时到 W18 仪表板
    monitor.markEnd('app_start');
    monitor.reportToAnalytics();
  }

  /**
   * 热启动 / 单实例复用时收到新 want。
   * 支付回调（alipays:// / weixin://）优先交给 PaymentDeepLinkHandler，
   * 不进普通路由，避免误触发页面跳转。
   */
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (want && want.uri) {
      // W6: WeChat OAuth redirect-back (scheme: wx<appid>://)
      if (want.uri.startsWith('wx')) {
        WeChatAuthProvider.handleCallback(want.uri, (result) => {
          if (result) {
            const resolver = (globalThis as Record<string, unknown>)['__wechat_pending_resolve'];
            if (typeof resolver === 'function') {
              (resolver as (r: object) => void)(result);
              delete (globalThis as Record<string, unknown>)['__wechat_pending_resolve'];
              delete (globalThis as Record<string, unknown>)['__wechat_pending_reject'];
            }
          }
        });
        return;
      }
      if (PaymentDeepLinkHandler.dispatch(want.uri)) {
        return;
      }
      this.pendingDeepLink = want.uri;
      AppStorage.SetOrCreate<string>(StoreKeys.APP_PENDING_DEEP_LINK, want.uri);
      RouterService.handleDeepLink(want.uri);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 首页统一为 pages/Index：内部根据 UserStore.isLoggedIn / first-launch 决定
    // 在 NavPathStack 上 push Login / Onboarding。这样保持 windowStage.loadContent
    // 单一入口，避免冷启动加载多页造成的状态错乱。
    windowStage.loadContent(PagePath.INDEX, (error) => {
      if (error.code) {
        console.error(`${TAG} loadContent failed: ${error.code} ${error.message}`);
        return;
      }
      // first-launch / pending deep link 标记给 Index.ets 消费
      AppStorage.SetOrCreate<boolean>(StoreKeys.APP_FIRST_LAUNCH, this.isFirstLaunch);
      // pendingDeepLink 在 Index aboutToAppear 后由 RouterService.handleDeepLink 消费
    });

    // W14-C1：注册断点 / 折叠屏监听 → AppStorage（UI 通过 @StorageProp 订阅）
    initBreakpoints(windowStage).catch((err: Error) => {
      console.warn(`${TAG} initBreakpoints failed: ${err.message}`);
    });
  }

  onWindowStageDestroy(): void {
    // 释放运行时缓存
    RouterService.clearHistory();
    // W14-C1：解除窗口尺寸 / 折叠屏监听
    disposeBreakpoints();
  }

  onForeground(): void {
    // 恢复 reading session：当前没有 active timer，留给 Reader 页 onPageShow 触发
    console.info(`${TAG} onForeground`);
    // W7-C6：恢复联机后立即把队列里残留的更新推上去
    ProgressSync.flush().catch(() => {});
    // W13-C3：恢复设备 polling
    ContinuationManager.onAppForeground();
    // W13-C4：刷新「最近活跃」时间戳，参与多端通知去重判定
    MultiDeviceNotifier.markActive();
  }

  onBackground(): void {
    // 暂停 reading session + 强制 flush 进度
    const progress = ReadingStore.getLastProgress();
    if (progress) {
      ReadingStore.setLastProgress(progress); // 触发一次 flush
    }
    // W7-C6：进入后台前强制 flush，避免因系统挂起丢失最新进度
    ProgressSync.flush().catch(() => {});
    // W13-C3：暂停设备 polling 节省电量
    ContinuationManager.onAppBackground();
    // W18-C1：埋点队列立即 flush，避免系统挂起丢事件
    Analytics.track(SaEvents.APP_BACKGROUNDED, {});
    Analytics.flush().catch(() => {});
    console.info(`${TAG} onBackground`);
  }

  /**
   * 系统内存压力回调。level 0=MODERATE 1=LOW 2=CRITICAL（依 SDK 文档）。
   * W20-C3：委托 MemoryGuard 执行分级清理策略。
   * 保留 RouterService.clearHistory() 作为额外兜底。
   */
  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    console.info(`${TAG} onMemoryLevel ${level}`);
    // W20-C3：交由 MemoryGuard 执行排版缓存 / CacheManager / 图片 LRU 清理
    MemoryGuard.getInstance().handleSystemMemoryLevel(level);
    if (level >= AbilityConstant.MemoryLevel.MEMORY_LEVEL_LOW) {
      RouterService.clearHistory();
    }
  }

  /**
   * 系统配置变化（暗色模式切换、locale 变更等）。
   * W5-C4：把 colorMode 转给 ThemeService 重算。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    try {
      if (newConfig && typeof newConfig.colorMode === 'number') {
        ThemeService.onSystemColorModeChange(newConfig.colorMode);
      }
    } catch (err) {
      const e = err as Error;
      console.warn(`${TAG} onConfigurationUpdate failed: ${e.message}`);
    }
  }

  onDestroy(): void {
    console.info(`${TAG} onDestroy`);
  }

  /**
   * 根据 want.parameters.target 决定深链落到哪个子 ability。
   * deep link / shortcut 解析完得到一个 logical target，再 startAbility 到对应 ability。
   *
   *   target=reader  -> ReaderAbility
   *   target=library -> LibraryAbility
   *   target=settings-> SettingsAbility
   *   target=audio   -> AudioAbility
   *   default        -> EntryAbility（继续走 NavPathStack 路由）
   *
   * 不在 onCreate 自动 startAbility，由 RouterService 在 NavPathStack 就绪后调用。
   */
  getDispatchedAbility(want: Want): string {
    if (!want || !want.parameters) {
      return 'EntryAbility';
    }
    const params = want.parameters as Record<string, Object>;
    const target = (params.target as string) ?? '';
    switch (target) {
      case 'reader':
        return 'ReaderAbility';
      case 'library':
        return 'LibraryAbility';
      case 'settings':
        return 'SettingsAbility';
      case 'audio':
        return 'AudioAbility';
      default:
        return 'EntryAbility';
    }
  }
}
