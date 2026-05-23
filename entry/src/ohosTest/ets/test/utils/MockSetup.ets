// MockSetup.ets
// 集中管理 Phase 2 e2e 测试所需的 mock：
//   - AuthApi / BooksApi / AiApi    →  替换 static 方法 + record call args
//   - TtsService / TranslateService →  替换单例方法
//   - 网络在线/离线开关              →  通过 ProgressSync 入口 setOnlineForTest
//
// 设计要点：
//   - 不引入 jest/sinon —— Hypium 自身只暴露 expect，所以采用「保存原方法 → 替换 →
//     restoreAll() 还原」的轻量模式，避免破坏单例长期态。
//   - 每个测试文件 beforeEach 调 MockSetup.resetAll()，确保隔离。
//   - 真实业务代码不被 import 修改：mock 只在 ohosTest 模块内挂钩 static method。

import { AuthApi, LoginResult } from '../../../../main/ets/api/auth/AuthApi';
import { BooksApi } from '../../../../main/ets/api/books/BooksApi';
import { AiApi, ExplainWordPayload, SseHandlers } from '../../../../main/ets/api/ai/AiApi';
import { TtsService, TtsHandle, TtsSpeakOptions } from '../../../../main/ets/features/audiobook/service/TtsService';
import { TranslateService, TranslateResult } from '../../../../main/ets/features/ai-tools/service/TranslateService';
import { Book, BookListResponse } from '../../../../main/ets/model/Book';
import { Chapter, ChapterContent } from '../../../../main/ets/model/Chapter';

/** 调用记录：每个 mock 方法被调用时按时间顺序追加。 */
export interface CallRecord {
  api: string;
  method: string;
  args: unknown[];
  ts: number;
}

/** AuthApi mock 行为：可在每个 it 内调 MockSetup.setAuthBehavior() 覆盖。 */
export interface AuthMockBehavior {
  /** loginByCode 是否成功；false → 抛 ApiError(401) */
  loginSucceeds: boolean;
  /** refresh 是否成功；false → 触发 handleAuthFailure */
  refreshSucceeds: boolean;
  /** sendSmsCode 是否成功 */
  smsSendSucceeds: boolean;
}

export interface BooksMockBehavior {
  /** listBooks 返回的固定列表 */
  bookList: Book[];
  /** getChapterContent 是否模拟离线（true → 抛 network error） */
  offline: boolean;
  /** getChapterContent 失败次数（用于测试自动恢复） */
  failChapterTimes: number;
}

export interface AiMockBehavior {
  /** explainWordStream 是否在中途触发 onError */
  streamFails: boolean;
  /** 模拟 explainWord 同步返回的释义 */
  explainResponse: string;
}

export interface TtsMockBehavior {
  /** speak 是否抛错（模拟服务不可用） */
  speakFails: boolean;
  /** speak 返回的 mock handle 是否立刻 complete */
  autoComplete: boolean;
}

export class MockSetup {
  // ------ 调用记录 ------
  private static records: CallRecord[] = [];

  // ------ 行为开关 ------
  private static auth: AuthMockBehavior = MockSetup.defaultAuth();
  private static books: BooksMockBehavior = MockSetup.defaultBooks();
  private static ai: AiMockBehavior = MockSetup.defaultAi();
  private static tts: TtsMockBehavior = MockSetup.defaultTts();
  private static online: boolean = true;

  // ------ 原方法引用，restore 时回填 ------
  // 用 unknown 装载避免静态类型签名差异；replaceXxx 内部强转。
  private static originals: Map<string, unknown> = new Map<string, unknown>();

  // ─────────────────────────────────────────
  // 行为预设
  // ─────────────────────────────────────────

  static defaultAuth(): AuthMockBehavior {
    return { loginSucceeds: true, refreshSucceeds: true, smsSendSucceeds: true };
  }

  static defaultBooks(): BooksMockBehavior {
    return {
      bookList: [
        MockSetup.makeBook('book-1', 'jane-eyre', 'Jane Eyre'),
        MockSetup.makeBook('book-2', 'pride-prejudice', 'Pride and Prejudice'),
        MockSetup.makeBook('book-3', '1984', 'Nineteen Eighty-Four'),
      ],
      offline: false,
      failChapterTimes: 0,
    };
  }

  static defaultAi(): AiMockBehavior {
    return {
      streamFails: false,
      explainResponse: '{"word":"hello","definition":"a greeting","exampleEn":"Hello world"}',
    };
  }

  static defaultTts(): TtsMockBehavior {
    return { speakFails: false, autoComplete: true };
  }

  // ─────────────────────────────────────────
  // 公共 API
  // ─────────────────────────────────────────

  /** 一次性安装全部 mock。每个测试套件 beforeAll 调一次即可。 */
  static installAll(): void {
    MockSetup.installAuth();
    MockSetup.installBooks();
    MockSetup.installAi();
    MockSetup.installTts();
    MockSetup.installTranslate();
  }

  /** 还原所有被替换的方法，避免污染下一个测试套件。 */
  static restoreAll(): void {
    MockSetup.originals.forEach((fn, key) => {
      const [api, method] = key.split('.');
      // 反射式写回：unknown 强转为 any 后赋值，HarmonyOS ArkTS 编译器允许。
      const target = MockSetup.resolveTarget(api);
      if (target) {
        (target as Record<string, unknown>)[method] = fn;
      }
    });
    MockSetup.originals.clear();
  }

  /** 重置行为开关 + 调用记录到默认值（每个 it 之前调）。 */
  static resetAll(): void {
    MockSetup.auth = MockSetup.defaultAuth();
    MockSetup.books = MockSetup.defaultBooks();
    MockSetup.ai = MockSetup.defaultAi();
    MockSetup.tts = MockSetup.defaultTts();
    MockSetup.online = true;
    MockSetup.records = [];
  }

  static setAuthBehavior(b: Partial<AuthMockBehavior>): void {
    MockSetup.auth = { ...MockSetup.auth, ...b };
  }

  static setBooksBehavior(b: Partial<BooksMockBehavior>): void {
    MockSetup.books = { ...MockSetup.books, ...b };
  }

  static setAiBehavior(b: Partial<AiMockBehavior>): void {
    MockSetup.ai = { ...MockSetup.ai, ...b };
  }

  static setTtsBehavior(b: Partial<TtsMockBehavior>): void {
    MockSetup.tts = { ...MockSetup.tts, ...b };
  }

  static setOnline(v: boolean): void {
    MockSetup.online = v;
  }

  static isOnline(): boolean {
    return MockSetup.online;
  }

  static getRecords(): CallRecord[] {
    return MockSetup.records.slice();
  }

  static getCallsFor(api: string, method: string): CallRecord[] {
    return MockSetup.records.filter((r) => r.api === api && r.method === method);
  }

  // ─────────────────────────────────────────
  // 单 API 安装函数（保留供单测细粒度控制）
  // ─────────────────────────────────────────

  static installAuth(): void {
    const target = AuthApi as unknown as Record<string, unknown>;
    MockSetup.save('AuthApi.sendSmsCode', target['sendSmsCode']);
    MockSetup.save('AuthApi.loginByCode', target['loginByCode']);
    MockSetup.save('AuthApi.refresh', target['refresh']);

    target['sendSmsCode'] = (phone: string): Promise<void> => {
      MockSetup.record('AuthApi', 'sendSmsCode', [phone]);
      return MockSetup.auth.smsSendSucceeds
        ? Promise.resolve()
        : Promise.reject(new Error('sms_rate_limited'));
    };

    target['loginByCode'] = (phone: string, code: string): Promise<LoginResult> => {
      MockSetup.record('AuthApi', 'loginByCode', [phone, code]);
      if (!MockSetup.auth.loginSucceeds) {
        return Promise.reject(new Error('invalid_code'));
      }
      const result: LoginResult = {
        token: 'mock-access-token',
        refreshToken: 'mock-refresh-token',
        userId: 'user-1',
        nickname: '测试用户',
      };
      return Promise.resolve(result);
    };

    target['refresh'] = (refreshToken: string): Promise<{ token: string; refreshToken: string }> => {
      MockSetup.record('AuthApi', 'refresh', [refreshToken]);
      if (!MockSetup.auth.refreshSucceeds) {
        return Promise.reject(new Error('refresh_failed'));
      }
      return Promise.resolve({ token: 'mock-access-token-2', refreshToken: 'mock-refresh-token-2' });
    };
  }

  static installBooks(): void {
    const target = BooksApi as unknown as Record<string, unknown>;
    MockSetup.save('BooksApi.listBooks', target['listBooks']);
    MockSetup.save('BooksApi.getChapters', target['getChapters']);
    MockSetup.save('BooksApi.getChapterContent', target['getChapterContent']);

    target['listBooks'] = (): Promise<BookListResponse> => {
      MockSetup.record('BooksApi', 'listBooks', []);
      const items = MockSetup.books.bookList;
      const resp: BookListResponse = {
        items,
        page: 1,
        limit: items.length,
        total: items.length,
        hasMore: false,
      };
      return Promise.resolve(resp);
    };

    target['getChapters'] = (slug: string): Promise<Chapter[]> => {
      MockSetup.record('BooksApi', 'getChapters', [slug]);
      const list: Chapter[] = [];
      for (let i = 0; i < 5; i++) {
        list.push({
          id: `${slug}-ch-${i}`,
          index: i,
          title: `Chapter ${i + 1}`,
          wordCount: 1000,
        });
      }
      return Promise.resolve(list);
    };

    target['getChapterContent'] = (slug: string, index: number): Promise<ChapterContent> => {
      MockSetup.record('BooksApi', 'getChapterContent', [slug, index]);
      if (!MockSetup.online || MockSetup.books.offline) {
        return Promise.reject(new Error('network_unreachable'));
      }
      if (MockSetup.books.failChapterTimes > 0) {
        MockSetup.books.failChapterTimes -= 1;
        return Promise.reject(new Error('chapter_fetch_failed'));
      }
      const content: ChapterContent = {
        bookId: `id-of-${slug}`,
        bookSlug: slug,
        index,
        title: `Chapter ${index + 1}`,
        html: `<p>Mock chapter ${index} content for ${slug}.</p>`,
        css: '',
        wordCount: 1000,
        prevIndex: index > 0 ? index - 1 : undefined,
        nextIndex: index + 1,
      };
      return Promise.resolve(content);
    };
  }

  static installAi(): void {
    const target = AiApi as unknown as Record<string, unknown>;
    MockSetup.save('AiApi.explainWord', target['explainWord']);
    MockSetup.save('AiApi.explainWordStream', target['explainWordStream']);

    target['explainWord'] = (payload: ExplainWordPayload): Promise<{
      raw: string;
      word?: string;
      definition?: string;
      exampleEn?: string;
    }> => {
      MockSetup.record('AiApi', 'explainWord', [payload.word, payload.bookId ?? '']);
      return Promise.resolve({
        raw: MockSetup.ai.explainResponse,
        word: payload.word,
        definition: 'mock definition',
        exampleEn: `Use ${payload.word} like this.`,
      });
    };

    target['explainWordStream'] = (payload: ExplainWordPayload, handlers: SseHandlers): (() => void) => {
      MockSetup.record('AiApi', 'explainWordStream', [payload.word]);
      // 同步派发 chunks 模拟流式：测试断言不等待 timer。
      const tid = setTimeout(() => {
        if (MockSetup.ai.streamFails) {
          handlers.onError?.(new Error('sse_stream_broken'));
          return;
        }
        handlers.onChunk('mock');
        handlers.onChunk(' delta');
        handlers.onDone?.();
      }, 0) as unknown as number;
      // 返回 stop()
      return (): void => {
        clearTimeout(tid);
      };
    };
  }

  static installTts(): void {
    const svc = TtsService.getInstance();
    const target = svc as unknown as Record<string, unknown>;
    MockSetup.save('TtsService.speak', svc.speak.bind(svc));
    // 注意：TtsService 为单例，bind 之后赋值原方法。

    target['speak'] = async (text: string, opts?: TtsSpeakOptions): Promise<TtsHandle> => {
      MockSetup.record('TtsService', 'speak', [text.length, opts?.bookId ?? '']);
      if (MockSetup.tts.speakFails) {
        throw new Error('tts_unavailable');
      }
      const handle: TtsHandle = {
        id: 'mock-tts-handle',
        status: MockSetup.tts.autoComplete ? 'completed' : 'playing',
        text,
        currentCharIndex: MockSetup.tts.autoComplete ? text.length : 0,
        cancel: (): void => {},
        pause: (): void => {},
        resume: (): void => {},
        onProgress: (): void => {},
        onComplete: (cb): void => {
          if (MockSetup.tts.autoComplete) cb();
        },
        onError: (): void => {},
      };
      return handle;
    };
  }

  static installTranslate(): void {
    const svc = TranslateService.getInstance();
    const target = svc as unknown as Record<string, unknown>;
    MockSetup.save('TranslateService.translate', svc.translate.bind(svc));

    target['translate'] = async (
      text: string,
      sourceLang: string,
      targetLang: string,
    ): Promise<TranslateResult> => {
      MockSetup.record('TranslateService', 'translate', [text, sourceLang, targetLang]);
      const result: TranslateResult = {
        translated: `[${targetLang}] ${text}`,
        sourceLang,
        targetLang,
        provider: 'server',
        fromCache: false,
      };
      return result;
    };
  }

  // ─────────────────────────────────────────
  // 内部工具
  // ─────────────────────────────────────────

  private static save(key: string, original: unknown): void {
    if (!MockSetup.originals.has(key)) {
      MockSetup.originals.set(key, original);
    }
  }

  private static record(api: string, method: string, args: unknown[]): void {
    MockSetup.records.push({ api, method, args, ts: Date.now() });
  }

  private static resolveTarget(api: string): unknown {
    if (api === 'AuthApi') return AuthApi;
    if (api === 'BooksApi') return BooksApi;
    if (api === 'AiApi') return AiApi;
    if (api === 'TtsService') return TtsService.getInstance();
    if (api === 'TranslateService') return TranslateService.getInstance();
    return null;
  }

  private static makeBook(id: string, slug: string, title: string): Book {
    return {
      id,
      slug,
      title,
      author: 'Test Author',
      coverUrl: `https://cdn.test/${slug}.jpg`,
      language: 'en',
      cefrLevel: 'B1',
    } as Book;
  }
}
