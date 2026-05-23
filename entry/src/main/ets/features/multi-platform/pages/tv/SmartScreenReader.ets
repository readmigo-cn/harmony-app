/**
 * SmartScreenReader.ets — W15-C3 智慧屏全屏阅读
 *
 * 视觉：
 *   - 字号 48-72pt（默认 56），正文置中，最大宽度 1200vp 避免过宽
 *   - 行高 1.6，段间距 32vp
 *   - 背景 #FBF7EE / 文字 #1A1A1A（高对比度白纸黑字）
 *   - 顶部细 progress bar，底部章节信息 + 字号档位 + 滚动速度
 *
 * 遥控器键位：
 *   - LEFT  / CHANNEL_DOWN → 上一页（自动滚动暂停 2s 等用户）
 *   - RIGHT / CHANNEL_UP   → 下一页
 *   - UP    → 字号 +4
 *   - DOWN  → 字号 -4
 *   - SELECT → 切换自动滚动 (5 速度档循环)
 *   - MENU   → 弹设置面板（字号 / 行高 / 主题，占位 toast）
 *   - PLAY_PAUSE → 优先 TTS 播放（占位：调 TTSService）
 *   - BACK   → router.back
 *
 * 自动滚动：
 *   - 5 档速度：0=停, 1=慢, 2=中慢, 3=中, 4=快, 5=超快
 *   - 实现：每 N ms 把 scroller 的 currentOffset.y 增加 stepPx
 *   - 长按 SELECT 也可调速（非本任务，留 TODO）
 */

import { AppColors } from '../../../../core/theme/AppColors';
import { Spacing, Radius } from '../../../../core/theme/AppSpacing';
import { RemoteController } from '../../../../features/multi-platform/service/RemoteController';
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';

const SCROLL_SPEEDS = [0, 1, 2, 3, 5, 8]; // px / tick (~50ms)
const SCROLL_TICK_MS = 50;
const FONT_MIN = 48;
const FONT_MAX = 96;
const FONT_STEP = 4;

const DEMO_PARAGRAPHS: string[] = [
  '第一章 · 真理',
  '凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。',
  '这样的单身汉，每逢新搬到一个地方，四邻八舍虽然完全不了解他的性情如何，见解如何，可是，既然这样的一条真理早已在人们心目中根深蒂固，因此人们总是把他看作自己某一个女儿理所应得的一笔财产。',
  '"我的好老爷，"有一天班纳特太太对她的丈夫说，"你听说过尼日斐花园终于租出去了吗？"',
  '班纳特先生回答道，没有听说过。',
  '"的确租出去了，"她说，"朗格太太刚刚上这儿来过，她把这件事的底细，一五一十地告诉了我。"',
  '班纳特先生没有理睬她。',
  '"你难道不想知道是谁租去的吗？"太太不耐烦地嚷起来了。',
  '"既是你要说给我听，我听听也无妨。"',
  '这句话足够鼓励她讲下去了。',
  '"哦！亲爱的，你得知道，朗格太太说，租尼日斐花园的是个阔少爷，他是英格兰北部的人；听说他星期一那天，乘着一辆驷马大轿车来看房子，看得非常中意，当场就和莫理斯先生谈妥了。"',
];

@Entry
@Component
struct SmartScreenReader {
  @State fontSize: number = 56;
  @State scrollSpeedIdx: number = 0; // 0 = paused
  @State currentChapter: number = 1;
  @State progress: number = 0; // 0..1
  @StorageLink('reading_current_book') bookId: string = '';

  private scroller: Scroller = new Scroller();
  private tickerId: number = -1;
  private unlistenRemote: (() => void) | null = null;

  aboutToAppear(): void {
    this.unlistenRemote = RemoteController.listen((key) => {
      switch (key) {
        case 'LEFT':
        case 'CHANNEL_DOWN':
          this.pageBackward();
          return true;
        case 'RIGHT':
        case 'CHANNEL_UP':
          this.pageForward();
          return true;
        case 'UP':
          this.bumpFont(+FONT_STEP);
          return true;
        case 'DOWN':
          this.bumpFont(-FONT_STEP);
          return true;
        case 'SELECT':
          this.cycleSpeed();
          return true;
        case 'MENU':
          promptAction.showToast({ message: '设置面板（占位）' });
          return true;
        case 'PLAY_PAUSE':
          this.toggleTts();
          return true;
        case 'BACK':
          router.back();
          return true;
        default:
          return false;
      }
    });
    this.startTicker();
  }

  aboutToDisappear(): void {
    if (this.unlistenRemote) this.unlistenRemote();
    this.stopTicker();
  }

  private bumpFont(delta: number): void {
    const next = Math.max(FONT_MIN, Math.min(FONT_MAX, this.fontSize + delta));
    if (next !== this.fontSize) {
      this.fontSize = next;
      promptAction.showToast({ message: `字号 ${next}pt` });
    }
  }

  private cycleSpeed(): void {
    this.scrollSpeedIdx = (this.scrollSpeedIdx + 1) % SCROLL_SPEEDS.length;
    promptAction.showToast({
      message: this.scrollSpeedIdx === 0 ? '自动滚动：暂停' : `自动滚动：档位 ${this.scrollSpeedIdx}`,
    });
  }

  private pageForward(): void {
    // 一屏约 800vp，下一页
    this.scroller.scrollBy(0, 800);
  }

  private pageBackward(): void {
    this.scroller.scrollBy(0, -800);
  }

  private toggleTts(): void {
    // TODO Phase 3：接入 TTSService.toggle(this.bookId)
    promptAction.showToast({ message: '已切换 TTS 朗读（占位）' });
  }

  private startTicker(): void {
    if (this.tickerId !== -1) return;
    this.tickerId = setInterval(() => {
      const step = SCROLL_SPEEDS[this.scrollSpeedIdx];
      if (step > 0) {
        this.scroller.scrollBy(0, step);
        // 模拟阅读进度
        this.progress = Math.min(1, this.progress + step / 100000);
      }
    }, SCROLL_TICK_MS);
  }

  private stopTicker(): void {
    if (this.tickerId !== -1) {
      clearInterval(this.tickerId);
      this.tickerId = -1;
    }
  }

  build() {
    Stack() {
      // ── 主体阅读区 ──
      Column() {
        Scroll(this.scroller) {
          Column({ space: 32 }) {
            ForEach(DEMO_PARAGRAPHS, (p: string, idx: number) => {
              Text(p)
                .fontSize(idx === 0 ? this.fontSize + 12 : this.fontSize)
                .fontWeight(idx === 0 ? FontWeight.Bold : FontWeight.Regular)
                .fontColor('#1A1A1A')
                .lineHeight(this.fontSize * 1.6)
                .width('100%')
            }, (p: string, idx: number) => `${idx}-${p.substring(0, 8)}`)
            // 留出底部空白避免被状态条遮挡
            Blank().height(160)
          }
          .width('100%')
          .padding({ left: 80, right: 80, top: 80 })
          .constraintSize({ maxWidth: 1400 })
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FBF7EE')

      // ── 顶部 progress bar ──
      Column() {
        Progress({ value: this.progress * 100, total: 100, type: ProgressType.Linear })
          .color(AppColors.brand)
          .backgroundColor('#E0D8C8')
          .style({ strokeWidth: 6 })
          .width('100%')
      }
      .width('100%')
      .position({ x: 0, y: 0 })

      // ── 底部状态栏 ──
      Row({ space: Spacing.s8 }) {
        Text(`第 ${this.currentChapter} 章`)
          .fontSize(24)
          .fontColor('#3B2F1E')
        Text(`字号 ${this.fontSize}pt`)
          .fontSize(24)
          .fontColor('#3B2F1E')
        Text(this.scrollSpeedIdx === 0
          ? '滚动: 暂停'
          : `滚动: 档 ${this.scrollSpeedIdx}/5`)
          .fontSize(24)
          .fontColor(this.scrollSpeedIdx === 0 ? '#7A6A52' : AppColors.brand)
        Text(`${Math.round(this.progress * 100)}%`)
          .fontSize(24)
          .fontColor('#3B2F1E')
        Blank()
        Text('← → 翻页    ↑ ↓ 字号    OK 滚动    MENU 设置')
          .fontSize(20)
          .fontColor('#7A6A52')
      }
      .width('100%')
      .padding({ left: 80, right: 80, top: 16, bottom: 16 })
      .backgroundColor('#F4ECD8')
      .border({ width: { top: 1 }, color: '#D8CDB0' })
      .position({ x: 0, y: '92%' })
    }
    .width('100%')
    .height('100%')
  }
}
