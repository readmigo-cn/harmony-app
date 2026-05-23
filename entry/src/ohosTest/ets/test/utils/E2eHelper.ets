// E2eHelper.ets
// W20-C5 — 集中工具集，给 FullFlow.test.ets 22 个 it 提供共用桩件。
//
// 与 MockSetup 的分工：
//   - MockSetup     仅替换 service 层 static method、记录调用次数。
//   - E2eHelper     更高层，封装「常用业务序列」：登录态注水、书架预填、模拟付款、
//                   切换网络、抓快照、模拟设备形态切换、ModuleLoader 注入。
//
// 设计原则：
//   1. 不直接 import UIAbility / Navigator —— Hypium 在 CI 拉不起 UI，所有 UI 行为
//      退化为 AppStorage / store 写入断言。
//   2. 所有方法同步可调；需要时间的（network / payment）走 Promise 但内部 setTimeout(0)。
//   3. 提供 captureScreenshot 占位——返回 base64 字符串方便快照对比；W22 引入真实
//      driver 截图后再替换实现。

import { AuthApi, LoginResult } from '../../../../main/ets/api/auth/AuthApi';
import { BooksApi } from '../../../../main/ets/api/books/BooksApi';
import { UserStore } from '../../../../main/ets/store/UserStore';
import { ReadingStore } from '../../../../main/ets/store/ReadingStore';
import { StoreKeys } from '../../../../main/ets/store/StoreKeys';
import { ModuleLoader, ModuleName, registerDefaultModules } from '../../../../main/ets/core/dynamic/ModuleLoader';
import { MockSetup } from './MockSetup';

/** 模拟付款的输入。 */
export interface PaymentRequest {
  productId: string;
  amountCents: number;
  /** 期望结果：success / failed / cancelled。 */
  outcome: 'success' | 'failed' | 'cancelled';
}

/** 模拟付款的输出。 */
export interface PaymentResult {
  productId: string;
  status: 'success' | 'failed' | 'cancelled';
  txId?: string;
  error?: string;
  durationMs: number;
}

/** 简易快照：当前 AppStorage 关键字段 + 调用统计。 */
export interface E2eSnapshot {
  ts: number;
  authenticated: boolean;
  currentBookId: string;
  bookshelfSize: number;
  totalCalls: number;
  /** 仅占位：W22 接入 driver 后填真实 PNG base64。 */
  screenshotBase64?: string;
}

/** 设备形态枚举（W14 / W15 复用）。 */
export type DeviceForm = 'phone' | 'tablet' | 'tv' | 'car' | 'watch' | 'fold-open' | 'fold-closed';

export class E2eHelper {
  /** 默认登录用账号，统一用同一个，方便断言比对。 */
  static readonly DEFAULT_PHONE: string = '13800001234';
  static readonly DEFAULT_SMS_CODE: string = '123456';
  static readonly DEFAULT_BOOK_ID: string = 'book-1';
  static readonly DEFAULT_BOOK_SLUG: string = 'jane-eyre';

  // ────────────────────────────────────────────────
  // 1. Auth / 登录态注水
  // ────────────────────────────────────────────────

  /**
   * 一行设置登录态——内部调 mock AuthApi.loginByCode，写 UserStore。
   * 适合「我只想测后续业务，不关心登录细节」的 it 用。
   */
  static async setupAuth(phone: string = E2eHelper.DEFAULT_PHONE): Promise<LoginResult> {
    const result = await AuthApi.loginByCode(phone, E2eHelper.DEFAULT_SMS_CODE);
    UserStore.setAuth(result.token, result.refreshToken, result.userId, phone);
    return result;
  }

  /** 强制清空登录态（避免上一个 it 泄漏）。 */
  static clearAuth(): void {
    UserStore.clear();
  }

  /** 是否已登录（断言糖）。 */
  static isAuthed(): boolean {
    return UserStore.isAuthenticated();
  }

  // ────────────────────────────────────────────────
  // 2. 书架预填
  // ────────────────────────────────────────────────

  /**
   * 预填书架：调用 mock BooksApi.listBooks，写 ReadingStore.currentBook。
   * 默认走 MockSetup.defaultBooks() 的 3 本书。
   */
  static async seedBookshelf(currentSlug: string = E2eHelper.DEFAULT_BOOK_SLUG): Promise<number> {
    const list = await BooksApi.listBooks({ page: 1, limit: 20 });
    const found = list.items.find((b) => b.slug === currentSlug);
    if (found) {
      ReadingStore.setCurrentBook(found.id, found.slug, found.title, found.coverUrl ?? '');
    }
    AppStorage.SetOrCreate<number>('bookshelf_size', list.items.length);
    return list.items.length;
  }

  /** 当前书架大小（从 AppStorage 读，默认 0）。 */
  static getBookshelfSize(): number {
    return AppStorage.Get<number>('bookshelf_size') ?? 0;
  }

  // ────────────────────────────────────────────────
  // 3. 支付模拟
  // ────────────────────────────────────────────────

  /**
   * 模拟一次 IAP 流程。不调用真实 IAPService（W17 测试已覆盖单点），仅写
   * AppStorage 让上层 paywall 状态机推进。
   */
  static simulatePayment(req: PaymentRequest): Promise<PaymentResult> {
    const t0 = Date.now();
    return new Promise<PaymentResult>((resolve) => {
      setTimeout(() => {
        const tx = `mock-tx-${req.productId}-${t0}`;
        if (req.outcome === 'success') {
          AppStorage.SetOrCreate<string>('iap_last_tx_id', tx);
          AppStorage.SetOrCreate<string>('subscription_active_product', req.productId);
          AppStorage.SetOrCreate<boolean>('subscription_pro', true);
        } else if (req.outcome === 'failed') {
          AppStorage.SetOrCreate<string>('iap_last_error', 'mock_payment_failed');
        }
        const result: PaymentResult = {
          productId: req.productId,
          status: req.outcome,
          txId: req.outcome === 'success' ? tx : undefined,
          error: req.outcome === 'failed' ? 'mock_payment_failed' : undefined,
          durationMs: Date.now() - t0,
        };
        resolve(result);
      }, 0);
    });
  }

  // ────────────────────────────────────────────────
  // 4. 网络模拟
  // ────────────────────────────────────────────────

  /**
   * 切换网络在线状态（影响 BooksApi.getChapterContent 等 mock 行为）。
   * 同时把 AppStorage 的 network_online 写一份，方便业务侧读到。
   */
  static setOnline(online: boolean): void {
    MockSetup.setOnline(online);
    AppStorage.SetOrCreate<boolean>('network_online', online);
  }

  /** 模拟 N 次网络抖动：每次 toggle 间隔 0ms（同步），便于 retry 测试。 */
  static flapNetwork(times: number = 3): void {
    for (let i = 0; i < times; i++) {
      E2eHelper.setOnline(false);
      E2eHelper.setOnline(true);
    }
  }

  /** 模拟「关键 API 失败 N 次再恢复」场景（用于 retry / 退避验证）。 */
  static failChapterFetchTimes(times: number): void {
    MockSetup.setBooksBehavior({ failChapterTimes: times });
  }

  // ────────────────────────────────────────────────
  // 5. 设备形态切换（W14 / W15 / W18）
  // ────────────────────────────────────────────────

  /**
   * 把当前设备形态写到 AppStorage，触发监听该 key 的组件重渲染。
   * 真实 BreakpointController 在运行时由 displayManager 推送，CI 内通过这里直写。
   */
  static setDeviceForm(form: DeviceForm): void {
    AppStorage.SetOrCreate<string>('device_form', form);
    if (form === 'tablet') {
      AppStorage.SetOrCreate<string>('breakpoint', 'lg');
    } else if (form === 'fold-open') {
      AppStorage.SetOrCreate<string>('fold_status', 'expanded');
    } else if (form === 'fold-closed') {
      AppStorage.SetOrCreate<string>('fold_status', 'folded');
    } else {
      AppStorage.SetOrCreate<string>('breakpoint', 'sm');
    }
  }

  static getDeviceForm(): DeviceForm {
    return (AppStorage.Get<string>('device_form') ?? 'phone') as DeviceForm;
  }

  // ────────────────────────────────────────────────
  // 6. ModuleLoader 测试桩
  // ────────────────────────────────────────────────

  /** 安装一组默认模块到 ModuleLoader，便于 W20 模块加载测试。 */
  static installModuleLoader(): ModuleLoader {
    const loader = ModuleLoader.getInstance();
    loader.resetForTest();
    registerDefaultModules(loader);
    return loader;
  }

  /** 直接注入 stub 实例（不触发真实工厂）。 */
  static stubModule(name: ModuleName, instance: unknown): void {
    ModuleLoader.getInstance().registerStub(name, instance);
  }

  // ────────────────────────────────────────────────
  // 7. 快照 / 截图
  // ────────────────────────────────────────────────

  /**
   * 抓一份当前测试上下文快照。screenshotBase64 是占位：
   * - W20 阶段返回 'placeholder'；
   * - W22 自托管 OHOS runner 上线后用 driver.captureScreen 替换。
   */
  static captureScreenshot(label: string = 'snapshot'): E2eSnapshot {
    return {
      ts: Date.now(),
      authenticated: UserStore.isAuthenticated(),
      currentBookId: AppStorage.Get<string>(StoreKeys.READING_CURRENT_BOOK) ?? '',
      bookshelfSize: E2eHelper.getBookshelfSize(),
      totalCalls: MockSetup.getRecords().length,
      screenshotBase64: `placeholder:${label}`,
    };
  }

  // ────────────────────────────────────────────────
  // 8. 通用 reset
  // ────────────────────────────────────────────────

  /** 在 beforeEach 调用：清掉 store + AppStorage 关键字段 + ModuleLoader。 */
  static resetWorld(): void {
    MockSetup.resetAll();
    UserStore.clear();
    ModuleLoader.getInstance().resetForTest();
    // 关键 AppStorage key 清掉，防止上轮 it 数据泄漏
    AppStorage.SetOrCreate<boolean>(StoreKeys.APP_FIRST_LAUNCH, true);
    AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_BOOK, '');
    AppStorage.SetOrCreate<number>('bookshelf_size', 0);
    AppStorage.SetOrCreate<boolean>('subscription_pro', false);
    AppStorage.SetOrCreate<string>('device_form', 'phone');
    AppStorage.SetOrCreate<boolean>('network_online', true);
  }

  /** 等待若干毫秒（对 mock setTimeout(0) 派发的 stream 回调最实用）。 */
  static wait(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(() => resolve(), ms));
  }
}
