/**
 * StudyPlan.ets — W9-C6 AI 个性化学习计划
 *
 * 流程：
 *   未生成   → 输入引导（CEFR / 目标 / 时长 / 兴趣 / 截止日期）→ 生成
 *   已生成   → 展示：进度条 / 当日任务 + checkbox / 周视图 切换 / 重新生成
 *
 * 持久化：完整 plan JSON 持久化到 PreferencesManager['settings_study_plan']。
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
  StudyPlan,
  StudyPlanInput,
  StudyTask,
  DailyPlan,
  CefrLevel,
} from '../../../api/study/StudyPlanApi';

const STORAGE_KEY = 'settings_study_plan';

type ViewMode = 'day' | 'week';

@Component
export struct StudyPlanPage {
  @State plan: StudyPlan | null = null;
  @State loading: boolean = false;
  @State errMsg: string = '';
  @State viewMode: ViewMode = 'day';

  // 表单字段
  @State currentLevel: CefrLevel = 'A2';
  @State targetLevel: CefrLevel = 'B2';
  @State dailyMinutesText: string = '30';
  @State interestsText: string = '小说,商业,科技';
  @State deadlineText: string = '';

  aboutToAppear(): void {
    this.loadFromCache();
  }

  private async loadFromCache(): Promise<void> {
    const raw = await PreferencesManager.getString(STORAGE_KEY, '');
    if (!raw) return;
    try {
      this.plan = JSON.parse(raw) as StudyPlan;
    } catch (_e) {
      this.plan = null;
    }
  }

  private async persist(): Promise<void> {
    if (!this.plan) {
      await PreferencesManager.remove(STORAGE_KEY);
      return;
    }
    await PreferencesManager.setString(STORAGE_KEY, JSON.stringify(this.plan));
  }

  private async generate(): Promise<void> {
    const minutes = parseInt(this.dailyMinutesText, 10);
    if (!minutes || minutes < 5 || minutes > 240) {
      ToastManager.error('每日时长需在 5-240 分钟之间');
      return;
    }
    const input: StudyPlanInput = {
      currentLevel: this.currentLevel,
      targetLevel: this.targetLevel,
      dailyMinutes: minutes,
      interests: this.interestsText
        .split(/[,，、\s]+/)
        .map((s) => s.trim())
        .filter((s) => s.length > 0),
      deadline: this.deadlineText.trim() || undefined,
    };
    this.loading = true;
    this.errMsg = '';
    try {
      const plan = await StudyPlanApi.generatePlan(input);
      this.plan = plan;
      await this.persist();
      ToastManager.success('学习计划已生成');
    } catch (e) {
      this.errMsg = (e as Error).message ?? 'unknown_error';
      ToastManager.error('生成失败：' + this.errMsg);
    } finally {
      this.loading = false;
    }
  }

  private async toggleTask(taskId: string, completed: boolean): Promise<void> {
    if (!this.plan) return;
    const updated = await StudyPlanApi.updatePlanProgress(this.plan, taskId, completed);
    this.plan = updated;
    await this.persist();
  }

  private async regenerate(): Promise<void> {
    AlertDialog.show({
      title: '重新生成？',
      message: '当前计划与已完成进度将被覆盖。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '重新生成',
        fontColor: AppColors.danger,
        action: () => { this.generate(); },
      },
    });
  }

  private currentDay(): number {
    if (!this.plan) return 1;
    const ms = Date.now() - new Date(this.plan.createdAt).getTime();
    const d = Math.floor(ms / 86400_000) + 1;
    return Math.max(1, Math.min(d, this.plan.totalDays));
  }

  private todayTasks(): StudyTask[] {
    if (!this.plan) return [];
    const day = this.currentDay();
    const found = this.plan.daily.find((d) => d.day === day);
    return found?.tasks ?? [];
  }

  private currentWeek(): DailyPlan[] {
    if (!this.plan) return [];
    const today = this.currentDay();
    const start = Math.floor((today - 1) / 7) * 7 + 1;
    return this.plan.daily.filter((d) => d.day >= start && d.day < start + 7);
  }

  // ---- UI ----

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: AppSpacing.base }) {
          this.header()
          if (this.loading) {
            this.loadingView()
          } else if (!this.plan) {
            this.intakeForm()
          } else {
            this.planView()
          }
        }
        .width('100%')
        .padding(AppSpacing.base)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgPrimary)
    }
    .title('学习计划')
    .onBackPressed(() => { RouterService.back(); return true; })
  }

  @Builder
  header() {
    Row() {
      Text('AI 学习计划')
        .fontSize(AppFontSize.xl)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .layoutWeight(1)
      if (this.plan) {
        AppButton({
          label: '重新生成',
          variant: 'ghost',
          size: 'sm',
          onClick: () => this.regenerate(),
        })
      }
    }
    .width('100%')
  }

  @Builder
  loadingView() {
    Column({ space: AppSpacing.base }) {
      LoadingProgress().width(48).height(48).color(AppColors.brand)
      Text('AI 正在生成计划……')
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textSecondary)
    }
    .width('100%')
    .padding(AppSpacing.lg)
    .alignItems(HorizontalAlign.Center)
  }

  // ---- 表单（intake form） ----

  @Builder
  intakeForm() {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Column({ space: AppSpacing.base }) {
        Text('告诉我你的学习目标')
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)

        this.cefrPicker('当前水平', this.currentLevel, (v: CefrLevel) => { this.currentLevel = v; })
        this.cefrPicker('目标水平', this.targetLevel, (v: CefrLevel) => { this.targetLevel = v; })

        this.formField('每日学习时长（分钟）', this.dailyMinutesText,
          (v: string) => { this.dailyMinutesText = v; }, 'number')
        this.formField('兴趣主题（用逗号分隔）', this.interestsText,
          (v: string) => { this.interestsText = v; })
        this.formField('截止日期 YYYY-MM-DD（可选）', this.deadlineText,
          (v: string) => { this.deadlineText = v; })

        AppButton({
          label: '生成学习计划',
          variant: 'primary',
          size: 'lg',
          onClick: () => this.generate(),
        })
        if (this.errMsg) {
          Text(this.errMsg)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.danger)
        }
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  cefrPicker(label: string, value: CefrLevel, onChange: (v: CefrLevel) => void) {
    Column({ space: AppSpacing.xs }) {
      Text(label)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textSecondary)
      Row({ space: AppSpacing.xs }) {
        ForEach(['A1', 'A2', 'B1', 'B2', 'C1', 'C2'] as CefrLevel[], (lvl: CefrLevel) => {
          Text(lvl)
            .fontSize(AppFontSize.sm)
            .fontColor(value === lvl ? AppColors.textInverse : AppColors.textPrimary)
            .backgroundColor(value === lvl ? AppColors.brand : AppColors.bgSecondary)
            .padding({ left: AppSpacing.sm, right: AppSpacing.sm, top: AppSpacing.xs, bottom: AppSpacing.xs })
            .borderRadius(AppRadius.sm)
            .onClick(() => onChange(lvl))
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  formField(label: string, value: string, onChange: (v: string) => void, kind: string = 'text') {
    Column({ space: AppSpacing.xs }) {
      Text(label)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textSecondary)
      TextInput({ text: value })
        .type(kind === 'number' ? InputType.Number : InputType.Normal)
        .fontSize(AppFontSize.md)
        .height(40)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.sm)
        .onChange((v: string) => onChange(v))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 计划视图 ----

  @Builder
  planView() {
    Column({ space: AppSpacing.base }) {
      this.progressCard()
      this.viewSwitcher()
      if (this.viewMode === 'day') {
        this.todayCard()
      } else {
        this.weekCard()
      }
      this.recommendedBooksCard()
      this.milestonesCard()
    }
    .width('100%')
  }

  @Builder
  progressCard() {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Column({ space: AppSpacing.sm }) {
        Row() {
          Text(`第 ${this.currentDay()} / ${this.plan!.totalDays} 天`)
            .fontSize(AppFontSize.md)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textPrimary)
            .layoutWeight(1)
          Text(`${this.plan!.completedDays} 天已完成`)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
        }
        .width('100%')
        Progress({
          value: this.plan!.completedDays,
          total: this.plan!.totalDays,
          type: ProgressType.Linear,
        })
          .width('100%')
          .color(AppColors.brand)
          .backgroundColor(AppColors.bgSecondary)
        Text(`${this.plan!.input.currentLevel} → ${this.plan!.input.targetLevel} · 每日 ${this.plan!.input.dailyMinutes} 分钟`)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  viewSwitcher() {
    Row({ space: AppSpacing.xs }) {
      Text('当日')
        .fontSize(AppFontSize.sm)
        .fontColor(this.viewMode === 'day' ? AppColors.textInverse : AppColors.textPrimary)
        .backgroundColor(this.viewMode === 'day' ? AppColors.brand : AppColors.bgSecondary)
        .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.xs, bottom: AppSpacing.xs })
        .borderRadius(AppRadius.sm)
        .onClick(() => { this.viewMode = 'day'; })
      Text('本周')
        .fontSize(AppFontSize.sm)
        .fontColor(this.viewMode === 'week' ? AppColors.textInverse : AppColors.textPrimary)
        .backgroundColor(this.viewMode === 'week' ? AppColors.brand : AppColors.bgSecondary)
        .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.xs, bottom: AppSpacing.xs })
        .borderRadius(AppRadius.sm)
        .onClick(() => { this.viewMode = 'week'; })
    }
    .width('100%')
  }

  @Builder
  todayCard() {
    AppCard({ variant: 'outlined', padding: 'md' }) {
      Column({ space: AppSpacing.sm }) {
        Text(`今日任务（第 ${this.currentDay()} 天）`)
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
        if (this.todayTasks().length === 0) {
          Text('今日暂无任务')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textTertiary)
        } else {
          ForEach(this.todayTasks(), (t: StudyTask) => {
            this.taskRow(t)
          }, (t: StudyTask) => t.id)
        }
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  taskRow(t: StudyTask) {
    Row({ space: AppSpacing.sm }) {
      Toggle({ type: ToggleType.Checkbox, isOn: t.completed })
        .selectedColor(AppColors.brand)
        .onChange((on: boolean) => this.toggleTask(t.id, on))
      Column({ space: 2 }) {
        Text(t.title)
          .fontSize(AppFontSize.sm)
          .fontColor(t.completed ? AppColors.textTertiary : AppColors.textPrimary)
          .decoration({ type: t.completed ? TextDecorationType.LineThrough : TextDecorationType.None })
        Text(`${t.kind} · ${t.minutes} 分钟`)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: AppSpacing.xs, bottom: AppSpacing.xs })
  }

  @Builder
  weekCard() {
    AppCard({ variant: 'outlined', padding: 'md' }) {
      Column({ space: AppSpacing.sm }) {
        Text('本周概览')
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
        ForEach(this.currentWeek(), (d: DailyPlan) => {
          Row() {
            Text(`第 ${d.day} 天`)
              .fontSize(AppFontSize.sm)
              .fontColor(AppColors.textPrimary)
              .width(60)
            Text(`${d.tasks.filter((t) => t.completed).length}/${d.tasks.length} 完成`)
              .fontSize(AppFontSize.xs)
              .fontColor(AppColors.textSecondary)
              .layoutWeight(1)
            Text(`${d.tasks.reduce((s, t) => s + t.minutes, 0)} 分钟`)
              .fontSize(AppFontSize.xs)
              .fontColor(AppColors.textTertiary)
          }
          .width('100%')
          .padding({ top: AppSpacing.xs, bottom: AppSpacing.xs })
        }, (d: DailyPlan) => `${d.day}`)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  recommendedBooksCard() {
    if (this.plan!.recommendedBooks.length === 0) return
    AppCard({ variant: 'filled', padding: 'md' }) {
      Column({ space: AppSpacing.xs }) {
        Text('推荐书籍')
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
        ForEach(this.plan!.recommendedBooks, (slug: string) => {
          Text(`· ${slug}`)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.brand)
        }, (s: string) => s)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  milestonesCard() {
    if (this.plan!.milestones.length === 0) return
    AppCard({ variant: 'filled', padding: 'md' }) {
      Column({ space: AppSpacing.xs }) {
        Text('每周里程碑')
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
        ForEach(this.plan!.milestones, (m: { week: number; goal: string }) => {
          Text(`第 ${m.week} 周：${m.goal}`)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
        }, (m: { week: number; goal: string }) => `${m.week}`)
        Text(`复习节奏：${this.plan!.reviewCadence}`)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
          .margin({ top: AppSpacing.xs })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }
}
