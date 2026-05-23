/**
 * WatchSync — W15-C1 手表端同步桥
 *
 * 复用 W10 SyncEngine 的 vocab-note + reading-progress syncer。
 * 手表场景特殊点：
 *   - 不允许长 push debounce（手表交互一次评分要立刻同步给手机端）
 *     → 评分后调用 immediateFlush('vocab-note')
 *   - reading-progress 仅 pull，不 push（手表端不产生新阅读进度）
 *   - 启动时 pullAll → 同步今日阅读分钟、单词列表到 AppStorage
 *
 * 注：实际跨端通道（hms-distributedSchedule）的握手在 DeviceManager 处理；
 *     本 sync 仅负责把"已就绪"的远端数据投递给 watch UI 层 (AppStorage)。
 */

import { SyncEngine } from '../sync/SyncEngine';
import { VocabNoteSyncer } from '../sync/syncers/VocabNoteSyncer';
import { ReadingProgressSyncer } from '../sync/syncers/ReadingProgressSyncer';
import { NoteService } from '../../../../features/notes/service/NoteService';
import {
  WATCH_TODAY_MINUTES_KEY,
  WATCH_DAILY_GOAL_KEY,
} from '../../../../abilities/WatchAbility';
import {
  WATCH_WEEK_STREAK_KEY,
  WATCH_TOTAL_MINUTES_KEY,
} from '../../../../features/multi-platform/pages/watch/WatchStats';

const TAG = 'WatchSync';

class WatchSyncImpl {
  private inited: boolean = false;
  private vocabSyncer: VocabNoteSyncer = new VocabNoteSyncer();
  private progressSyncer: ReadingProgressSyncer = new ReadingProgressSyncer();

  /** 启动时调用：注册 syncer 并触发初次 pull。 */
  async init(): Promise<void> {
    if (this.inited) return;
    this.inited = true;

    SyncEngine.register(this.vocabSyncer);
    SyncEngine.register(this.progressSyncer);
    await SyncEngine.init();

    // 拉一次远端最新数据
    await SyncEngine.pullAll();

    // 同步今日阅读分钟（占位：先用本地 NoteService 估算）
    await this.refreshLocalSnapshot();
  }

  /** vocab 评分后立刻 flush，避免手机端延迟看到 SRS 状态。 */
  async pushVocabImmediate(): Promise<void> {
    await SyncEngine.flush('vocab-note');
  }

  /** WatchHome / WatchStats 拉到前台时刷新一次 AppStorage 快照。 */
  async refreshLocalSnapshot(): Promise<void> {
    try {
      // 单词量 → AppStorage
      const vocab = await NoteService.listVocab({ known: false });
      // 计算今日分钟（占位逻辑：从已有阅读 session ledger，TODO W16 接 ReadingSession）
      const todayMin = AppStorage.Get<number>(WATCH_TODAY_MINUTES_KEY) ?? 0;
      AppStorage.SetOrCreate<number>(WATCH_TODAY_MINUTES_KEY, todayMin);

      // 默认目标
      if (AppStorage.Get<number>(WATCH_DAILY_GOAL_KEY) === undefined) {
        AppStorage.SetOrCreate<number>(WATCH_DAILY_GOAL_KEY, 30);
      }

      // 周打卡占位（TODO 接 server-cn /reading/streak/me）
      if (AppStorage.Get<boolean[]>(WATCH_WEEK_STREAK_KEY) === undefined) {
        AppStorage.SetOrCreate<boolean[]>(WATCH_WEEK_STREAK_KEY,
          [false, false, false, false, false, false, false]);
      }
      if (AppStorage.Get<number>(WATCH_TOTAL_MINUTES_KEY) === undefined) {
        AppStorage.SetOrCreate<number>(WATCH_TOTAL_MINUTES_KEY, 0);
      }

      console.info(`${TAG} snapshot refreshed: vocab=${vocab.length} todayMin=${todayMin}`);
    } catch (e) {
      console.warn(`${TAG} refresh failed: ${(e as Error).message}`);
    }
  }
}

export const WatchSync = new WatchSyncImpl();
