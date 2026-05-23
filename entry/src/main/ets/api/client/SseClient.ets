import http from '@ohos.net.http';
import { ApiConfig } from './ApiConfig';
import { UserStore } from '../../store/UserStore';

/**
 * SSE 消费器，基于 @ohos.net.http requestInStream + 数据回调。
 * Harmony 的 http 不像浏览器原生支持 EventSource，必须自己解析 SSE 帧：
 *   - 每条事件由两次 \n\n 分隔
 *   - data: 行的内容是负载（同一事件可能有多个 data: 行）
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
    const url = SseClient.buildUrl(path);
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'Accept-Language': 'zh-CN',
    };
    const token = UserStore.getToken();
    if (token) headers['Authorization'] = `Bearer ${token}`;

    const req = http.createHttp();
    let buffer = '';
    let aborted = false;
    const decoder = new TextDecoder('utf-8');

    req.on('dataReceive', (chunk: ArrayBuffer) => {
      if (aborted) return;
      buffer += decoder.decode(chunk, { stream: true });
      // SSE 事件用 \n\n 分隔
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

    req.on('headersReceive', (_h: object) => {
      // 仅占位，后续可读 status code
    });

    req.requestInStream(url, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: JSON.stringify(body),
      connectTimeout: 30_000,
      readTimeout: 60_000,
    }).then((statusCode: number) => {
      if (statusCode < 200 || statusCode >= 300) {
        handlers.onError?.(new Error(`http_${statusCode}`));
        req.destroy();
      }
    }).catch((err: Error) => {
      if (!aborted) handlers.onError?.(err);
      req.destroy();
    });

    return () => {
      aborted = true;
      req.destroy();
    };
  }

  private static handleEvent(rawEvent: string, handlers: SseHandlers): void {
    // 一个 event 可能包含多行；只关心 data: 开头的
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
