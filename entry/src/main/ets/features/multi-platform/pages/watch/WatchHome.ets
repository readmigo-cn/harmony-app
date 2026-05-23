/**
 * WatchHome — W15-C1 手表主页（圆形屏）
 *
 * 布局策略（适配 466×466 等圆形/方形屏）：
 *   - 整屏使用 Stack，外层圆形掩膜（borderRadius=halfWidth）
 *   - 中央 Circle 进度环：今日阅读分钟 / 目标分钟 (默认 30)
 *   - 顶部 header（弧形顶端）：12vp 时间 + 米果橙 logo dot
 *   - 中部 Column：阅读分钟数 + "今日" 标签
 *   - 下方三个圆形 quick action button 横排（限制宽度避免溢出圆形）
 *
 * 表冠 (Crown) 滚动：
 *   - HarmonyOS 手表 ArkUI 的 Scroll/List 组件原生支持表冠输入
 *   - 这里把 quick action 套在 Scroll 中，长按表冠可上下浏览
 *   - WatchVocab/WatchStats 内部独立处理表冠翻卡
 *
 * 子页路由：
 *   - 通过修改 AppStorage[WATCH_CURRENT_PAGE_KEY] 在 home/vocab/stats/audio 之间切换
 *   - 不使用 router.push（手表场景路由极简化，省内存）
 */

import router from '@ohos.router';
import { WATCH_CURRENT_PAGE_KEY, WATCH_TODAY_MINUTES_KEY, WATCH_DAILY_GOAL_KEY, WatchHaptic } from '../../../../abilities/WatchAbility';

@Entry
@Component
struct WatchHome {
  @StorageLink(WATCH_CURRENT_PAGE_KEY) currentPage: string = 'home';
  @StorageLink(WATCH_TODAY_MINUTES_KEY) todayMinutes: number = 0;
  @StorageProp(WATCH_DAILY_GOAL_KEY) dailyGoal: number = 30;

  @State private clockTime: string = '';
  private clockTimer: number = -1;

  // ---- 设计 token（高对比、暗色优先，适配 AOD） ----
  private readonly bgColor: string = '#0B0F1A';
  private readonly accent: string = '#E76F1A'; // 米果橙
  private readonly accentDim: string = '#3A2618';
  private readonly textPrimary: string = '#FFFFFF';
  private readonly textSecondary: string = '#9AA3B2';
  private readonly ringTrack: string = '#1F2532';

  // ---- 圆形屏 Geometry ----
  private readonly screenSize: number = 466; // wearable 默认 466vp
  private readonly ringSize: number = 220;
  private readonly ringStroke: number = 12;

  // ---------- lifecycle ----------

  aboutToAppear(): void {
    this.tickClock();
    this.clockTimer = setInterval(() => this.tickClock(), 30_000) as unknown as number;
  }

  aboutToDisappear(): void {
    if (this.clockTimer !== -1) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
  }

  private tickClock(): void {
    const now = new Date();
    const hh = String(now.getHours()).padStart(2, '0');
    const mm = String(now.getMinutes()).padStart(2, '0');
    this.clockTime = `${hh}:${mm}`;
  }

  // ---------- 进度计算 ----------

  private progressPct(): number {
    const goal = Math.max(1, this.dailyGoal);
    const cur = Math.max(0, Math.min(this.todayMinutes, goal));
    return cur / goal;
  }

  // ---------- 路由（in-storage） ----------

  private goto(page: 'vocab' | 'stats' | 'audio'): void {
    WatchHaptic.fire('tap');
    this.currentPage = page;
  }

  // ---------- builders ----------

  @Builder ProgressArc() {
    Stack() {
      // 背景圆环
      Circle({ width: this.ringSize, height: this.ringSize })
        .fill(Color.Transparent)
        .stroke(this.ringTrack)
        .strokeWidth(this.ringStroke)

      // 进度圆环（用 Progress 组件适配 NEXT 的 ring style）
      Progress({ value: Math.round(this.progressPct() * 100), total: 100, type: ProgressType.Ring })
        .width(this.ringSize)
        .height(this.ringSize)
        .color(this.accent)
        .style({ strokeWidth: this.ringStroke, scaleCount: 0, scaleWidth: 0 })

      // 中央数字
      Column({ space: 2 }) {
        Text(`${Math.max(0, this.todayMinutes ?? 0)}`)
          .fontSize(56)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textPrimary)
        Text(`分钟 / ${this.dailyGoal}`)
          .fontSize(13)
          .fontColor(this.textSecondary)
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width(this.ringSize)
    .height(this.ringSize)
  }

  @Builder QuickActionButton(label: string, target: 'vocab' | 'stats' | 'audio') {
    Column({ space: 4 }) {
      Circle({ width: 40, height: 40 })
        .fill(this.accentDim)
        .stroke(this.accent)
        .strokeWidth(1.5)
      Text(label)
        .fontSize(11)
        .fontColor(this.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Center)
    .padding(4)
    .onClick(() => this.goto(target))
  }

  @Builder Header() {
    Row() {
      Circle({ width: 6, height: 6 }).fill(this.accent)
      Text(this.clockTime)
        .fontSize(13)
        .fontColor(this.textSecondary)
        .margin({ left: 6 })
    }
    .padding({ top: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder HomeContent() {
    // 用 Scroll 让表冠（crown）可滚动；圆形屏的视觉中心保持在 ring
    Scroll() {
      Column({ space: 14 }) {
        this.Header()
        this.ProgressArc()
        // 三 quick actions（横排，限制总宽以适配圆形）
        Row({ space: 18 }) {
          this.QuickActionButton('今日一词', 'vocab')
          this.QuickActionButton('阅读统计', 'stats')
          this.QuickActionButton('继续听书', 'audio')
        }
        .width(280)
        .justifyContent(FlexAlign.Center)
        .padding({ top: 8 })
      }
      .alignItems(HorizontalAlign.Center)
      .width('100%')
      .padding({ bottom: 40 })
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
  }

  // 子页通过 router-equivalent state machine 触发
  @Builder Body() {
    if (this.currentPage === 'vocab') {
      // 子页加载时切到 vocab page（用 router.replaceUrl 保持 stack 单层）
      Column().onAppear(() => router.pushUrl({ url: 'pages/watch/WatchVocab' }).catch(() => {}))
    } else if (this.currentPage === 'stats') {
      Column().onAppear(() => router.pushUrl({ url: 'pages/watch/WatchStats' }).catch(() => {}))
    } else if (this.currentPage === 'audio') {
      // 复用主 App AudioAbility 入口，跳到现有 player（手表精简版后续 W16）
      Column().onAppear(() => router.pushUrl({ url: 'features/audiobook/pages/AudiobookPlayer' }).catch(() => {}))
    } else {
      this.HomeContent()
    }
  }

  build() {
    Stack() {
      this.Body()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
  }
}
