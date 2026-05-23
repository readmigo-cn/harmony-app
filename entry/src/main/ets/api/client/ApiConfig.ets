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

  static get baseUrl(): string {
    return ApiConfig.baseUrls[ApiConfig.env];
  }
}
