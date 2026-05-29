import http from '@ohos.net.http';
import { ApiConfig } from './ApiConfig';
import { UserStore } from '../../store/UserStore';

/**
 * SSE 消费器，基于 @ohos.net.http requestInStream + 数据回调。
 * Harmony 的 http 不像浏览器原生支持 EventSource，必须自己解析 SSE 帧：
 *   - 每条事件由两次 \n\n 分隔
 *   - data: 行的内容是负载（同一事件可能有多个 data: 行）
 *
 * 重试策略：1 次初始 + 1 次 retry（仅网络错误 / 5xx，4xx 不重试）。
 *
 * 用法：
 *   const stop = SseClient.stream(path, body, {
 *     onMessage: (data) => { ... },
 *     onDone: () => { ... },
 *     onError: (e) => { ... },
 *   });
 *   stop(); // 中止
 */
export interface SseHandlers {
  onMessage: (data: string) => void;
  onDone?: () => void;
  onError?: (err: Error) => void;
}

export class SseClient {
  static stream(path: string, body: object, handlers: SseHandlers): () => void {
    let aborted = false;
    let currentReq: http.HttpRequest | null = null;

    const attempt = (retriesLeft: number): void => {
      if (aborted) return;

      const url = SseClient.buildUrl(path);
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Accept-Language': 'zh-CN',
      };
      const token = UserStore.getToken();
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const req = http.createHttp();
      currentReq = req;
      let buffer = '';
      const decoder = new TextDecoder('utf-8');

      req.on('dataReceive', (chunk: ArrayBuffer) => {
        if (aborted) return;
        buffer += decoder.decode(chunk, { stream: true });
        let idx = buffer.indexOf('\n\n');
        while (idx >= 0) {
          const event = buffer.slice(0, idx);
          buffer = buffer.slice(idx + 2);
          SseClient.handleEvent(event, handlers);
          idx = buffer.indexOf('\n\n');
        }
      });

      req.on('dataEnd', () => {
        if (aborted) return;
        if (buffer.length > 0) {
          SseClient.handleEvent(buffer, handlers);
          buffer = '';
        }
        handlers.onDone?.();
        req.destroy();
      });

      req.requestInStream(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        connectTimeout: 30_000,
        readTimeout: 60_000,
      }).then((statusCode: number) => {
        if (aborted) return;
        if (statusCode >= 400 && statusCode < 500) {
          // 4xx: no retry
          handlers.onError?.(new Error(`http_${statusCode}`));
          req.destroy();
        } else if (statusCode < 200 || statusCode >= 300) {
          // 5xx: retry once
          req.destroy();
          if (retriesLeft > 0) {
            attempt(retriesLeft - 1);
          } else {
            handlers.onError?.(new Error(`http_${statusCode}`));
          }
        }
      }).catch((err: Error) => {
        req.destroy();
        if (aborted) return;
        // Network error: retry once
        if (retriesLeft > 0) {
          attempt(retriesLeft - 1);
        } else {
          handlers.onError?.(err);
        }
      });
    };

    attempt(1);

    return () => {
      aborted = true;
      currentReq?.destroy();
    };
  }

  private static handleEvent(rawEvent: string, handlers: SseHandlers): void {
    const lines = rawEvent.split('\n');
    const dataParts: string[] = [];
    for (const line of lines) {
      if (line.startsWith('data:')) {
        dataParts.push(line.slice(5).trimStart());
      }
    }
    if (dataParts.length === 0) return;
    const data = dataParts.join('\n');
    if (data === '[DONE]') {
      handlers.onDone?.();
      return;
    }
    handlers.onMessage(data);
  }

  private static buildUrl(path: string): string {
    const base = ApiConfig.baseUrl.replace(/\/$/, '');
    const p = path.startsWith('/') ? path : `/${path}`;
    return `${base}${p}`;
  }
}
