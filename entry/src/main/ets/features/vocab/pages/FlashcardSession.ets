/**
 * FlashcardSession.ets — W9-C2 闪卡复习页（SuperMemo-2 SRS 核心 UX）
 *
 * 状态机（per-card）：
 *   review  — 正面：单词 + 音标 + CEFR + 来源 book，用户「翻面」
 *   show    — 背面：释义 + 例句 + 上下文，5 档难度评分按钮
 *   submitting — 调 NotesApi.submitReview() 中
 *   next    — 下一张（重置为 review）
 *
 * 整体流程：
 *   aboutToAppear → fetchDue() → 渲染卡片队列
 *   → 用户翻面 → 评分（quality 0-5）→ submitReview → 队列 shift → 下一张
 *   → 队列空：显示 summary（已复习 N 张，正确率 X%）
 *
 * 翻转动画：rotateY(0) ↔ rotateY(180)，0.4s ease；正反面用 axis 控制可见。
 *
 * SuperMemo-2 quality 5 档（与后端 applySm2 对齐）：
 *   0 「不认识」     红    完全遗忘，间隔重置
 *   2 「想起一些」   橙    没通过，但有印象
 *   3 「想起来了」   黄    勉强通过，间隔小幅前进
 *   4 「容易」       绿    正确，间隔正常前进
 *   5 「太简单」     蓝    EF 略升，下次间隔加长
 */

import { EffectiveTheme } from '../../../core/theme/Theme.types';
import {
  useColor,
  TextColors,
  BgColors,
  BorderColors,
  AccentColors,
  StateColors,
  BrandPalette,
  ColorPalette,
} from '../../../core/theme/AppColors';
import {
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius, Elevation, MotionEasing } from '../../../core/theme/AppSpacing';
import { ToastManager } from '../../../ui/primitives/Toast';
import { VocabDetailSheet, VocabDetailActions } from '../../../features/vocab/components/VocabDetailSheet';
import {
  NotesApi,
  VocabNoteRecord,
} from '../../../api/notes/NotesApi';
import { TtsService } from '../../../features/audiobook/service/TtsService';
import router from '@ohos.router';

// ─────────────────────────────────────────────
// 类型 + 常量
// ─────────────────────────────────────────────

type SessionPhase = 'loading' | 'reviewing' | 'finished' | 'error';
type CardSide = 'front' | 'back';

type Quality = 0 | 1 | 2 | 3 | 4 | 5;

interface QualityOption {
  quality: Quality;
  label: string;
  hint: string;
  /** 主色（按钮背景） */
  color: string;
}

// 与后端 applySm2 quality 解读对齐：q<3 视为遗忘；q>=3 通过
const QUALITY_OPTIONS: QualityOption[] = [
  { quality: 0, label: '不认识',     hint: '间隔重置',    color: ColorPalette.red500     },
  { quality: 2, label: '想起一些',   hint: '没通过',      color: ColorPalette.orange500  },
  { quality: 3, label: '想起来了',   hint: '吃力',        color: ColorPalette.yellow500  },
  { quality: 4, label: '容易',       hint: '正常前进',    color: ColorPalette.green500   },
  { quality: 5, label: '太简单',     hint: '间隔加长',    color: ColorPalette.blue500    },
];

// ─────────────────────────────────────────────
// 主组件
// ─────────────────────────────────────────────

@Entry
@Component
struct FlashcardSession {
  @Provide('theme') theme: EffectiveTheme = 'day';

  @State private phase: SessionPhase = 'loading';
  @State private queue: VocabNoteRecord[] = [];
  @State private cursor: number = 0;
  @State private side: CardSide = 'front';
  @State private flipDeg: number = 0;
  @State private submitting: boolean = false;

  /** 会话统计 */
  @State private reviewedCount: number = 0;
  @State private correctCount: number = 0;
  @State private startedAt: number = Date.now();

  private detailController: CustomDialogController | null = null;

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  private get current(): VocabNoteRecord | null {
    if (this.cursor < 0 || this.cursor >= this.queue.length) return null;
    return this.queue[this.cursor];
  }

  private get total(): number {
    return this.queue.length;
  }

  // ─── lifecycle ──────────────────────────────────────────

  aboutToAppear(): void {
    this.startedAt = Date.now();
    this.fetchDue();
  }

  aboutToDisappear(): void {
    if (this.detailController) {
      this.detailController.close();
      this.detailController = null;
    }
  }

  // ─── 数据 ───────────────────────────────────────────────

  private async fetchDue(): Promise<void> {
    this.phase = 'loading';
    try {
      const list = await NotesApi.getDue({ count: 50 });
      this.queue = list;
      this.cursor = 0;
      this.side = 'front';
      this.flipDeg = 0;
      this.phase = list.length > 0 ? 'reviewing' : 'finished';
    } catch (_e) {
      this.phase = 'error';
      this.queue = [];
    }
  }

  // ─── 卡片状态机 ─────────────────────────────────────────

  private flipCard(): void {
    if (this.submitting) return;
    const target = this.side === 'front' ? 180 : 0;
    animateTo(
      { duration: 400, curve: MotionEasing.standard },
      () => {
        this.flipDeg = target;
      },
    );
    this.side = this.side === 'front' ? 'back' : 'front';
  }

  private async submitQuality(q: Quality): Promise<void> {
    const cur = this.current;
    if (!cur || this.submitting) return;
    this.submitting = true;
    try {
      await NotesApi.submitReview({ vocabNoteId: cur.id, quality: q });
      this.reviewedCount += 1;
      if (q >= 3) this.correctCount += 1;
      this.advance();
    } catch (_e) {
      ToastManager.show({ message: '提交失败，请重试', type: 'error' });
    } finally {
      this.submitting = false;
    }
  }

  private advance(): void {
    // 翻回正面 → 切下一张 → 队列空则结束
    this.side = 'front';
    this.flipDeg = 0;
    if (this.cursor + 1 >= this.queue.length) {
      this.phase = 'finished';
    } else {
      this.cursor += 1;
    }
  }

  private skipCard(): void {
    if (this.submitting) return;
    // 跳过 = quality 0（不增加 correct，但记入 reviewedCount）
    this.submitQuality(0);
  }

  private playTts(): void {
    const cur = this.current;
    if (!cur) return;
    const text = cur.exampleSentence
      ? `${cur.word}. ${cur.exampleSentence}`
      : cur.word;
    TtsService.getInstance().speak(text).catch(() => {
      ToastManager.show({ message: '朗读失败', type: 'error' });
    });
  }

  private openDetail(): void {
    const cur = this.current;
    if (!cur) return;
    const actions: VocabDetailActions = {
      onMarkKnown: () => {
        // 标记掌握 → 视为 quality 5 提交并前进
        this.submitQuality(5);
      },
      onDelete: async (v) => {
        try {
          await NotesApi.deleteVocab(v.id);
          // 从队列移除
          this.queue = this.queue.filter((x) => x.id !== v.id);
          if (this.cursor >= this.queue.length) {
            this.phase = this.queue.length === 0 ? 'finished' : 'reviewing';
            if (this.queue.length > 0) this.cursor = this.queue.length - 1;
          }
          ToastManager.show({ message: '已删除', type: 'success' });
        } catch (_e) {
          ToastManager.show({ message: '删除失败', type: 'error' });
        }
      },
      onSave: async (v, _note, tags) => {
        try {
          await NotesApi.updateVocab(v.id, {
            userTag: tags[0],
            aiTags: tags.length > 1 ? tags.slice(1) : undefined,
          });
        } catch (_e) { /* ignore */ }
      },
      onTtsRead: (text) => {
        TtsService.getInstance().speak(text).catch(() => {});
      },
      onClose: () => {},
    };
    this.detailController = new CustomDialogController({
      builder: VocabDetailSheet({
        vocab: cur,
        theme: this.theme,
        actions,
      }),
      alignment: DialogAlignment.Bottom,
      customStyle: true,
      autoCancel: true,
    });
    this.detailController.open();
  }

  // ─── builders ───────────────────────────────────────────

  @Builder
  topBar() {
    Row() {
      Text('\u{2039}')
        .fontSize(FontSizeToken.title2)
        .fontColor(useColor(AccentColors.primary, this.isDark))
        .padding(Spacing.s2)
        .onClick(() => router.back())
      Text('闪卡复习')
        .fontSize(FontSizeToken.headline)
        .fontWeight(FontWeightToken.semibold)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text('\u{2715}')
        .fontSize(FontSizeToken.title3)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
        .padding(Spacing.s2)
        .onClick(() => router.back())
    }
    .width('100%')
    .padding({ left: Spacing.s2, right: Spacing.s2 })
  }

  @Builder
  progressBar() {
    Column({ space: Spacing.s1 }) {
      Row() {
        Text(`${this.cursor + 1} / ${this.total}`)
          .fontSize(FontSizeToken.caption1)
          .fontColor(useColor(TextColors.secondary, this.isDark))
        Blank()
        Text(`已答对 ${this.correctCount}`)
          .fontSize(FontSizeToken.caption1)
          .fontColor(useColor(StateColors.success, this.isDark))
      }
      .width('100%')

      // 进度条
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(4)
          .backgroundColor(useColor(BgColors.secondary, this.isDark))
          .borderRadius(Radius.full)
        Row()
          .width(`${this.total === 0 ? 0 : Math.floor(((this.cursor) / this.total) * 100)}%`)
          .height(4)
          .backgroundColor(useColor(AccentColors.primary, this.isDark))
          .borderRadius(Radius.full)
      }
      .width('100%')
    }
    .width('92%')
  }

  @Builder
  cardFront(v: VocabNoteRecord) {
    Column({ space: Spacing.s3 }) {
      // CEFR + 来源
      Row({ space: Spacing.s2 }) {
        if (v.difficulty !== null && v.difficulty !== undefined) {
          Text(`CEFR L${v.difficulty}`)
            .fontSize(FontSizeToken.caption1)
            .fontColor(useColor(TextColors.inverse, this.isDark))
            .padding({ left: Spacing.s2, right: Spacing.s2, top: 2, bottom: 2 })
            .borderRadius(Radius.sm)
            .backgroundColor(useColor(AccentColors.primary, this.isDark))
        }
        if (v.sourceBookId) {
          Text(`\u{1F4D6} ${v.sourceBookId}`)
            .fontSize(FontSizeToken.caption1)
            .fontColor(useColor(TextColors.tertiary, this.isDark))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Blank()
      }
      .width('100%')

      Blank()

      Text(v.word)
        .fontSize(40)
        .fontWeight(FontWeightToken.bold)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (v.pronunciation) {
        Text(`/${v.pronunciation}/`)
          .fontSize(FontSizeToken.callout)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
          .textAlign(TextAlign.Center)
          .width('100%')
      }

      Row({ space: Spacing.s4 }) {
        Text('\u{1F50A} 朗读')
          .fontSize(FontSizeToken.subheadline)
          .fontColor(useColor(AccentColors.primary, this.isDark))
          .padding({ left: Spacing.s3, right: Spacing.s3, top: Spacing.s1, bottom: Spacing.s1 })
          .borderRadius(Radius.full)
          .border({ width: 1, color: useColor(AccentColors.primary, this.isDark) })
          .onClick(() => this.playTts())
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')

      Blank()

      Text('\u{1F446} 点击卡片查看释义')
        .fontSize(FontSizeToken.caption1)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(Spacing.s5)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  cardBack(v: VocabNoteRecord) {
    // 注意：rotateY 180 后，子元素需要再次 rotateY 180 才能正常阅读
    Column({ space: Spacing.s3 }) {
      Row({ space: Spacing.s2 }) {
        Text(v.word)
          .fontSize(FontSizeToken.title3)
          .fontWeight(FontWeightToken.bold)
          .fontColor(useColor(TextColors.primary, this.isDark))
        if (v.partOfSpeech) {
          Text(v.partOfSpeech)
            .fontSize(FontSizeToken.caption1)
            .fontColor(useColor(AccentColors.primary, this.isDark))
            .padding({ left: Spacing.s1, right: Spacing.s1, top: 2, bottom: 2 })
            .borderRadius(Radius.sm)
            .backgroundColor(BrandPalette.b50)
        }
        Blank()
        Text('\u{1F50A}')
          .fontSize(FontSizeToken.title3)
          .padding(Spacing.s1)
          .onClick(() => this.playTts())
      }
      .width('100%')

      if (v.definition) {
        Text(v.definition)
          .fontSize(FontSizeToken.body)
          .fontColor(useColor(TextColors.primary, this.isDark))
          .lineHeight(LineHeightToken.body)
          .width('100%')
      }

      if (v.exampleSentence) {
        Column({ space: Spacing.s1 }) {
          Text('例句')
            .fontSize(FontSizeToken.caption1)
            .fontWeight(FontWeightToken.medium)
            .fontColor(useColor(TextColors.tertiary, this.isDark))
          Text(v.exampleSentence)
            .fontSize(FontSizeToken.subheadline)
            .fontColor(useColor(TextColors.primary, this.isDark))
            .fontStyle(FontStyle.Italic)
            .lineHeight(LineHeightToken.subheadline)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(Spacing.s3)
        .backgroundColor(useColor(BgColors.secondary, this.isDark))
        .borderRadius(Radius.md)
      }

      if (v.sourceContext && v.sourceContext.length > 0) {
        Column({ space: Spacing.s1 }) {
          Text('上下文')
            .fontSize(FontSizeToken.caption1)
            .fontWeight(FontWeightToken.medium)
            .fontColor(useColor(TextColors.tertiary, this.isDark))
          Text(v.sourceContext)
            .fontSize(FontSizeToken.footnote)
            .fontColor(useColor(TextColors.secondary, this.isDark))
            .lineHeight(LineHeightToken.footnote)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding(Spacing.s5)
    .rotate({ x: 0, y: 1, z: 0, angle: 180, centerX: '50%', centerY: '50%' })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  card() {
    Stack() {
      // 卡片本体 — 通过 rotate 旋转角度切换正反面
      Column() {
        if (this.side === 'front' && this.current) {
          this.cardFront(this.current)
        } else if (this.current) {
          this.cardBack(this.current)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(useColor(BgColors.elevated, this.isDark))
      .borderRadius(Radius.xl)
      .border({ width: 1, color: useColor(BorderColors.secondary, this.isDark) })
      .shadow(Elevation.e3)
      .rotate({ x: 0, y: 1, z: 0, angle: this.flipDeg, centerX: '50%', centerY: '50%' })
      .onClick(() => this.flipCard())
    }
    .width('92%')
    .height('60%')
  }

  @Builder
  qualityButtons() {
    Column({ space: Spacing.s2 }) {
      Text('你对这个词的掌握程度？')
        .fontSize(FontSizeToken.caption1)
        .fontColor(useColor(TextColors.secondary, this.isDark))
      Row({ space: Spacing.s2 }) {
        ForEach(
          QUALITY_OPTIONS,
          (opt: QualityOption) => {
            this.qualityButton(opt)
          },
          (opt: QualityOption) => `q${opt.quality}`,
        )
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('92%')
    .padding({ top: Spacing.s2 })
  }

  @Builder
  qualityButton(opt: QualityOption) {
    Column({ space: 2 }) {
      Text(opt.label)
        .fontSize(FontSizeToken.footnote)
        .fontWeight(FontWeightToken.semibold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
      Text(opt.hint)
        .fontSize(FontSizeToken.caption2)
        .fontColor('#FFFFFFCC')
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .padding({ top: Spacing.s2, bottom: Spacing.s2, left: Spacing.s1, right: Spacing.s1 })
    .borderRadius(Radius.md)
    .backgroundColor(opt.color)
    .opacity(this.submitting ? 0.5 : 1)
    .onClick(() => this.submitQuality(opt.quality))
  }

  @Builder
  bottomActionBar() {
    Row({ space: Spacing.s4 }) {
      Text('\u{23ED} 跳过')
        .fontSize(FontSizeToken.subheadline)
        .fontColor(useColor(TextColors.secondary, this.isDark))
        .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s1, bottom: Spacing.s1 })
        .borderRadius(Radius.full)
        .backgroundColor(useColor(BgColors.secondary, this.isDark))
        .onClick(() => this.skipCard())
      Blank()
      Text('\u{270F} 编辑')
        .fontSize(FontSizeToken.subheadline)
        .fontColor(useColor(TextColors.secondary, this.isDark))
        .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s1, bottom: Spacing.s1 })
        .borderRadius(Radius.full)
        .backgroundColor(useColor(BgColors.secondary, this.isDark))
        .onClick(() => this.openDetail())
    }
    .width('92%')
  }

  @Builder
  finishedView() {
    Column({ space: Spacing.s4 }) {
      Text('\u{1F389}')
        .fontSize(72)
        .textAlign(TextAlign.Center)
      Text(this.reviewedCount === 0 ? '今日暂无待复习生词' : '本轮复习完成！')
        .fontSize(FontSizeToken.title2)
        .fontWeight(FontWeightToken.bold)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .textAlign(TextAlign.Center)

      if (this.reviewedCount > 0) {
        Row({ space: Spacing.s6 }) {
          Column({ space: 2 }) {
            Text(`${this.reviewedCount}`)
              .fontSize(FontSizeToken.title2)
              .fontWeight(FontWeightToken.bold)
              .fontColor(useColor(AccentColors.primary, this.isDark))
            Text('已复习')
              .fontSize(FontSizeToken.caption1)
              .fontColor(useColor(TextColors.secondary, this.isDark))
          }
          .alignItems(HorizontalAlign.Center)

          Column({ space: 2 }) {
            Text(`${Math.round((this.correctCount / this.reviewedCount) * 100)}%`)
              .fontSize(FontSizeToken.title2)
              .fontWeight(FontWeightToken.bold)
              .fontColor(useColor(StateColors.success, this.isDark))
            Text('正确率')
              .fontSize(FontSizeToken.caption1)
              .fontColor(useColor(TextColors.secondary, this.isDark))
          }
          .alignItems(HorizontalAlign.Center)

          Column({ space: 2 }) {
            Text(`${Math.max(1, Math.round((Date.now() - this.startedAt) / 60000))}m`)
              .fontSize(FontSizeToken.title2)
              .fontWeight(FontWeightToken.bold)
              .fontColor(useColor(TextColors.primary, this.isDark))
            Text('用时')
              .fontSize(FontSizeToken.caption1)
              .fontColor(useColor(TextColors.secondary, this.isDark))
          }
          .alignItems(HorizontalAlign.Center)
        }
        .padding(Spacing.s4)
        .backgroundColor(useColor(BgColors.elevated, this.isDark))
        .borderRadius(Radius.lg)
      }

      Row({ space: Spacing.s2 }) {
        Text('再来一轮')
          .fontSize(FontSizeToken.body)
          .fontWeight(FontWeightToken.medium)
          .fontColor(useColor(TextColors.inverse, this.isDark))
          .padding({ left: Spacing.s5, right: Spacing.s5, top: Spacing.s2, bottom: Spacing.s2 })
          .borderRadius(Radius.full)
          .backgroundColor(useColor(AccentColors.primary, this.isDark))
          .onClick(() => {
            this.reviewedCount = 0;
            this.correctCount = 0;
            this.startedAt = Date.now();
            this.fetchDue();
          })

        Text('返回')
          .fontSize(FontSizeToken.body)
          .fontWeight(FontWeightToken.medium)
          .fontColor(useColor(TextColors.primary, this.isDark))
          .padding({ left: Spacing.s5, right: Spacing.s5, top: Spacing.s2, bottom: Spacing.s2 })
          .borderRadius(Radius.full)
          .backgroundColor(useColor(BgColors.secondary, this.isDark))
          .onClick(() => router.back())
      }
    }
    .width('100%')
    .height('100%')
    .padding(Spacing.s5)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  loadingView() {
    Column({ space: Spacing.s3 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(useColor(AccentColors.primary, this.isDark))
      Text('加载待复习生词...')
        .fontSize(FontSizeToken.subheadline)
        .fontColor(useColor(TextColors.secondary, this.isDark))
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  errorView() {
    Column({ space: Spacing.s3 }) {
      Text('\u{26A0}')
        .fontSize(48)
      Text('加载失败')
        .fontSize(FontSizeToken.title3)
        .fontColor(useColor(TextColors.primary, this.isDark))
      Text('请检查网络后重试')
        .fontSize(FontSizeToken.subheadline)
        .fontColor(useColor(TextColors.secondary, this.isDark))
      Text('重试')
        .fontSize(FontSizeToken.body)
        .fontColor(useColor(TextColors.inverse, this.isDark))
        .padding({ left: Spacing.s5, right: Spacing.s5, top: Spacing.s2, bottom: Spacing.s2 })
        .borderRadius(Radius.full)
        .backgroundColor(useColor(AccentColors.primary, this.isDark))
        .onClick(() => this.fetchDue())
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  // ─── build ──────────────────────────────────────────────

  build() {
    Column({ space: Spacing.s3 }) {
      this.topBar()

      if (this.phase === 'loading') {
        this.loadingView()
      } else if (this.phase === 'error') {
        this.errorView()
      } else if (this.phase === 'finished') {
        this.finishedView()
      } else {
        // reviewing
        this.progressBar()
        this.card()
        if (this.side === 'back') {
          this.qualityButtons()
        }
        this.bottomActionBar()
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: Spacing.s2, bottom: Spacing.s4 })
    .backgroundColor(useColor(BgColors.primary, this.isDark))
    .alignItems(HorizontalAlign.Center)
  }
}
