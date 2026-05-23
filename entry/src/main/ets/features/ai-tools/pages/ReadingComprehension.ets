/**
 * ReadingComprehension.ets — W9-C7 阅读理解题
 *
 * 流程：
 *   loading 生成（AI 调 contentQA）
 *   → 答题：每题展示原文 quote / prompt / options（mcq）/ TextArea（fill,short）
 *   → 提交：调 StudyPlanApi.submitAnswer 拿 evaluation
 *   → 全部完成：总分 + 弱点反馈 + 历史持久化
 *
 * 难度自适应（W9-C7）：
 *   历史评估按 type 聚合错误率 → weaknessBias 传给下次 generate
 *   错误率 > 0.4 的题型权重 += 0.5
 *
 * 历史：最近 10 次 attempt 持久化在 Preferences['settings_comprehension_history']
 */

import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import { AppButton } from '../../../ui/primitives/Button';
import { AppCard } from '../../../ui/primitives/Card';
import { ToastManager } from '../../../ui/primitives/Toast';
import { PreferencesManager } from '../../../core/persistence/PreferencesManager';
import {
  StudyPlanApi,
  ComprehensionQuestion,
  AnswerEvaluation,
  ComprehensionAttempt,
  QuestionType,
} from '../../../api/study/StudyPlanApi';

const HISTORY_KEY = 'settings_comprehension_history';
const HISTORY_MAX = 10;

interface ComprehensionParams {
  bookId: string;
  chapterIndex: number;
}

type Phase = 'loading' | 'answering' | 'finished' | 'error';

@Component
export struct ReadingComprehensionPage {
  @State phase: Phase = 'loading';
  @State questions: ComprehensionQuestion[] = [];
  @State answers: string[] = [];
  @State evaluations: AnswerEvaluation[] = [];
  @State currentIdx: number = 0;
  @State submitting: boolean = false;
  @State errMsg: string = '';
  @State totalScore: number = 0;
  @State weaknessFeedback: string = '';
  @State history: ComprehensionAttempt[] = [];

  private bookId: string = 'demo';
  private chapterIndex: number = 0;

  aboutToAppear(): void {
    const params = RouterService.getParams<ComprehensionParams>('ReadingComprehension');
    if (params) {
      this.bookId = params.bookId;
      this.chapterIndex = params.chapterIndex;
    }
    this.loadHistory().then(() => this.startNewAttempt());
  }

  private async loadHistory(): Promise<void> {
    const raw = await PreferencesManager.getString(HISTORY_KEY, '');
    if (!raw) return;
    try {
      this.history = JSON.parse(raw) as ComprehensionAttempt[];
    } catch (_e) {
      this.history = [];
    }
  }

  /**
   * W9-C7 难度自适应：基于历史 evaluations 算每种题型错误率，
   * 错误率 > 0.4 的题型在下次出题时加权。
   */
  private computeWeaknessBias(): Partial<Record<QuestionType, number>> {
    const counts: Record<QuestionType, { right: number; total: number }> = {
      mcq: { right: 0, total: 0 },
      fill: { right: 0, total: 0 },
      short: { right: 0, total: 0 },
    };
    for (const att of this.history) {
      for (const q of att.questions) {
        const e = att.evaluations.find((x) => x.questionId === q.id);
        if (!e) continue;
        counts[q.type].total += 1;
        if (e.correct) counts[q.type].right += 1;
      }
    }
    const bias: Partial<Record<QuestionType, number>> = {};
    (Object.keys(counts) as QuestionType[]).forEach((t) => {
      const c = counts[t];
      if (c.total < 3) return;
      const errRate = 1 - c.right / c.total;
      if (errRate > 0.4) bias[t] = Number((1 + errRate).toFixed(2));
    });
    return bias;
  }

  private async startNewAttempt(): Promise<void> {
    this.phase = 'loading';
    this.errMsg = '';
    try {
      const bias = this.computeWeaknessBias();
      this.questions = await StudyPlanApi.generateComprehension(this.bookId, this.chapterIndex, bias);
      this.answers = this.questions.map(() => '');
      this.evaluations = [];
      this.currentIdx = 0;
      this.phase = 'answering';
    } catch (e) {
      this.errMsg = (e as Error).message ?? 'unknown_error';
      this.phase = 'error';
    }
  }

  private setAnswer(v: string): void {
    if (this.currentIdx < 0 || this.currentIdx >= this.answers.length) return;
    this.answers[this.currentIdx] = v;
  }

  private async submitAll(): Promise<void> {
    this.submitting = true;
    try {
      const evals: AnswerEvaluation[] = [];
      for (let i = 0; i < this.questions.length; i++) {
        const q = this.questions[i];
        const ans = this.answers[i] ?? '';
        if (!ans) {
          evals.push({
            questionId: q.id,
            userAnswer: '',
            correct: false,
            score: 0,
            explanation: '未作答',
            reference: q.answer,
          });
          continue;
        }
        try {
          const e = await StudyPlanApi.submitAnswer(q, ans);
          evals.push(e);
        } catch (_e) {
          evals.push({
            questionId: q.id,
            userAnswer: ans,
            correct: false,
            score: 0,
            explanation: 'AI 评分失败',
            reference: q.answer,
          });
        }
      }
      this.evaluations = evals;
      const total = evals.reduce((s, e) => s + e.score, 0);
      this.totalScore = Math.round(total / Math.max(1, evals.length));
      this.weaknessFeedback = this.buildWeaknessFeedback(evals);
      await this.persistAttempt();
      this.phase = 'finished';
    } finally {
      this.submitting = false;
    }
  }

  private buildWeaknessFeedback(evals: AnswerEvaluation[]): string {
    const wrongByType: Record<QuestionType, number> = { mcq: 0, fill: 0, short: 0 };
    for (let i = 0; i < this.questions.length; i++) {
      const q = this.questions[i];
      const e = evals[i];
      if (e && !e.correct) wrongByType[q.type] += 1;
    }
    const parts: string[] = [];
    if (wrongByType.mcq > 0) parts.push(`选择题错 ${wrongByType.mcq} 道：注意细节理解`);
    if (wrongByType.fill > 0) parts.push(`填空题错 ${wrongByType.fill} 道：加强词汇与上下文`);
    if (wrongByType.short > 0) parts.push(`简答题错 ${wrongByType.short} 道：练习概括能力`);
    return parts.length === 0 ? '全对，继续保持。' : parts.join('；');
  }

  private async persistAttempt(): Promise<void> {
    const attempt: ComprehensionAttempt = {
      id: `att_${Date.now()}`,
      bookId: this.bookId,
      chapterIndex: this.chapterIndex,
      questions: this.questions,
      evaluations: this.evaluations,
      totalScore: this.totalScore,
      weaknessFeedback: this.weaknessFeedback,
      createdAt: new Date().toISOString(),
    };
    const next = [attempt, ...this.history].slice(0, HISTORY_MAX);
    this.history = next;
    await PreferencesManager.setString(HISTORY_KEY, JSON.stringify(next));
  }

  // ---- UI ----

  build() {
    NavDestination() {
      Column() {
        if (this.phase === 'loading') this.loadingView()
        else if (this.phase === 'error') this.errorView()
        else if (this.phase === 'answering') this.answeringView()
        else this.finishedView()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgPrimary)
    }
    .title('阅读理解')
    .onBackPressed(() => { RouterService.back(); return true; })
  }

  @Builder
  loadingView() {
    Column({ space: AppSpacing.base }) {
      LoadingProgress().width(48).height(48).color(AppColors.brand)
      Text('AI 正在生成题目……')
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textSecondary)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  errorView() {
    Column({ space: AppSpacing.base }) {
      Text('出题失败')
        .fontSize(AppFontSize.md)
        .fontColor(AppColors.danger)
      Text(this.errMsg)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textSecondary)
      AppButton({
        label: '重试',
        variant: 'primary',
        onClick: () => this.startNewAttempt(),
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(AppSpacing.lg)
  }

  @Builder
  answeringView() {
    Scroll() {
      Column({ space: AppSpacing.base }) {
        Row() {
          Text(`第 ${this.currentIdx + 1} / ${this.questions.length} 题`)
            .fontSize(AppFontSize.md)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textPrimary)
            .layoutWeight(1)
          Text(this.typeLabel(this.questions[this.currentIdx].type))
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.brand)
            .padding({ left: AppSpacing.sm, right: AppSpacing.sm, top: 2, bottom: 2 })
            .borderRadius(AppRadius.sm)
            .backgroundColor(AppColors.bgSecondary)
        }
        .width('100%')

        this.questionCard(this.questions[this.currentIdx])

        Row({ space: AppSpacing.sm }) {
          AppButton({
            label: '上一题',
            variant: 'ghost',
            disabled: this.currentIdx === 0,
            onClick: () => { if (this.currentIdx > 0) this.currentIdx -= 1; },
          })
          if (this.currentIdx < this.questions.length - 1) {
            AppButton({
              label: '下一题',
              variant: 'primary',
              onClick: () => { this.currentIdx += 1; },
            })
          } else {
            AppButton({
              label: this.submitting ? '提交中…' : '提交全部',
              variant: 'primary',
              loading: this.submitting,
              disabled: this.submitting,
              onClick: () => this.submitAll(),
            })
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .padding(AppSpacing.base)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  questionCard(q: ComprehensionQuestion) {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Column({ space: AppSpacing.sm }) {
        if (q.quote && q.quote.length > 0) {
          Text(`"${q.quote}"`)
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
            .padding(AppSpacing.sm)
            .backgroundColor(AppColors.bgSecondary)
            .borderRadius(AppRadius.sm)
        }
        Text(q.prompt)
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)

        if (q.type === 'mcq' && q.options && q.options.length > 0) {
          ForEach(q.options, (opt: string) => {
            Row({ space: AppSpacing.sm }) {
              Radio({ value: opt, group: `q_${q.id}` })
                .checked(this.answers[this.currentIdx] === opt)
                .onChange((on: boolean) => { if (on) this.setAnswer(opt); })
              Text(opt)
                .fontSize(AppFontSize.sm)
                .fontColor(AppColors.textPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: AppSpacing.xs, bottom: AppSpacing.xs })
          }, (opt: string, idx: number) => `${q.id}_${idx}`)
        } else {
          TextArea({
            text: this.answers[this.currentIdx] ?? '',
            placeholder: q.type === 'fill' ? '填空' : '请输入你的答案',
          })
            .fontSize(AppFontSize.md)
            .height(q.type === 'short' ? 120 : 60)
            .backgroundColor(AppColors.bgSecondary)
            .borderRadius(AppRadius.sm)
            .onChange((v: string) => this.setAnswer(v))
        }
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  finishedView() {
    Scroll() {
      Column({ space: AppSpacing.base }) {
        AppCard({ variant: 'elevated', padding: 'md' }) {
          Column({ space: AppSpacing.sm }) {
            Text('得分')
              .fontSize(AppFontSize.sm)
              .fontColor(AppColors.textSecondary)
            Text(`${this.totalScore}`)
              .fontSize(48)
              .fontWeight(AppFontWeight.bold)
              .fontColor(AppColors.brand)
            Text(this.weaknessFeedback)
              .fontSize(AppFontSize.sm)
              .fontColor(AppColors.textPrimary)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')

        ForEach(this.questions, (q: ComprehensionQuestion, idx: number) => {
          this.evalCard(q, this.evaluations[idx])
        }, (q: ComprehensionQuestion) => q.id)

        Row({ space: AppSpacing.sm }) {
          AppButton({
            label: '再来一组',
            variant: 'secondary',
            onClick: () => this.startNewAttempt(),
          })
          AppButton({
            label: '返回',
            variant: 'primary',
            onClick: () => RouterService.back(),
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)

        if (this.history.length > 0) {
          this.historyCard()
        }
      }
      .width('100%')
      .padding(AppSpacing.base)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  evalCard(q: ComprehensionQuestion, e: AnswerEvaluation) {
    AppCard({ variant: 'outlined', padding: 'md' }) {
      Column({ space: AppSpacing.xs }) {
        Row() {
          Text(this.typeLabel(q.type))
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
            .layoutWeight(1)
          Text(e?.correct ? '✓ 正确' : '✗ 错误')
            .fontSize(AppFontSize.sm)
            .fontColor(e?.correct ? AppColors.brand : AppColors.danger)
        }
        .width('100%')
        Text(q.prompt)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textPrimary)
        Text(`你的答案：${e?.userAnswer || '（未作答）'}`)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textSecondary)
        Text(`参考答案：${e?.reference ?? q.answer}`)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textSecondary)
        if (e?.explanation) {
          Text(e.explanation)
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  historyCard() {
    AppCard({ variant: 'filled', padding: 'md' }) {
      Column({ space: AppSpacing.xs }) {
        Text('历史记录（最近 10 次）')
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
        ForEach(this.history, (h: ComprehensionAttempt) => {
          Row() {
            Text(h.createdAt.slice(0, 10))
              .fontSize(AppFontSize.xs)
              .fontColor(AppColors.textSecondary)
              .width(90)
            Text(`${h.bookId} 第 ${h.chapterIndex} 章`)
              .fontSize(AppFontSize.xs)
              .fontColor(AppColors.textPrimary)
              .layoutWeight(1)
            Text(`${h.totalScore} 分`)
              .fontSize(AppFontSize.sm)
              .fontWeight(AppFontWeight.bold)
              .fontColor(h.totalScore >= 80 ? AppColors.brand : AppColors.textSecondary)
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
        }, (h: ComprehensionAttempt) => h.id)
      }
      .width('100%')
    }
    .width('100%')
  }

  private typeLabel(t: QuestionType): string {
    return t === 'mcq' ? '选择题' : t === 'fill' ? '填空题' : '简答题';
  }
}
