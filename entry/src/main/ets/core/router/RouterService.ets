import { UserStore } from '../../store/UserStore';
import { StoreKeys } from '../../store/StoreKeys';
import {
  RoutePath,
  AUTH_REQUIRED_ROUTES,
  DeepLinkTarget,
  LoginRouteParams,
} from './RouteConstants';
import { ModuleLoader, ModuleName } from '../dynamic/ModuleLoader';

const MAX_HISTORY = 50;
const DEEP_LINK_SCHEME = 'readmigo://';

/**
 * Maps route names to the HSP that must be loaded before navigation.
 * Routes not in this map live in the entry HAP and need no pre-load.
 */
const ROUTE_TO_HSP: ReadonlyMap<string, ModuleName> = new Map<string, ModuleName>([
  [RoutePath.READER, 'reader'],
  [RoutePath.READING_COMPREHENSION, 'reader'],
  [RoutePath.WEAKNESS_ANALYSIS, 'reader'],
  [RoutePath.VOCAB, 'vocab'],
  [RoutePath.FLASHCARD_SESSION, 'vocab'],
  [RoutePath.VOCAB_STATS, 'vocab'],
  [RoutePath.WORD_ASSOCIATION, 'vocab'],
  [RoutePath.WORD_FAMILY, 'vocab'],
  [RoutePath.SUBSCRIPTIONS, 'paywall'],
  [RoutePath.REFUND_FLOW, 'paywall'],
]);

interface HistoryEntry {
  route: string;
  at: number;
}

/**
 * Router 单例：包装 NavPathStack。
 *
 * 职责：
 *   - 全局唯一 NavPathStack（写入 AppStorage 'globalNavStack' 给子页拿）
 *   - 命名路由 push/replace/pop/back/clear
 *   - Auth guard：受保护路由若未登录，自动改跳 Login（带 redirectTo 参数）
 *   - getParams<T>()：当前栈顶 param 类型化读取
 *   - parseDeepLink：readmigo://book/:slug 等 cold-launch 链接解析
 *   - 路由历史：写入 AppStorage 供 analytics 消费
 *
 * 兼容旧 API：bind / get / push / replace / pop / popToRoot 全部保留。
 */
export class RouterService {
  private static stack: NavPathStack | null = null;

  static bind(stack: NavPathStack): void {
    RouterService.stack = stack;
    AppStorage.SetOrCreate<NavPathStack>(StoreKeys.APP_NAV_STACK, stack);
  }

  static get(): NavPathStack {
    if (!RouterService.stack) {
      const fromStorage = AppStorage.Get<NavPathStack>(StoreKeys.APP_NAV_STACK);
      if (fromStorage) {
        RouterService.stack = fromStorage;
      } else {
        RouterService.stack = new NavPathStack();
      }
    }
    return RouterService.stack;
  }

  /**
   * 命名路由 push。受保护路由 + 未登录会被劫持到 Login。
   * 同步版本：HSP 已加载时直接跳；未加载时可能短暂白屏。
   * 优先使用 navigate()（异步，确保 HSP 就绪后才入栈）。
   */
  static push(name: string, param?: object): void {
    if (RouterService.shouldRedirectToLogin(name)) {
      const loginParam: LoginRouteParams = { redirectTo: name, redirectParams: param };
      RouterService.get().pushPathByName(RoutePath.LOGIN, loginParam);
      RouterService.recordHistory(RoutePath.LOGIN);
      return;
    }
    RouterService.get().pushPathByName(name, param ?? null);
    RouterService.recordHistory(name);
  }

  /**
   * 异步路由导航：先等待目标 HSP 加载完成，再执行 push。
   * 若目标路由不需要 HSP（在 entry HAP 内），立即 push。
   * 若 HSP 加载失败，回调 onError（可选），不做路由跳转。
   */
  static async navigate(
    name: string,
    param?: object,
    onError?: (err: Error) => void,
  ): Promise<void> {
    const hspName = ROUTE_TO_HSP.get(name);
    if (hspName) {
      try {
        await ModuleLoader.getInstance().load(hspName);
      } catch (err) {
        if (onError) {
          onError(err instanceof Error ? err : new Error(String(err)));
        }
        return;
      }
    }
    RouterService.push(name, param);
  }

  static replace(name: string, param?: object): void {
    if (RouterService.shouldRedirectToLogin(name)) {
      const loginParam: LoginRouteParams = { redirectTo: name, redirectParams: param };
      RouterService.get().replacePathByName(RoutePath.LOGIN, loginParam);
      RouterService.recordHistory(RoutePath.LOGIN);
      return;
    }
    RouterService.get().replacePathByName(name, param ?? null);
    RouterService.recordHistory(name);
  }

  static pop(): void {
    RouterService.get().pop();
  }

  /** back() 是 pop() 的语义化别名。 */
  static back(): void {
    RouterService.pop();
  }

  static popToRoot(): void {
    RouterService.get().clear();
  }

  /** clear stack to root（语义化别名）。 */
  static clear(): void {
    RouterService.popToRoot();
  }

  /**
   * 取栈顶路由的 param。NavPathStack.getParamByIndex(stack.size - 1) 不一定每个 SDK 都暴露，
   * 这里走 getParamByName 兜底；调用方需自行知道当前栈顶名字。
   */
  static getParams<T>(routeName: string): T | null {
    const s = RouterService.get();
    const list = s.getParamByName(routeName);
    if (!list || list.length === 0) return null;
    return list[list.length - 1] as T;
  }

  // ---- Auth guard ----

  private static shouldRedirectToLogin(name: string): boolean {
    if (!AUTH_REQUIRED_ROUTES.has(name)) return false;
    return !UserStore.isAuthenticated();
  }

  /**
   * 登录成功后调用：若有 redirectTo，跳过去；否则回根。
   */
  static onLoginSuccess(): void {
    const param = RouterService.getParams<LoginRouteParams>(RoutePath.LOGIN);
    if (param && param.redirectTo) {
      RouterService.get().clear();
      RouterService.get().pushPathByName(param.redirectTo, param.redirectParams ?? null);
      RouterService.recordHistory(param.redirectTo);
    } else {
      RouterService.popToRoot();
    }
  }

  // ---- Deep link ----

  /**
   * 解析 readmigo://... URL。
   * 当前支持：
   *   readmigo://book/:slug                -> Reader { bookId: slug }
   *   readmigo://audiobook/:id             -> AudiobookPlayer { audiobookId: id }
   *   readmigo://library                   -> Library
   *   readmigo://discover                  -> Discover
   *   readmigo://me                        -> Me
   *   readmigo://notes                     -> Notes
   * Phase 4 会接入更多深度链接，结构保持一致。
   */
  static parseDeepLink(url: string): DeepLinkTarget | null {
    if (!url || !url.startsWith(DEEP_LINK_SCHEME)) return null;
    const path = url.substring(DEEP_LINK_SCHEME.length);
    const parts = path.split('/').filter((p) => p.length > 0);
    if (parts.length === 0) return null;
    const head = parts[0];
    if (head === 'book' && parts.length >= 2) {
      return { route: RoutePath.READER, params: { bookId: parts[1] } };
    }
    if (head === 'audiobook' && parts.length >= 2) {
      return { route: RoutePath.AUDIOBOOK_PLAYER, params: { audiobookId: parts[1] } };
    }
    if (head === 'library') return { route: RoutePath.LIBRARY, params: null };
    if (head === 'discover') return { route: RoutePath.DISCOVER, params: null };
    if (head === 'me') return { route: RoutePath.ME, params: null };
    if (head === 'notes') return { route: RoutePath.NOTES, params: null };
    return null;
  }

  /**
   * EntryAbility 在导航栈就绪后调用。auth-guard 同样生效。
   */
  static handleDeepLink(url: string): boolean {
    const target = RouterService.parseDeepLink(url);
    if (!target) return false;
    RouterService.push(target.route, target.params ?? undefined);
    return true;
  }

  // ---- History tracking ----

  private static recordHistory(route: string): void {
    const list = AppStorage.Get<HistoryEntry[]>(StoreKeys.APP_ROUTE_HISTORY) ?? [];
    list.push({ route, at: Date.now() });
    while (list.length > MAX_HISTORY) {
      list.shift();
    }
    AppStorage.SetOrCreate<HistoryEntry[]>(StoreKeys.APP_ROUTE_HISTORY, list);
  }

  static getHistory(): HistoryEntry[] {
    return AppStorage.Get<HistoryEntry[]>(StoreKeys.APP_ROUTE_HISTORY) ?? [];
  }

  static clearHistory(): void {
    AppStorage.SetOrCreate<HistoryEntry[]>(StoreKeys.APP_ROUTE_HISTORY, []);
  }
}
