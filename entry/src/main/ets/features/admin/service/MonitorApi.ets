/**
 * 监控仪表板 API 调用服务
 *
 * 负责与后端通信，获取：
 * - 实时聚合指标数据
 * - 崩溃列表详情
 * - 当前告警列表
 */

import { http } from '@kit.NetworkKit';

export interface DashboardMetricsRequest {
  period: 'last_1h' | 'last_24h' | 'last_7d';
}

export interface DashboardMetricsResponse {
  dau: number;                    // 日活跃用户
  activeSessions: number;         // 当前活跃会话数
  crashRate: number;              // 崩溃率 (0-1, 浮点数)
  apiErrorRate: number;           // API 错误率 (0-1, 浮点数)
  registrationConversion: number; // 注册转化率 (0-1)
  paymentConversion: number;      // 付费转化率 (0-1)
  avgReadingDuration: number;     // 平均阅读时长 (分钟)
  timestamp: number;              // 数据时间戳
}

export interface CrashListResponse {
  count: number;            // 崩溃总数
  rate: number;             // 崩溃率
  topIssue: string;         // 最频繁的 issue 名称
  affectedUsers: number;    // 受影响用户数
  lastOccurrence: number;   // 最后一次出现时间
  crashDetails: CrashItem[];
}

export interface CrashItem {
  issueId: string;
  name: string;
  count: number;
  affectedUsers: number;
  lastSeen: number;
  firstSeen: number;
  stackTrace: string;
}

export interface AlertItem {
  id: string;
  severity: 'error' | 'warning' | 'info';
  title: string;
  message: string;
  timestamp: number;
  resolved: boolean;
  source: string; // 'sentry' | 'api' | 'system'
}

/**
 * 监控 API 服务
 */
export class MonitorApi {
  private static readonly baseUrl = 'https://api.readmigo.cn/admin/dashboard';
  private static readonly timeout = 10000; // 10 秒超时

  /**
   * 获取仪表板聚合数据
   *
   * @param token 认证令牌
   * @param period 时间周期
   * @returns 聚合指标数据
   */
  static async getDashboardData(
    token: string,
    period: 'last_1h' | 'last_24h' | 'last_7d' = 'last_1h'
  ): Promise<DashboardMetricsResponse> {
    try {
      const response = await this.httpPost(
        `${this.baseUrl}/metrics`,
        { period },
        token
      );

      return {
        dau: response.data?.dau || 0,
        activeSessions: response.data?.activeSessions || 0,
        crashRate: (response.data?.crashRate || 0) / 100,  // 转换为浮点数
        apiErrorRate: (response.data?.apiErrorRate || 0) / 100,
        registrationConversion: (response.data?.registrationConversion || 0) / 100,
        paymentConversion: (response.data?.paymentConversion || 0) / 100,
        avgReadingDuration: response.data?.avgReadingDuration || 0,
        timestamp: response.timestamp || Date.now()
      };
    } catch (error) {
      console.error('Failed to get dashboard metrics:', error);
      throw this.handleError(error);
    }
  }

  /**
   * 获取崩溃列表
   *
   * @param token 认证令牌
   * @param period 时间周期
   * @param limit 返回数量限制
   * @returns 崩溃信息列表
   */
  static async getCrashList(
    token: string,
    period: 'last_1h' | 'last_24h' | 'last_7d' = 'last_24h',
    limit: number = 20
  ): Promise<CrashListResponse> {
    try {
      const params = new URLSearchParams({
        period,
        limit: String(limit)
      });

      const response = await this.httpGet(
        `${this.baseUrl}/crashes?${params.toString()}`,
        token
      );

      return {
        count: response.data?.count || 0,
        rate: (response.data?.rate || 0) / 100,
        topIssue: response.data?.topIssue || 'N/A',
        affectedUsers: response.data?.affectedUsers || 0,
        lastOccurrence: response.data?.lastOccurrence || 0,
        crashDetails: (response.data?.details || []).map((item: any) => ({
          issueId: item.issueId,
          name: item.name,
          count: item.count,
          affectedUsers: item.affectedUsers,
          lastSeen: item.lastSeen,
          firstSeen: item.firstSeen,
          stackTrace: item.stackTrace
        }))
      };
    } catch (error) {
      console.error('Failed to get crash list:', error);
      throw this.handleError(error);
    }
  }

  /**
   * 获取当前活跃告警
   *
   * @param token 认证令牌
   * @returns 告警列表
   */
  static async getActiveAlerts(token: string): Promise<AlertItem[]> {
    try {
      const response = await this.httpGet(
        `${this.baseUrl}/alerts?active=true`,
        token
      );

      return (response.data?.alerts || []).map((item: any) => ({
        id: item.id,
        severity: item.severity || 'info',
        title: item.title,
        message: item.message,
        timestamp: item.timestamp,
        resolved: item.resolved || false,
        source: item.source || 'system'
      }));
    } catch (error) {
      console.error('Failed to get active alerts:', error);
      // 不抛异常，返回空列表
      return [];
    }
  }

  /**
   * 获取 API 错误率详情
   *
   * @param token 认证令牌
   * @param period 时间周期
   * @returns API 错误率趋势数据
   */
  static async getApiErrorTrend(
    token: string,
    period: 'last_1h' | 'last_24h' = 'last_1h'
  ): Promise<{ time: number; errorRate: number }[]> {
    try {
      const response = await this.httpPost(
        `${this.baseUrl}/api-errors`,
        { period },
        token
      );

      return (response.data?.trend || []).map((item: any) => ({
        time: item.time,
        errorRate: (item.errorRate || 0) / 100
      }));
    } catch (error) {
      console.error('Failed to get API error trend:', error);
      return [];
    }
  }

  /**
   * 标记告警为已解决
   *
   * @param token 认证令牌
   * @param alertId 告警 ID
   */
  static async resolveAlert(token: string, alertId: string): Promise<void> {
    try {
      await this.httpPut(
        `${this.baseUrl}/alerts/${alertId}/resolve`,
        {},
        token
      );
    } catch (error) {
      console.error('Failed to resolve alert:', error);
      throw this.handleError(error);
    }
  }

  /**
   * HTTP GET 请求
   */
  private static httpGet(url: string, token: string): Promise<any> {
    return new Promise((resolve, reject) => {
      const request = {
        method: 'GET',
        url: url,
        header: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        connectTimeout: this.timeout,
        readTimeout: this.timeout
      };

      http.createHttpRequest(request)
        .then((response: any) => {
          try {
            const result = JSON.parse(response.result);
            if (response.responseCode === 200) {
              resolve(result);
            } else {
              reject({
                code: response.responseCode,
                message: result.message || 'Request failed'
              });
            }
          } catch (e) {
            reject(e);
          }
        })
        .catch(reject);
    });
  }

  /**
   * HTTP POST 请求
   */
  private static httpPost(url: string, data: any, token: string): Promise<any> {
    return new Promise((resolve, reject) => {
      const request = {
        method: 'POST',
        url: url,
        header: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        extraData: JSON.stringify(data),
        connectTimeout: this.timeout,
        readTimeout: this.timeout
      };

      http.createHttpRequest(request)
        .then((response: any) => {
          try {
            const result = JSON.parse(response.result);
            if (response.responseCode === 200) {
              resolve(result);
            } else {
              reject({
                code: response.responseCode,
                message: result.message || 'Request failed'
              });
            }
          } catch (e) {
            reject(e);
          }
        })
        .catch(reject);
    });
  }

  /**
   * HTTP PUT 请求
   */
  private static httpPut(url: string, data: any, token: string): Promise<any> {
    return new Promise((resolve, reject) => {
      const request = {
        method: 'PUT',
        url: url,
        header: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        extraData: JSON.stringify(data),
        connectTimeout: this.timeout,
        readTimeout: this.timeout
      };

      http.createHttpRequest(request)
        .then((response: any) => {
          try {
            const result = JSON.parse(response.result);
            if (response.responseCode === 200) {
              resolve(result);
            } else {
              reject({
                code: response.responseCode,
                message: result.message || 'Request failed'
              });
            }
          } catch (e) {
            reject(e);
          }
        })
        .catch(reject);
    });
  }

  /**
   * 处理错误
   */
  private static handleError(error: any): Error {
    if (error.code === 401) {
      return new Error('认证失败，请重新登录');
    } else if (error.code === 403) {
      return new Error('您没有权限访问此资源');
    } else if (error.code === 404) {
      return new Error('请求的资源不存在');
    } else if (error.code === 500) {
      return new Error('服务器内部错误，请稍后重试');
    } else if (error.message?.includes('timeout')) {
      return new Error('请求超时，请检查网络连接');
    } else {
      return error instanceof Error ? error : new Error('未知错误');
    }
  }
}

/**
 * 监控指标缓存管理
 * 用于减少 API 调用
 */
export class MonitorCache {
  private static cache: Map<string, { data: any; timestamp: number }> = new Map();
  private static readonly cacheDuration = 30000; // 30 秒缓存

  static get(key: string): any | null {
    const entry = this.cache.get(key);
    if (!entry) return null;

    if (Date.now() - entry.timestamp > this.cacheDuration) {
      this.cache.delete(key);
      return null;
    }

    return entry.data;
  }

  static set(key: string, data: any): void {
    this.cache.set(key, {
      data,
      timestamp: Date.now()
    });
  }

  static clear(): void {
    this.cache.clear();
  }

  static clearKey(key: string): void {
    this.cache.delete(key);
  }
}
