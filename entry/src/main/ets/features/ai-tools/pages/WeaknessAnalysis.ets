/**
 * WeaknessAnalysis — W9-C8 弱点分析报告
 *
 * AI 基于 SRS 复习历史 + 阅读数据生成个性化弱点报告。
 * 报告结构：
 *   - summary：一句话总结
 *   - 易错词 Top 10（quality < 3）
 *   - 易错词性
 *   - 易错主题
 *   - 推荐补强方向（每条配「针对性练习」CTA）
 *   - 历史报告列表（最近 5 份）
 *
 * 数据：StatsApi.generateWeaknessReport / getWeaknessHistory
 */

import {
  useColor,
  TextColors,
  BgColors,
  BorderColors,
  AccentColors,
  StateColors,
  BrandPalette,
  GrayPalette,
  ColorPalette,
} from '../../../core/theme/AppColors';
import {
  TitleStyles,
  HeadlineStyles,
  BodyStyles,
  LabelStyles,
  CaptionStyle,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius, Elevation } from '../../../core/theme/AppSpacing';
import { EffectiveTheme } from '../../../core/theme/Theme.types';
import { RouterService } from '../../../core/router/RouterService';
import { RoutePath } from '../../../core/router/RouteConstants';
import { AppCard } from '../../../ui/primitives/Card';
import { AppButton } from '../../../ui/primitives/Button';
import { AppEmptyState } from '../../../ui/primitives/EmptyState';
import {
  StatsApi,
  WeaknessReport,
  WeaknessHistoryItem,
  WeakWord,
  WeakPos,
  WeakTopic,
} from '../../../api/reading/StatsApi';

const POS_LABELS: Record<string, string> = {
  noun: '名词',
  verb: '动词',
  adj: '形容词',
  adv: '副词',
  prep: '介词',
  conj: '连词',
  pron: '代词',
};

@Entry
@Component
struct WeaknessAnalysis {
  @State private report: WeaknessReport | null = null;
  @State private history: WeaknessHistoryItem[] = [];
  @State private loading: boolean = false;
  @State private generating: boolean = false;
  @State private errorMessage: string = '';

  @Provide('theme') theme: EffectiveTheme = 'day';

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  aboutToAppear(): void {
    this.loadHistory();
  }

  private async loadHistory(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      this.history = await StatsApi.getWeaknessHistory(5);
    } catch (e) {
      this.errorMessage = (e as Error).message ?? '加载历史失败';
    } finally {
      this.loading = false;
    }
  }

  private async generate(): Promise<void> {
    if (this.generating) return;
    this.generating = true;
    this.errorMessage = '';
    try {
      this.report = await StatsApi.generateWeaknessReport();
      // 重新拉一遍 history（新增了一条）
      await this.loadHistory();
    } catch (e) {
      this.errorMessage = (e as Error).message ?? '生成失败';
    } finally {
      this.generating = false;
    }
  }

  private formatPercent(v: number): string {
    return `${Math.round(v * 100)}%`;
  }

  private formatDate(iso: string): string {
    if (!iso) return '';
    return iso.length >= 10 ? iso.slice(0, 10) : iso;
  }

  // ─────────────────────────────────────────────
  // 顶部 nav
  // ─────────────────────────────────────────────

  @Builder
  topBar() {
    Row() {
      Text('‹')
        .fontSize(28)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s2, bottom: Spacing.s2 })
        .onClick(() => RouterService.back())
      Text('弱点分析')
        .fontSize(TitleStyles.medium.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .layoutWeight(1)
      // 占位平衡左侧 ‹
      Column().width(48)
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(useColor(BgColors.primary, this.isDark))
  }

  // ─────────────────────────────────────────────
  // 报告：summary 卡片
  // ─────────────────────────────────────────────

  @Builder
  summaryCard() {
    AppCard({ variant: 'elevated', padding: 'lg' }) {
      Column({ space: Spacing.s2 }) {
        Row({ space: Spacing.s2 }) {
          Text('📊')
            .fontSize(20)
          Text('AI 报告摘要')
            .fontSize(TitleStyles.small.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(useColor(TextColors.primary, this.isDark))
        }
        .alignItems(VerticalAlign.Center)

        Text(this.report?.summary ?? '')
          .fontSize(BodyStyles.medium.fontSize)
          .lineHeight(BodyStyles.medium.lineHeight)
          .fontColor(useColor(TextColors.secondary, this.isDark))

        Text(`生成于 ${this.formatDate(this.report?.generatedAt ?? '')}`)
          .fontSize(CaptionStyle.fontSize)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  // ─────────────────────────────────────────────
  // 易错词 Top 10
  // ─────────────────────────────────────────────

  @Builder
  weakWordsCard() {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Column({ space: Spacing.s3 }) {
        Row() {
          Text('易错词 Top 10')
            .fontSize(TitleStyles.small.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(useColor(TextColors.primary, this.isDark))
            .layoutWeight(1)
          Text('针对性练习')
            .fontSize(LabelStyles.small.fontSize)
            .fontColor(useColor(AccentColors.primary, this.isDark))
            .onClick(() => RouterService.push(RoutePath.NOTES))
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')

        Column({ space: Spacing.s2 }) {
          ForEach(this.report?.weakWords ?? [], (w: WeakWord, idx?: number) => {
            this.weakWordRow(w, (idx ?? 0) + 1)
          }, (w: WeakWord) => w.word)
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  @Builder
  weakWordRow(w: WeakWord, rank: number) {
    Row({ space: Spacing.s3 }) {
      Text(`${rank}`)
        .fontSize(LabelStyles.medium.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
        .width(24)
        .textAlign(TextAlign.Center)
      Text(w.word)
        .fontSize(BodyStyles.medium.fontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .layoutWeight(1)
      Text(`错 ${w.failureCount}/${w.reviewCount}`)
        .fontSize(CaptionStyle.fontSize)
        .fontColor(useColor(StateColors.error, this.isDark))
      // quality bar
      Column()
        .width(40)
        .height(4)
        .borderRadius(Radius.full)
        .backgroundColor(useColor(BgColors.secondary, this.isDark))
        .overlay(this.qualityBarOverlay(w.avgQuality), { align: Alignment.Start })
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding({ top: Spacing.s1, bottom: Spacing.s1 })
  }

  @Builder
  qualityBarOverlay(quality: number) {
    Column()
      .width(`${(quality / 5) * 100}%`)
      .height(4)
      .borderRadius(Radius.full)
      .backgroundColor(useColor(AccentColors.primary, this.isDark))
  }

  // ─────────────────────────────────────────────
  // 易错词性
  // ─────────────────────────────────────────────

  @Builder
  weakPosCard() {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Column({ space: Spacing.s3 }) {
        Text('易错词性')
          .fontSize(TitleStyles.small.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(useColor(TextColors.primary, this.isDark))

        Column({ space: Spacing.s2 }) {
          ForEach(this.report?.weakPos ?? [], (p: WeakPos) => {
            Row({ space: Spacing.s3 }) {
              Text(POS_LABELS[p.pos] ?? p.pos)
                .fontSize(BodyStyles.medium.fontSize)
                .fontColor(useColor(TextColors.primary, this.isDark))
                .width(72)
              Column()
                .height(8)
                .layoutWeight(1)
                .borderRadius(Radius.full)
                .backgroundColor(useColor(BgColors.secondary, this.isDark))
                .overlay(this.accuracyBarOverlay(p.accuracy), { align: Alignment.Start })
              Text(this.formatPercent(p.accuracy))
                .fontSize(CaptionStyle.fontSize)
                .fontColor(useColor(TextColors.secondary, this.isDark))
                .width(48)
                .textAlign(TextAlign.End)
            }
            .alignItems(VerticalAlign.Center)
            .width('100%')
          }, (p: WeakPos) => p.pos)
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  @Builder
  accuracyBarOverlay(acc: number) {
    Column()
      .width(`${acc * 100}%`)
      .height(8)
      .borderRadius(Radius.full)
      .backgroundColor(
        acc < 0.5
          ? useColor(StateColors.error, this.isDark)
          : acc < 0.75
            ? useColor(StateColors.warning, this.isDark)
            : useColor(StateColors.success, this.isDark),
      )
  }

  // ─────────────────────────────────────────────
  // 易错主题
  // ─────────────────────────────────────────────

  @Builder
  weakTopicsCard() {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Column({ space: Spacing.s3 }) {
        Text('易错主题')
          .fontSize(TitleStyles.small.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(useColor(TextColors.primary, this.isDark))

        Column({ space: Spacing.s2 }) {
          ForEach(this.report?.weakTopics ?? [], (t: WeakTopic) => {
            Row() {
              Column({ space: 2 }) {
                Text(t.topic)
                  .fontSize(BodyStyles.medium.fontSize)
                  .fontColor(useColor(TextColors.primary, this.isDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${t.wordCount} 个词`)
                  .fontSize(CaptionStyle.fontSize)
                  .fontColor(useColor(TextColors.tertiary, this.isDark))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.formatPercent(t.accuracy))
                .fontSize(LabelStyles.medium.fontSize)
                .fontWeight(FontWeight.Bold)
                .fontColor(
                  t.accuracy < 0.5
                    ? useColor(StateColors.error, this.isDark)
                    : useColor(TextColors.secondary, this.isDark),
                )
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }, (t: WeakTopic) => t.topic)
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  // ─────────────────────────────────────────────
  // 推荐补强方向
  // ─────────────────────────────────────────────

  @Builder
  recommendationsCard() {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Column({ space: Spacing.s3 }) {
        Text('推荐补强方向')
          .fontSize(TitleStyles.small.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(useColor(TextColors.primary, this.isDark))

        ForEach(this.report?.recommendations ?? [], (rec: string, idx?: number) => {
          Column({ space: Spacing.s2 }) {
            Row({ space: Spacing.s2 }) {
              Text(`${(idx ?? 0) + 1}.`)
                .fontSize(BodyStyles.medium.fontSize)
                .fontWeight(FontWeight.Bold)
                .fontColor(useColor(AccentColors.primary, this.isDark))
              Text(rec)
                .fontSize(BodyStyles.medium.fontSize)
                .lineHeight(BodyStyles.medium.lineHeight)
                .fontColor(useColor(TextColors.primary, this.isDark))
                .layoutWeight(1)
            }
            .alignItems(VerticalAlign.Top)
            .width('100%')

            AppButton({
              label: '针对性练习',
              variant: 'tertiary',
              size: 'sm',
              onClick: () => RouterService.push(RoutePath.NOTES),
            })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ top: Spacing.s2, bottom: Spacing.s2 })
        }, (rec: string, idx?: number) => `${idx ?? 0}-${rec}`)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  // ─────────────────────────────────────────────
  // 历史报告列表
  // ─────────────────────────────────────────────

  @Builder
  historyCard() {
    AppCard({ variant: 'outlined', padding: 'md' }) {
      Column({ space: Spacing.s3 }) {
        Text('历史报告')
          .fontSize(TitleStyles.small.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(useColor(TextColors.primary, this.isDark))

        if (this.history.length === 0) {
          Text('暂无历史报告')
            .fontSize(CaptionStyle.fontSize)
            .fontColor(useColor(TextColors.tertiary, this.isDark))
        } else {
          ForEach(this.history, (h: WeaknessHistoryItem) => {
            Row() {
              Column({ space: 2 }) {
                Text(h.summary)
                  .fontSize(BodyStyles.small.fontSize)
                  .fontColor(useColor(TextColors.primary, this.isDark))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.formatDate(h.generatedAt))
                  .fontSize(CaptionStyle.fontSize)
                  .fontColor(useColor(TextColors.tertiary, this.isDark))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('›')
                .fontSize(20)
                .fontColor(useColor(TextColors.tertiary, this.isDark))
            }
            .width('100%')
            .padding({ top: Spacing.s2, bottom: Spacing.s2 })
            .alignItems(VerticalAlign.Center)
          }, (h: WeaknessHistoryItem) => h.id)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  // ─────────────────────────────────────────────
  // 主体
  // ─────────────────────────────────────────────

  build() {
    Column() {
      this.topBar()

      if (this.generating && this.report === null) {
        AppEmptyState({
          variant: 'no-data',
          title: 'AI 正在分析…',
          description: '基于你的复习与阅读数据生成个性化报告',
        })
      } else if (this.errorMessage.length > 0 && this.report === null && this.history.length === 0) {
        AppEmptyState({
          variant: 'error',
          description: this.errorMessage,
          actionLabel: '重试',
          onAction: () => this.loadHistory(),
        })
      } else {
        Scroll() {
          Column({ space: Spacing.s4 }) {
            // 没有当前报告时给生成按钮 + 历史
            if (this.report === null) {
              AppCard({ variant: 'elevated', padding: 'lg' }) {
                Column({ space: Spacing.s3 }) {
                  Text('🎯')
                    .fontSize(48)
                  Text('生成你的弱点分析报告')
                    .fontSize(TitleStyles.medium.fontSize)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(useColor(TextColors.primary, this.isDark))
                    .textAlign(TextAlign.Center)
                  Text('AI 将根据近 30 天的 SRS 复习历史 + 阅读数据，生成易错词 / 词性 / 主题分析与补强建议。')
                    .fontSize(BodyStyles.small.fontSize)
                    .lineHeight(BodyStyles.small.lineHeight)
                    .fontColor(useColor(TextColors.secondary, this.isDark))
                    .textAlign(TextAlign.Center)
                  AppButton({
                    label: this.generating ? '生成中…' : '生成报告',
                    variant: 'primary',
                    size: 'lg',
                    fullWidth: true,
                    loading: this.generating,
                    onClick: () => this.generate(),
                  })
                }
                .alignItems(HorizontalAlign.Center)
                .width('100%')
              }
            } else {
              this.summaryCard()
              this.weakWordsCard()
              this.weakPosCard()
              this.weakTopicsCard()
              this.recommendationsCard()

              AppButton({
                label: '重新生成',
                variant: 'secondary',
                size: 'md',
                fullWidth: true,
                loading: this.generating,
                onClick: () => this.generate(),
              })
            }

            // 历史
            this.historyCard()

            Column().height(Spacing.s8)
          }
          .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s3, bottom: Spacing.s8 })
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(useColor(BgColors.primary, this.isDark))
  }
}
