import http from '@ohos.net.http';
import { ApiConfig } from './ApiConfig';
import { ResponseCache } from './ResponseCache';
import { UserStore } from '../../store/UserStore';
import { RouterService } from '../../core/router/RouterService';
import { RoutePath } from '../../core/router/RouteConstants';
import { StoreKeys } from '../../store/StoreKeys';
import { LocalizationManager } from '../../core/i18n/LocalizationManager';

/**
 * HTTP client based on @ohos.net.http.
 *
 * Features:
 * - 请求拦截器链：默认拦截器自动从 UserStore 取 Authorization
 * - 401 自动调用 /auth/refresh 刷新 token，再重放原请求一次；refresh 失败清空 UserStore + 跳 Login
 * - 自动重试：5xx / 网络错误指数退避（1s / 2s / 4s）
 * - 超时：每请求可配，默认 ApiConfig.timeoutMs（30s 兜底）
 * - 错误归一化：HTTP / 网络错误统一抛 ApiError(code, message, statusCode, details?)
 * - Loading 计数：写 AppStorage 'http_pending_count'，UI 可挂全局 spinner
 *
 * 兼容原 API：static get(path, query?), post(path, body?), put(path, body?), delete(path),
 * patch(path, body?) 现在都额外接受可选 `opts`。
 */

// ---------- Types ----------

export interface ApiResponse<T> {
  code: number;
  message: string;
  data: T;
}

export interface ApiErrorDetails {
  body?: string;
  cause?: string;
}

export class ApiError extends Error {
  code: number;
  /** HTTP status code（0 表示网络错误 / 未发出） */
  statusCode: number;
  /** 旧字段别名，保留供历史代码使用 */
  httpStatus: number;
  details?: ApiErrorDetails;
  constructor(code: number, message: string, statusCode: number, details?: ApiErrorDetails) {
    super(message);
    this.code = code;
    this.statusCode = statusCode;
    this.httpStatus = statusCode;
    this.details = details;
  }
}

export interface RequestOptions {
  method?: http.RequestMethod;
  headers?: Record<string, string>;
  body?: object;
  query?: Record<string, string | number>;
  /** ms, default ApiConfig.timeoutMs */
  timeoutMs?: number;
  /** 是否带 Authorization，默认 true */
  auth?: boolean;
  /** 重试次数，默认 2（共最多 3 次发起） */
  retries?: number;
  /** 跳过 401 refresh+retry，避免 refresh 自身死循环 */
  skipRefresh?: boolean;
}

interface InternalRequestContext {
  url: string;
  options: RequestOptions;
  headers: Record<string, string>;
}

export type RequestInterceptor = (ctx: InternalRequestContext) => Promise<void> | void;

// ---------- Loading state hook ----------

class LoadingCounter {
  private static count: number = 0;
  static inc(): void {
    LoadingCounter.count += 1;
    AppStorage.SetOrCreate<number>('http_pending_count', LoadingCounter.count);
  }
  static dec(): void {
    LoadingCounter.count = Math.max(0, LoadingCounter.count - 1);
    AppStorage.SetOrCreate<number>('http_pending_count', LoadingCounter.count);
  }
}

// ---------- Singleton ----------

export class HttpClient {
  /** 默认超时 30s（兜底，ApiConfig 优先） */
  private static readonly DEFAULT_TIMEOUT: number = 30000;

  private static interceptors: RequestInterceptor[] = [
    // 默认拦截器：注入 Authorization
    (ctx: InternalRequestContext) => {
      if (ctx.options.auth !== false) {
        const token = UserStore.getToken();
        if (token) {
          ctx.headers['Authorization'] = `Bearer ${token}`;
        }
      }
    },
  ];

  /** 是否正在刷新 token，避免并发请求触发多次 refresh */
  private static refreshing: Promise<string> | null = null;

  static addInterceptor(i: RequestInterceptor): void {
    HttpClient.interceptors.push(i);
  }

  static async request<T>(path: string, opts: RequestOptions = {}): Promise<T> {
    const ctx: InternalRequestContext = {
      url: HttpClient.buildUrl(path, opts.query),
      options: opts,
      headers: {
        'Content-Type': 'application/json',
        'Accept-Language': LocalizationManager.getAcceptLanguageHeader(),
        ...(opts.headers ?? {}),
      },
    };
    for (const i of HttpClient.interceptors) {
      await i(ctx);
    }
    const method = ctx.options.method ?? http.RequestMethod.GET;
    const isGet = method === http.RequestMethod.GET;
    const cacheKey = ResponseCache.keyFor(String(method), ctx.url);

    // 缓存读：GET 命中且未过期直接返回；解析失败回退网络。
    if (isGet) {
      const hit = await ResponseCache.get(cacheKey);
      if (hit) {
        try {
          return JSON.parse(hit.data) as T;
        } catch (_e) {
          // 缓存损坏，丢弃继续走网络
        }
      }
    }

    const result = await HttpClient.execute<T>(path, ctx, opts.retries ?? 2);

    // 缓存写：GET 成功落盘；mutating 清同 URL 前缀的 GET 缓存。
    if (isGet) {
      await ResponseCache.put(cacheKey, result);
    } else {
      await ResponseCache.invalidate(ResponseCache.keyFor('GET', ctx.url));
    }
    return result;
  }

  /** 真正执行请求 + 重试 + 401 处理 */
  private static async execute<T>(
    path: string,
    ctx: InternalRequestContext,
    retriesLeft: number,
  ): Promise<T> {
    LoadingCounter.inc();
    const httpRequest = http.createHttp();
    try {
      const timeoutMs = ctx.options.timeoutMs ?? ApiConfig.timeoutMs ?? HttpClient.DEFAULT_TIMEOUT;
      const resp = await httpRequest.request(ctx.url, {
        method: ctx.options.method ?? http.RequestMethod.GET,
        header: ctx.headers,
        extraData: ctx.options.body ? JSON.stringify(ctx.options.body) : undefined,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
      });
      return HttpClient.handleResponse<T>(resp);
    } catch (err) {
      const apiErr = err instanceof ApiError
        ? err
        : new ApiError(-1, (err as Error).message ?? 'network_error', 0,
            { cause: String(err) });

      // 401: 尝试 refresh + retry once
      if (apiErr.statusCode === 401 && !ctx.options.skipRefresh) {
        const refreshed = await HttpClient.tryRefresh();
        if (refreshed) {
          ctx.headers['Authorization'] = `Bearer ${refreshed}`;
          return HttpClient.execute<T>(path, ctx, 0); // refresh 后只重试一次
        }
        HttpClient.handleAuthFailure();
        throw apiErr;
      }

      // 5xx / 网络错误：指数退避重试
      const isTransient = apiErr.statusCode === 0
        || (apiErr.statusCode >= 500 && apiErr.statusCode < 600);
      if (isTransient && retriesLeft > 0) {
        const totalRetries = ctx.options.retries ?? 2;
        const attempt = totalRetries - retriesLeft; // 0,1,2...
        const delay = Math.pow(2, attempt) * 1000; // 1s, 2s, 4s
        await HttpClient.sleep(delay);
        return HttpClient.execute<T>(path, ctx, retriesLeft - 1);
      }

      throw apiErr;
    } finally {
      httpRequest.destroy();
      LoadingCounter.dec();
    }
  }

  // ---------- Convenience methods ----------

  static get<T>(path: string, query?: Record<string, string | number>, opts?: RequestOptions): Promise<T> {
    return HttpClient.request<T>(path, { ...(opts ?? {}), method: http.RequestMethod.GET, query });
  }

  static post<T>(path: string, body?: object, opts?: RequestOptions): Promise<T> {
    return HttpClient.request<T>(path, { ...(opts ?? {}), method: http.RequestMethod.POST, body });
  }

  static put<T>(path: string, body?: object, opts?: RequestOptions): Promise<T> {
    return HttpClient.request<T>(path, { ...(opts ?? {}), method: http.RequestMethod.PUT, body });
  }

  /**
   * PATCH —— 部分字段更新。@ohos.net.http 在 API 9+ 支持 PATCH 枚举；
   * 旧版本若缺失会回退到 POST + X-HTTP-Method-Override header。
   */
  static patch<T>(path: string, body?: object, opts?: RequestOptions): Promise<T> {
    const m = (http.RequestMethod as unknown as Record<string, http.RequestMethod>).PATCH
      ?? http.RequestMethod.POST;
    const overrideHeaders: Record<string, string> = m === http.RequestMethod.POST
      ? { 'X-HTTP-Method-Override': 'PATCH' }
      : {};
    return HttpClient.request<T>(path, {
      ...(opts ?? {}),
      method: m,
      body,
      headers: { ...overrideHeaders, ...(opts?.headers ?? {}) },
    });
  }

  static delete<T>(path: string, opts?: RequestOptions): Promise<T> {
    return HttpClient.request<T>(path, { ...(opts ?? {}), method: http.RequestMethod.DELETE });
  }

  // ---------- Internals ----------

  private static buildUrl(path: string, query?: Record<string, string | number>): string {
    const base = ApiConfig.baseUrl.replace(/\/$/, '');
    const p = path.startsWith('/') ? path : `/${path}`;
    if (!query || Object.keys(query).length === 0) {
      return `${base}${p}`;
    }
    const qs = Object.keys(query)
      .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(String(query[k]))}`)
      .join('&');
    return `${base}${p}?${qs}`;
  }

  private static handleResponse<T>(resp: http.HttpResponse): T {
    const status = resp.responseCode;
    const text = HttpClient.decodeBody(resp);

    if (status === 401) {
      throw new ApiError(401, 'unauthorized', 401, { body: text });
    }
    if (status < 200 || status >= 300) {
      let serverMsg = `http_${status}`;
      try {
        const j = JSON.parse(text) as ApiResponse<unknown>;
        if (j && typeof j.message === 'string') {
          serverMsg = j.message;
        }
      } catch (_e) {
        // ignore parse failure, keep default
      }
      throw new ApiError(status, serverMsg, status, { body: text });
    }

    if (!text) {
      // 204 / 空 body 也允许
      return undefined as unknown as T;
    }
    let parsed: ApiResponse<T>;
    try {
      parsed = JSON.parse(text) as ApiResponse<T>;
    } catch (_e) {
      throw new ApiError(-2, 'invalid_json', status, { body: text });
    }
    if (parsed.code !== 0 && parsed.code !== 200) {
      throw new ApiError(parsed.code, parsed.message ?? 'api_error', status);
    }
    return parsed.data;
  }

  private static decodeBody(resp: http.HttpResponse): string {
    if (typeof resp.result === 'string') {
      return resp.result;
    }
    try {
      return new TextDecoder('utf-8').decode(resp.result as ArrayBuffer);
    } catch (_e) {
      return '';
    }
  }

  /**
   * 尝试用 refreshToken 换新 accessToken。返回新 token 或 null（refresh 失败）。
   * 并发安全：多请求同时 401 时只发一次 refresh，其它共享 Promise。
   */
  private static async tryRefresh(): Promise<string | null> {
    if (HttpClient.refreshing) {
      try {
        return await HttpClient.refreshing;
      } catch (_e) {
        return null;
      }
    }
    const refreshToken = AppStorage.Get<string>(StoreKeys.USER_REFRESH_TOKEN);
    if (!refreshToken) {
      return null;
    }
    HttpClient.refreshing = HttpClient.doRefresh(refreshToken);
    try {
      return await HttpClient.refreshing;
    } catch (_e) {
      return null;
    } finally {
      HttpClient.refreshing = null;
    }
  }

  private static async doRefresh(refreshToken: string): Promise<string> {
    interface RefreshResp { token: string; refreshToken: string; }
    const res = await HttpClient.request<RefreshResp>('/auth/refresh', {
      method: http.RequestMethod.POST,
      body: { refreshToken },
      auth: false,
      skipRefresh: true,
      retries: 0,
    });
    UserStore.setToken(res.token, res.refreshToken);
    return res.token;
  }

  /**
   * 401 + refresh 失败：清空用户态，跳回登录页。
   */
  private static handleAuthFailure(): void {
    UserStore.clear();
    try {
      RouterService.replace(RoutePath.LOGIN);
    } catch (_e) {
      // RouterService 未绑定时（启动早期）忽略
    }
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(() => resolve(), ms));
  }
}
