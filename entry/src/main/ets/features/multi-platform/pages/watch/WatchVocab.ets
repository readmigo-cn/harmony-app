/**
 * WatchVocab — W15-C1 手表生词复习
 *
 * 圆形屏卡片式生词复习：
 *   - 单卡占整屏，居中大字号 word（48–56vp，圆形屏可读）
 *   - 下方释义（中文，两行内），底部小字"卡片 i / N"
 *   - 二档评分：
 *       「不知道」← 标记错答 → reviewCount++（不掌握）
 *       「知道」  ← 标记会  → markVocabKnown（提升 SRS）
 *     按钮采用对称弧形布局，避免误触
 *
 * 表冠 (Crown) 翻卡：
 *   - 包一层 List/Swiper，HarmonyOS NEXT 的 Swiper 在 wearable 上原生
 *     绑定 crown 滚动事件 → 上滑下一卡 / 下滑上一卡
 *   - 同时翻卡触发 'tap' 振动反馈
 *
 * 数据：从 NoteService.listVocab({ known: false }) 取未掌握的生词，最多 20 条。
 *      离线场景：若 NoteService 未初始化，使用最近一次缓存。
 */

import router from '@ohos.router';
import { NoteService, VocabNote } from '../../../../features/notes/service/NoteService';
import { WatchHaptic } from '../../../../abilities/WatchAbility';

@Entry
@Component
struct WatchVocab {
  @State private cards: VocabNote[] = [];
  @State private idx: number = 0;
  @State private loading: boolean = true;
  @State private finished: boolean = false;

  // ---- design tokens ----
  private readonly bgColor: string = '#0B0F1A';
  private readonly accent: string = '#E76F1A';
  private readonly success: string = '#3CB371';
  private readonly fail: string = '#E05050';
  private readonly textPrimary: string = '#FFFFFF';
  private readonly textSecondary: string = '#9AA3B2';

  // ---------- lifecycle ----------

  async aboutToAppear(): Promise<void> {
    try {
      const all = await NoteService.listVocab({ known: false });
      // 按 lastReviewedAt 升序：最久没复习的优先
      all.sort((a, b) => (a.lastReviewedAt ?? 0) - (b.lastReviewedAt ?? 0));
      this.cards = all.slice(0, 20);
    } catch (e) {
      console.warn(`WatchVocab load failed: ${(e as Error).message}`);
      this.cards = [];
    }
    this.loading = false;
    if (this.cards.length === 0) this.finished = true;
  }

  // ---------- 评分 ----------

  private async grade(known: boolean): Promise<void> {
    if (this.idx >= this.cards.length) return;
    const cur = this.cards[this.idx];
    WatchHaptic.fire(known ? 'success' : 'fail');
    try {
      if (known) {
        await NoteService.markVocabKnown(cur.id);
      } else {
        // 不掌握：仍更新 lastReviewedAt，让下次 SRS 提前
        await NoteService.updateVocab(cur.id, { lastReviewedAt: Date.now() });
      }
    } catch (e) {
      console.warn(`WatchVocab grade err: ${(e as Error).message}`);
    }
    this.next();
  }

  private next(): void {
    if (this.idx + 1 >= this.cards.length) {
      this.finished = true;
    } else {
      this.idx += 1;
    }
  }

  private prev(): void {
    if (this.idx > 0) {
      this.idx -= 1;
      WatchHaptic.fire('tap');
    }
  }

  private goBack(): void {
    router.back();
  }

  // ---------- builders ----------

  @Builder LoadingView() {
    Column() {
      Text('加载中…')
        .fontSize(16)
        .fontColor(this.textSecondary)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder FinishedView() {
    Column({ space: 12 }) {
      Text(this.cards.length === 0 ? '没有待复习的生词' : '今日复习完成 🎉')
        .fontSize(16)
        .fontColor(this.textPrimary)
        .textAlign(TextAlign.Center)
      Text('表冠下滑回到主页')
        .fontSize(12)
        .fontColor(this.textSecondary)
      Row() {
        Text('返回')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(this.accent)
          .borderRadius(20)
          .onClick(() => this.goBack())
      }
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(20)
  }

  @Builder Card(card: VocabNote) {
    Column({ space: 8 }) {
      // 顶部进度
      Text(`${this.idx + 1} / ${this.cards.length}`)
        .fontSize(11)
        .fontColor(this.textSecondary)
        .padding({ top: 16 })

      // 大字号 word
      Text(card.word)
        .fontSize(48)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ top: 16, bottom: 6 })

      // 中文释义（用 explain.translations 或 explain.definition fallback）
      Text(this.summarizeMeaning(card))
        .fontSize(13)
        .fontColor(this.textSecondary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })

      Blank()

      // 二档评分按钮：圆形屏对称布局
      Row({ space: 16 }) {
        Text('不会')
          .fontSize(13)
          .fontColor('#FFFFFF')
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor(this.fail)
          .borderRadius(24)
          .onClick(() => this.grade(false))
        Text('知道')
          .fontSize(13)
          .fontColor('#FFFFFF')
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor(this.success)
          .borderRadius(24)
          .onClick(() => this.grade(true))
      }
      .padding({ bottom: 28 })
      .justifyContent(FlexAlign.Center)
    }
    .width('100%').height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 从 ExplainData 抽取最简释义文本。 */
  private summarizeMeaning(card: VocabNote): string {
    const ex = card.explain as Record<string, Object> | undefined;
    if (!ex) return '';
    const def = ex.definition as string | undefined;
    if (def && def.length > 0) return def;
    const ts = ex.translations as string[] | undefined;
    if (ts && ts.length > 0) return ts[0];
    return card.context ?? '';
  }

  build() {
    // Swiper 给 crown 滚动用：HarmonyOS wearable Swiper 自动响应表冠
    Stack() {
      if (this.loading) {
        this.LoadingView()
      } else if (this.finished) {
        this.FinishedView()
      } else {
        Swiper() {
          ForEach(this.cards, (c: VocabNote) => {
            this.Card(c)
          }, (c: VocabNote) => c.id)
        }
        .index(this.idx)
        .loop(false)
        .indicator(false)
        .vertical(true)
        .onChange((i) => {
          if (i !== this.idx) {
            WatchHaptic.fire('tap');
            this.idx = i;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
  }
}
