/**
 * API base URL 三环境切换。运行模式从 BuildProfile 注入或硬编码。
 */
export type ApiEnv = 'dev' | 'staging' | 'prod';

export class ApiConfig {
  // 默认 dev：连本地 docker-compose 起的 server-cn (PORT=3000)
  // 真机调试需改为局域网 IP
  static readonly env: ApiEnv = 'dev';

  static readonly baseUrls: Record<ApiEnv, string> = {
    dev: 'http://10.0.2.2:3000/api/v1',
    staging: 'https://api-staging.readmigo.cn/api/v1',
    prod: 'https://api.readmigo.cn/api/v1',
  };

  static readonly timeoutMs: number = 15000;

  /**
   * HTTP 响应缓存配置。对齐 iOS URLCache（20MB 内存 / 100MB 磁盘 / 默认 5min TTL）。
   * 默认关闭（enabled=false），逐端点灰度后再启用。
   */
  static readonly cache: {
    enabled: boolean;
    memBytes: number;
    diskBytes: number;
    defaultTtlMs: number;
  } = {
    enabled: false,
    memBytes: 20 * 1024 * 1024,
    diskBytes: 100 * 1024 * 1024,
    defaultTtlMs: 5 * 60 * 1000,
  };

  static get baseUrl(): string {
    return ApiConfig.baseUrls[ApiConfig.env];
  }
}
