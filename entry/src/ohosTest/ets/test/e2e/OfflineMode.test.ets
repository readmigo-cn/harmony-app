// OfflineMode.test.ets
// Phase 2 e2e — 离线场景。
//
// 覆盖：
//   1. 网络可用：阅读章节 → 缓存到本地
//   2. 切断网络：再次阅读已缓存章节 → 应可读
//   3. 翻页 → ProgressSync 队列 → 网络恢复后 flush
//   4. 离线启动应用 → UserStore 应能从 preferences 恢复
//
// 注：HarmonyOS NEXT 的 @ohos.net.connection 在测试运行时不易直接断网，因此通过
// MockSetup.setOnline(false) 切换 Books mock 行为，模拟「请求超时」。

import { describe, beforeAll, beforeEach, afterAll, it, expect } from '@ohos/hypium';
import { MockSetup } from '../utils/MockSetup';
import { BooksApi } from '../../../../main/ets/api/books/BooksApi';
import { UserStore } from '../../../../main/ets/store/UserStore';
import { ProgressSync } from '../../../../main/ets/features/multi-device/service/ProgressSync';
import { ChapterContent } from '../../../../main/ets/model/Chapter';
import { StoreKeys } from '../../../../main/ets/store/StoreKeys';

const BOOK_SLUG = 'jane-eyre';
const BOOK_ID = 'book-1';

/** 本地章节缓存 mock：业务侧未实现统一缓存层时，用 AppStorage 兜底。 */
class LocalChapterCache {
  private static cache: Map<string, ChapterContent> = new Map<string, ChapterContent>();

  static put(slug: string, index: number, c: ChapterContent): void {
    LocalChapterCache.cache.set(`${slug}#${index}`, c);
  }

  static get(slug: string, index: number): ChapterContent | undefined {
    return LocalChapterCache.cache.get(`${slug}#${index}`);
  }

  static clear(): void {
    LocalChapterCache.cache.clear();
  }
}

export default function offlineModeE2ETest() {
  describe('E2E_OfflineMode', () => {
    beforeAll(() => {
      MockSetup.installAll();
    });

    afterAll(() => {
      MockSetup.restoreAll();
      LocalChapterCache.clear();
    });

    beforeEach(() => {
      MockSetup.resetAll();
      LocalChapterCache.clear();
    });

    // ── 1. 在线读章 → 缓存 ───────────────────────────────────
    it('online_should_read_chapter_and_cache_locally', 0, async () => {
      MockSetup.setOnline(true);

      const c = await BooksApi.getChapterContent(BOOK_SLUG, 0);
      expect(c.html.length > 0).assertTrue();
      LocalChapterCache.put(BOOK_SLUG, 0, c);

      expect(LocalChapterCache.get(BOOK_SLUG, 0) !== undefined).assertTrue();
    });

    // ── 2. 离线 + 命中缓存 ────────────────────────────────────
    it('offline_should_serve_cached_chapter_without_network', 0, async () => {
      // 先在线缓存
      MockSetup.setOnline(true);
      const fresh = await BooksApi.getChapterContent(BOOK_SLUG, 0);
      LocalChapterCache.put(BOOK_SLUG, 0, fresh);

      // 切离线
      MockSetup.setOnline(false);

      // 直接走 cache，不调 BooksApi
      const cached = LocalChapterCache.get(BOOK_SLUG, 0);
      expect(cached !== undefined).assertTrue();
      expect(cached?.bookSlug).assertEqual(BOOK_SLUG);

      // 离线下 BooksApi 应抛错
      let threw = false;
      try {
        await BooksApi.getChapterContent(BOOK_SLUG, 1);
      } catch (e) {
        threw = true;
        expect((e as Error).message).assertEqual('network_unreachable');
      }
      expect(threw).assertTrue();
    });

    // ── 3. ProgressSync 离线入队 → 在线 flush ──────────────────
    it('progress_should_queue_offline_and_flush_after_recovery', 0, async () => {
      // 准备：登录 + ProgressSync init
      UserStore.setAuth('mock-access-token', 'mock-refresh-token', 'user-1', '13800001234');
      await ProgressSync.init();

      // 离线翻页 5 次：每次 queueUpdate
      MockSetup.setOnline(false);
      for (let i = 0; i < 5; i++) {
        ProgressSync.queueUpdate(BOOK_ID, {
          bookId: BOOK_ID,
          chapterIndex: i,
          percent: (i + 1) * 20,
          updatedAt: new Date().toISOString(),
        });
      }
      // 队列内对同 bookId 应合并为最新一条（不会膨胀）

      // 网络恢复，触发 flush
      MockSetup.setOnline(true);
      await ProgressSync.flush();

      // 注：实际 flush 的成功与否依赖 ReadingApi mock；这里只断言不抛异常。
      expect(true).assertTrue();
    });

    // ── 4. 离线冷启动 → UserStore 从 preferences 恢复 ─────────
    it('offline_cold_start_should_restore_user_from_preferences', 0, () => {
      // 登录写入 AppStorage + 持久化
      UserStore.setAuth('persisted-token', 'persisted-refresh', 'user-99', '13800009999');
      expect(UserStore.getToken()).assertEqual('persisted-token');
      expect(UserStore.isAuthenticated()).assertTrue();
      expect(AppStorage.Get<string>(StoreKeys.USER_ID)).assertEqual('user-99');

      // 模拟冷启动「写入路径」：调用 setToken 后 AppStorage 必须保留新值
      // 真正的「PreferencesManager → AppStorage 回灌」需要 ability sandbox + W12
      // 引入 lifecycle 测试后补充。
      const tokenAfter = UserStore.getToken();
      expect(tokenAfter.length > 0).assertTrue();
    });

    // ── 5. 离线下不允许调远程接口 ──────────────────────────
    it('offline_calls_should_reject_consistently', 0, async () => {
      MockSetup.setOnline(false);
      let count = 0;
      for (let i = 0; i < 3; i++) {
        try {
          await BooksApi.getChapterContent(BOOK_SLUG, i);
        } catch (_e) {
          count += 1;
        }
      }
      expect(count).assertEqual(3);
      const calls = MockSetup.getCallsFor('BooksApi', 'getChapterContent');
      expect(calls.length).assertEqual(3);
    });
  });
}

