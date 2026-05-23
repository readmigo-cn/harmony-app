/**
 * 内部监控仪表板
 * 仅管理员用户可见，用于实时监控应用健康状态
 *
 * 功能：
 * - DAU / 活跃会话展示
 * - 崩溃率监控（Sentry + AGC）
 * - API 错误率追踪
 * - 关键转化漏斗（注册、付费）
 * - 阈值告警标识
 * - 自动 30 秒刷新
 */

import { router } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { persistentStorage } from '@kit.ArkData';

interface DashboardMetrics {
  timestamp: number;
  dau: number;              // 日活跃用户
  activeSessions: number;   // 当前活跃会话
  crashRate: number;        // 崩溃率 (%)
  apiErrorRate: number;     // API 错误率 (%)
  registrationConversion: number;  // 注册转化率
  paymentConversion: number;       // 付费转化率
  avgReadingDuration: number;      // 平均阅读时长 (分钟)
  serverHealth: 'healthy' | 'degraded' | 'unhealthy';
  alerts: AlertItem[];
}

interface AlertItem {
  id: string;
  severity: 'error' | 'warning' | 'info';
  title: string;
  message: string;
  timestamp: number;
  resolved: boolean;
}

interface CrashDetail {
  count: number;
  rate: number;
  topIssue: string;
  affectedUsers: number;
  lastOccurrence: number;
}

@Entry
@Component
struct MonitorDashboard {
  @State metrics: DashboardMetrics | null = null;
  @State crashDetails: CrashDetail | null = null;
  @State activeAlerts: AlertItem[] = [];
  @State loading: boolean = true;
  @State refreshTime: number = Date.now();
  @State autoRefreshEnabled: boolean = true;

  private refreshTimer: number | null = null;
  private readonly REFRESH_INTERVAL = 30000; // 30 秒

  aboutToAppear() {
    this.checkAdminAccess();
    this.loadDashboardData();
    this.startAutoRefresh();
  }

  aboutToDisappear() {
    this.stopAutoRefresh();
  }

  /**
   * 检查用户是否为管理员
   */
  private checkAdminAccess() {
    // 获取当前用户身份
    const userId = persistentStorage.getSync<string>('userId', '');
    const userRole = persistentStorage.getSync<string>('userRole', 'user');

    const adminList = [
      'admin_001',  // CEO
      'admin_002',  // CTO
      'admin_003',  // Operations Lead
    ];

    if (!adminList.includes(userId) && userRole !== 'admin') {
      AlertDialog.show({
        message: '您没有权限访问此页面',
        buttons: [{ text: '返回', onPress: () => router.back() }]
      });
    }
  }

  /**
   * 加载仪表板数据
   */
  private async loadDashboardData() {
    this.loading = true;
    try {
      // 调用后端 API 获取数据
      const response = await this.fetchDashboardMetrics();
      this.metrics = response;

      // 获取崩溃详情
      this.crashDetails = await this.fetchCrashDetails();

      // 获取当前告警
      this.activeAlerts = await this.fetchActiveAlerts();

      // 记录刷新时间
      this.refreshTime = Date.now();
    } catch (error) {
      console.error('Failed to load dashboard data:', error);
      this.showErrorNotification();
    } finally {
      this.loading = false;
    }
  }

  /**
   * 从后端获取聚合指标数据
   * API: POST /admin/dashboard/metrics
   */
  private async fetchDashboardMetrics(): Promise<DashboardMetrics> {
    const token = persistentStorage.getSync<string>('authToken', '');

    const request = {
      method: 'POST',
      url: 'https://api.readmigo.cn/admin/dashboard/metrics',
      header: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify({ period: 'last_1h' })
    };

    return new Promise((resolve, reject) => {
      http.createHttpRequest(request)
        .then((response: any) => {
          try {
            const result = JSON.parse(response.result);
            resolve({
              timestamp: Date.now(),
              dau: result.dau || 0,
              activeSessions: result.activeSessions || 0,
              crashRate: result.crashRate || 0,
              apiErrorRate: result.apiErrorRate || 0,
              registrationConversion: result.registrationConversion || 0,
              paymentConversion: result.paymentConversion || 0,
              avgReadingDuration: result.avgReadingDuration || 0,
              serverHealth: this.evaluateServerHealth(result),
              alerts: []
            });
          } catch (e) {
            reject(e);
          }
        })
        .catch((err: any) => {
          console.error('API call failed:', err);
          reject(err);
        });
    });
  }

  /**
   * 获取崩溃详情（来自 Sentry API）
   * API: GET /admin/dashboard/crashes
   */
  private async fetchCrashDetails(): Promise<CrashDetail> {
    const token = persistentStorage.getSync<string>('authToken', '');

    const request = {
      method: 'GET',
      url: 'https://api.readmigo.cn/admin/dashboard/crashes?period=last_24h',
      header: {
        'Authorization': `Bearer ${token}`
      }
    };

    return new Promise((resolve) => {
      http.createHttpRequest(request)
        .then((response: any) => {
          try {
            const result = JSON.parse(response.result);
            resolve({
              count: result.count || 0,
              rate: result.rate || 0,
              topIssue: result.topIssue || 'N/A',
              affectedUsers: result.affectedUsers || 0,
              lastOccurrence: result.lastOccurrence || 0
            });
          } catch (e) {
            resolve({
              count: 0,
              rate: 0,
              topIssue: 'Error loading',
              affectedUsers: 0,
              lastOccurrence: 0
            });
          }
        })
        .catch(() => {
          resolve({
            count: 0,
            rate: 0,
            topIssue: 'Failed to load',
            affectedUsers: 0,
            lastOccurrence: 0
          });
        });
    });
  }

  /**
   * 获取当前告警列表
   * API: GET /admin/dashboard/alerts
   */
  private async fetchActiveAlerts(): Promise<AlertItem[]> {
    const token = persistentStorage.getSync<string>('authToken', '');

    const request = {
      method: 'GET',
      url: 'https://api.readmigo.cn/admin/dashboard/alerts?active=true',
      header: {
        'Authorization': `Bearer ${token}`
      }
    };

    return new Promise((resolve) => {
      http.createHttpRequest(request)
        .then((response: any) => {
          try {
            const result = JSON.parse(response.result);
            resolve(result.alerts || []);
          } catch (e) {
            resolve([]);
          }
        })
        .catch(() => {
          resolve([]);
        });
    });
  }

  /**
   * 评估服务器健康状态
   */
  private evaluateServerHealth(metrics: any): 'healthy' | 'degraded' | 'unhealthy' {
    const crashRate = metrics.crashRate || 0;
    const apiErrorRate = metrics.apiErrorRate || 0;

    if (crashRate > 10 || apiErrorRate > 5) {
      return 'unhealthy';
    } else if (crashRate > 5 || apiErrorRate > 2) {
      return 'degraded';
    } else {
      return 'healthy';
    }
  }

  /**
   * 启动自动刷新定时器
   */
  private startAutoRefresh() {
    if (this.refreshTimer !== null) {
      clearInterval(this.refreshTimer);
    }

    this.refreshTimer = setInterval(() => {
      if (this.autoRefreshEnabled) {
        this.loadDashboardData();
      }
    }, this.REFRESH_INTERVAL);
  }

  /**
   * 停止自动刷新
   */
  private stopAutoRefresh() {
    if (this.refreshTimer !== null) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  /**
   * 手动刷新
   */
  private manualRefresh() {
    this.loadDashboardData();
  }

  /**
   * 显示错误通知
   */
  private showErrorNotification() {
    AlertDialog.show({
      message: '无法加载仪表板数据，请检查网络连接',
      buttons: [
        { text: '重试', onPress: () => this.loadDashboardData() },
        { text: '返回', onPress: () => router.back() }
      ]
    });
  }

  /**
   * 获取告警徽章颜色
   */
  private getAlertBadgeColor(severity: string): string {
    switch (severity) {
      case 'error': return '#FF2E2E';
      case 'warning': return '#FFA500';
      case 'info': return '#1890FF';
      default: return '#999999';
    }
  }

  /**
   * 获取健康状态颜色
   */
  private getHealthStatusColor(status: string): string {
    switch (status) {
      case 'healthy': return '#22A745';
      case 'degraded': return '#FFC107';
      case 'unhealthy': return '#DC3545';
      default: return '#999999';
    }
  }

  /**
   * 格式化时间
   */
  private formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    return `${hours}:${minutes}`;
  }

  /**
   * 格式化百分比
   */
  private formatPercent(value: number): string {
    return `${(value * 100).toFixed(2)}%`;
  }

  build() {
    Column({ space: 20 }) {
      // 顶部标题栏
      Row({ space: 10 }) {
        Text('监控仪表板')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1);

        // 健康状态指示器
        if (this.metrics) {
          Row({ space: 5 }) {
            Circle({ width: 12, height: 12 })
              .fill(this.getHealthStatusColor(this.metrics.serverHealth));

            Text(this.metrics.serverHealth.toUpperCase())
              .fontSize(12)
              .fontColor('#666666');
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor('#f5f5f5')
          .borderRadius(4);
        }

        // 刷新按钮
        Button('刷新', { stateEffect: true })
          .width(80)
          .height(36)
          .fontSize(12)
          .onClick(() => this.manualRefresh());
      }
      .padding({ left: 16, right: 16, top: 12 })
      .width('100%');

      // 加载状态
      if (this.loading) {
        LoadingProgress()
          .width(50)
          .height(50)
          .margin(30);
      } else if (this.metrics) {
        // 关键指标卡片网格
        Grid() {
          GridItem() {
            this.MetricCard('DAU', `${this.metrics!.dau}`, '#1890FF');
          }
          GridItem() {
            this.MetricCard('活跃会话', `${this.metrics!.activeSessions}`, '#52C41A');
          }
          GridItem() {
            this.MetricCard(
              '崩溃率',
              this.formatPercent(this.metrics!.crashRate),
              this.metrics!.crashRate > 0.05 ? '#FF2E2E' : '#52C41A'
            );
          }
          GridItem() {
            this.MetricCard(
              'API 错误率',
              this.formatPercent(this.metrics!.apiErrorRate),
              this.metrics!.apiErrorRate > 0.02 ? '#FFA500' : '#52C41A'
            );
          }
        }
        .columnsTemplate('1fr 1fr')
        .rowsGap(12)
        .columnsGap(12)
        .padding(16);

        // 转化指标
        Column({ space: 8 }) {
          Text('关键转化')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .padding({ left: 16 });

          Row({ space: 0 }) {
            this.ConversionMeter(
              '注册',
              this.metrics!.registrationConversion,
              0.22
            );

            Divider()
              .width(1)
              .height(40)
              .margin({ left: 8, right: 8 });

            this.ConversionMeter(
              '付费',
              this.metrics!.paymentConversion,
              0.07
            );
          }
          .padding(12)
          .backgroundColor('#f5f5f5')
          .borderRadius(4)
          .margin({ left: 16, right: 16 });
        };

        // 阅读时长
        Column({ space: 8 }) {
          Text('平均阅读时长')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .padding({ left: 16 });

          Text(`${this.metrics!.avgReadingDuration.toFixed(1)} 分钟`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1890FF')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 });
        };

        // 崩溃详情
        if (this.crashDetails && this.crashDetails.count > 0) {
          Column({ space: 8 }) {
            Text('崩溃监控')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 16 });

            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('最近 24h')
                  .fontSize(12)
                  .fontColor('#999999');
                Text(`${this.crashDetails!.count} 次`)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FF2E2E');
              }
              .layoutWeight(1);

              Column({ space: 4 }) {
                Text('顶级 Issue')
                  .fontSize(12)
                  .fontColor('#999999');
                Text(this.crashDetails!.topIssue.substring(0, 20))
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold);
              }
              .layoutWeight(1);

              Column({ space: 4 }) {
                Text('受影响用户')
                  .fontSize(12)
                  .fontColor('#999999');
                Text(`${this.crashDetails!.affectedUsers}`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold);
              }
              .layoutWeight(1);
            }
            .padding(12)
            .backgroundColor('#fff5f5')
            .borderRadius(4)
            .margin({ left: 16, right: 16 });
          };
        }

        // 告警列表
        if (this.activeAlerts.length > 0) {
          Column({ space: 8 }) {
            Text(`告警 (${this.activeAlerts.length})`)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 16 });

            List({ space: 8 }) {
              ForEach(this.activeAlerts, (alert: AlertItem) => {
                ListItem() {
                  Row({ space: 8 }) {
                    Circle({ width: 8, height: 8 })
                      .fill(this.getAlertBadgeColor(alert.severity));

                    Column({ space: 2 }) {
                      Text(alert.title)
                        .fontSize(12)
                        .fontWeight(FontWeight.Bold);
                      Text(alert.message)
                        .fontSize(11)
                        .fontColor('#666666');
                    }
                    .layoutWeight(1);

                    Text(this.formatTime(alert.timestamp))
                      .fontSize(10)
                      .fontColor('#999999');
                  }
                  .padding(8)
                  .width('100%');
                }
                .backgroundColor('#f9f9f9')
                .borderRadius(4);
              }, (alert: AlertItem) => alert.id);
            }
            .padding({ left: 16, right: 16 })
            .scrollBar(BarState.Off);
          };
        }

        // 底部刷新时间
        Row() {
          Text(`最后刷新: ${this.formatTime(this.refreshTime)}`)
            .fontSize(11)
            .fontColor('#999999');

          Toggle({ type: ToggleType.Checkbox, isOn: this.autoRefreshEnabled })
            .width(32)
            .height(20)
            .onChange((value: boolean) => {
              this.autoRefreshEnabled = value;
              if (value) {
                this.startAutoRefresh();
              } else {
                this.stopAutoRefresh();
              }
            });

          Text('自动刷新')
            .fontSize(11)
            .fontColor('#666666');
        }
        .padding(16)
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween);
      }
    }
    .padding({ top: 8, bottom: 20 })
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
    .scrollable(ScrollDirection.Vertical);
  }

  /**
   * 指标卡片组件
   */
  @Builder
  MetricCard(label: string, value: string, color: string) {
    Column({ space: 8 }) {
      Text(label)
        .fontSize(12)
        .fontColor('#666666');

      Text(value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(color);
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#f5f5f5')
    .borderRadius(4)
    .justifyContent(FlexAlign.Center);
  }

  /**
   * 转化率指示器
   */
  @Builder
  ConversionMeter(label: string, rate: number, target: number) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontColor('#666666');

      Text(this.formatPercent(rate))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(rate >= target ? '#22A745' : '#FFA500');

      if (target > 0) {
        Progress({ value: (rate / target) * 100, total: 100, type: ProgressType.Linear })
          .height(4)
          .color(rate >= target ? '#22A745' : '#FFA500')
          .value(Math.min((rate / target) * 100, 100));

        Text(`目标: ${this.formatPercent(target)}`)
          .fontSize(10)
          .fontColor('#999999');
      }
    }
    .layoutWeight(1);
  }
}
