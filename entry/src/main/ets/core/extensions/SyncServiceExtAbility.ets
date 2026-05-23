import ServiceExtensionAbility from '@ohos.app.ability.ServiceExtensionAbility';
import Want from '@ohos.app.ability.Want';

const TAG = 'SyncServiceExtAbility';

/** 同步任务类型。 */
enum SyncKind {
  READING_PROGRESS = 'reading_progress',
  VOCAB_NOTES = 'vocab_notes',
  PERSONAL_NOTES = 'personal_notes',
  BOOKSHELF = 'bookshelf',
}

/** 单次同步窗口的执行结果。 */
interface SyncResult {
  kind: SyncKind;
  ok: boolean;
  pushed: number;
  pulled: number;
  errorMessage?: string;
}

/**
 * SyncServiceExtAbility：后台同步服务。
 *
 * 触发条件：
 *   - 周期定时（默认 15 分钟，由系统调度，受电量/网络状态约束）
 *   - 主 App 切前台时主动 startServiceExtensionAbility(want={cmd:'sync_now'})
 *   - 网络从断开恢复时 commonEvent 触发（TODO Phase 2 注册）
 *
 * 失败重试：指数退避 30s -> 1m -> 2m -> 5m，最多 4 次；之后等下一周期。
 *
 * 实际同步走 ReadingApi / NotesApi / SyncApi（在 service/ 下，与主进程共享代码包）。
 * 同进程 / 跨进程实例隔离：service 跑在独立进程，但访问的是同一个 RDB / Preferences，
 * DatabaseManager 内部用 dataPreferences + relationalStore 自带的多进程互斥。
 */
export default class SyncServiceExtAbility extends ServiceExtensionAbility {
  private retryAttempt: number = 0;
  private readonly retryBackoffMs: number[] = [30_000, 60_000, 120_000, 300_000];

  onCreate(_want: Want): void {
    console.info(`${TAG} onCreate`);
  }

  /**
   * 由系统调度器触发或主 App 主动 start 时调用。
   * 不建立长连接（onConnect 留空），用 onRequest + commonEvent 通信。
   */
  onRequest(want: Want, _startId: number): void {
    const params = (want?.parameters ?? {}) as Record<string, Object>;
    const cmd = (params.cmd as string) ?? 'sync_now';
    if (cmd === 'sync_now') {
      this.runSyncCycle();
    } else if (cmd === 'cancel') {
      this.cancelInternal();
    }
  }

  onDestroy(): void {
    console.info(`${TAG} onDestroy`);
  }

  // ---- 同步主流程 ----

  private async runSyncCycle(): Promise<void> {
    // 前置检查：用户已登录 + 网络可用
    const loggedIn = AppStorage.Get<boolean>('user_logged_in') ?? false;
    if (!loggedIn) {
      console.info(`${TAG} skip: not authenticated`);
      return;
    }
    // TODO(Phase 2): @ohos.net.connection 检查网络可用 / 是否仅 Wi-Fi
    const allKinds: SyncKind[] = [
      SyncKind.READING_PROGRESS,
      SyncKind.VOCAB_NOTES,
      SyncKind.PERSONAL_NOTES,
      SyncKind.BOOKSHELF,
    ];
    const results: SyncResult[] = [];
    for (const kind of allKinds) {
      const r = await this.runOne(kind);
      results.push(r);
    }
    // 任何一个 kind 失败 -> 触发指数退避
    const anyFailed = results.some((r) => !r.ok);
    if (anyFailed) {
      this.scheduleRetry();
    } else {
      this.retryAttempt = 0;
      console.info(`${TAG} all kinds synced ok`);
    }
    // TODO(Phase 2): commonEvent.publish('readmigo.sync.done', { results })
  }

  /**
   * 单个 kind 的 push + pull。占位实现 —— Phase 2 接 ReadingApi / NotesApi / SyncApi。
   */
  private async runOne(kind: SyncKind): Promise<SyncResult> {
    try {
      // TODO(Phase 2): 真实 push (RDB 中 dirty=1 的行) + pull (since=lastSyncedAt)
      // 当前为占位，直接返回成功
      console.info(`${TAG} sync ${kind} (placeholder)`);
      return { kind, ok: true, pushed: 0, pulled: 0 };
    } catch (err) {
      const e = err as Error;
      return { kind, ok: false, pushed: 0, pulled: 0, errorMessage: e.message };
    }
  }

  /**
   * 指数退避：用 setTimeout 而非 system scheduler，避免抢占系统配额。
   */
  private scheduleRetry(): void {
    if (this.retryAttempt >= this.retryBackoffMs.length) {
      console.warn(`${TAG} retry exhausted`);
      this.retryAttempt = 0;
      return;
    }
    const delay = this.retryBackoffMs[this.retryAttempt];
    this.retryAttempt += 1;
    console.info(`${TAG} schedule retry in ${delay}ms (attempt ${this.retryAttempt})`);
    setTimeout(() => this.runSyncCycle(), delay);
  }

  private cancelInternal(): void {
    this.retryAttempt = 0;
    console.info(`${TAG} cancel`);
  }
}
