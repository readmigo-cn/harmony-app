/**
 * WatchStats — W15-C1 手表阅读统计
 *
 * 圆形屏极简数据可视化：
 *   - 顶部弧形："本周打卡"
 *   - 中央：今日阅读分钟（80vp 大字号）+ "今日" 标签
 *   - 中部：周打卡 7 个圆点（周一至周日，已打卡填色 / 未打卡描边）
 *   - 底部：单词量 / 累计阅读时长（小字两行）
 *
 * 数据来源：
 *   - 今日分钟：AppStorage[WATCH_TODAY_MINUTES_KEY]（WatchSync 同步）
 *   - 周打卡：AppStorage[WATCH_WEEK_STREAK_KEY] (boolean[7])
 *   - 单词量：NoteService.listVocab() count
 *
 * 表冠：内容总高 < 屏幕高，无需滚动；表冠下滑触发 router.back()。
 */

import router from '@ohos.router';
import { NoteService } from '../../../../features/notes/service/NoteService';
import { WATCH_TODAY_MINUTES_KEY, WATCH_DAILY_GOAL_KEY, WatchHaptic } from '../../../../abilities/WatchAbility';

/** AppStorage key：本周打卡（[周一,…,周日] boolean，由 WatchSync 计算）*/
export const WATCH_WEEK_STREAK_KEY: string = 'watch_week_streak';
/** AppStorage key：累计阅读分钟 */
export const WATCH_TOTAL_MINUTES_KEY: string = 'watch_total_minutes';

@Entry
@Component
struct WatchStats {
  @StorageProp(WATCH_TODAY_MINUTES_KEY) todayMinutes: number = 0;
  @StorageProp(WATCH_DAILY_GOAL_KEY) dailyGoal: number = 30;
  @StorageProp(WATCH_WEEK_STREAK_KEY) weekStreak: boolean[] = [false, false, false, false, false, false, false];
  @StorageProp(WATCH_TOTAL_MINUTES_KEY) totalMinutes: number = 0;

  @State private vocabCount: number = 0;

  // ---- design tokens ----
  private readonly bgColor: string = '#0B0F1A';
  private readonly accent: string = '#E76F1A';
  private readonly textPrimary: string = '#FFFFFF';
  private readonly textSecondary: string = '#9AA3B2';
  private readonly dotEmpty: string = '#1F2532';

  private readonly weekLabels: string[] = ['一', '二', '三', '四', '五', '六', '日'];

  // ---------- lifecycle ----------

  async aboutToAppear(): Promise<void> {
    try {
      const list = await NoteService.listVocab();
      this.vocabCount = list.length;
    } catch (_e) {
      this.vocabCount = 0;
    }
  }

  // ---------- builders ----------

  @Builder DayDot(idx: number) {
    Column({ space: 4 }) {
      if (this.weekStreak[idx]) {
        Circle({ width: 14, height: 14 }).fill(this.accent)
      } else {
        Circle({ width: 14, height: 14 })
          .fill(Color.Transparent)
          .stroke(this.dotEmpty)
          .strokeWidth(1.5)
      }
      Text(this.weekLabels[idx])
        .fontSize(9)
        .fontColor(this.textSecondary)
    }
  }

  build() {
    Stack() {
      Column() {
        // 顶部 header
        Text('本周打卡')
          .fontSize(12)
          .fontColor(this.textSecondary)
          .padding({ top: 24 })

        // 中央：今日阅读分钟（大字号）
        Column({ space: 2 }) {
          Text(`${Math.max(0, this.todayMinutes ?? 0)}`)
            .fontSize(80)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textPrimary)
          Text(`今日 / 目标 ${this.dailyGoal} 分钟`)
            .fontSize(11)
            .fontColor(this.textSecondary)
        }
        .padding({ top: 12 })
        .alignItems(HorizontalAlign.Center)

        // 周打卡 7 圆点
        Row({ space: 10 }) {
          ForEach([0, 1, 2, 3, 4, 5, 6], (i: number) => {
            this.DayDot(i)
          }, (i: number) => `dot-${i}`)
        }
        .padding({ top: 18 })
        .justifyContent(FlexAlign.Center)

        Blank()

        // 底部：单词量 + 累计
        Column({ space: 4 }) {
          Text(`单词量 ${this.vocabCount}`)
            .fontSize(12)
            .fontColor(this.textSecondary)
          Text(`累计 ${Math.round((this.totalMinutes ?? 0) / 60 * 10) / 10} 小时`)
            .fontSize(11)
            .fontColor(this.textSecondary)
        }
        .padding({ bottom: 26 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        // 整屏点击触发振动反馈（确认手势）
        WatchHaptic.fire('tap');
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
  }
}
