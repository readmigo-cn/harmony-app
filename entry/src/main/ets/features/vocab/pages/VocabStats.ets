/**
 * VocabStats — W9-C5 词汇量统计 dashboard
 *
 * 顶部：总词汇量 + CEFR 等级估算
 * 卡片网格：今日新增 / 本周复习 / 已掌握 / 待复习 / streak / 累计阅读时长
 * 图表：CEFR 柱状分布、词性饼图、7 天新增 sparkline
 * 时间维度：今日 / 本周 / 本月 / 全部（AppTabs segmented）
 *
 * 数据：StatsApi.getVocabStats + StatsApi.getReadingStats
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
  Typography,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius, Elevation } from '../../../core/theme/AppSpacing';
import { EffectiveTheme } from '../../../core/theme/Theme.types';
import { RouterService } from '../../../core/router/RouterService';
import { RoutePath } from '../../../core/router/RouteConstants';
import { AppCard } from '../../../ui/primitives/Card';
import { AppButton } from '../../../ui/primitives/Button';
import { AppEmptyState } from '../../../ui/primitives/EmptyState';
import { AppTabs } from '../../../ui/primitives/Tab';
import {
  StatsApi,
  VocabStats as VocabStatsDto,
  ReadingStats,
  StatsPeriod,
  CefrBucket,
  PosBucket,
  SparkPoint,
} from '../../../api/reading/StatsApi';

// ─────────────────────────────────────────────
// 常量
// ─────────────────────────────────────────────

const PERIOD_LABELS: string[] = ['今日', '本周', '本月', '全部'];
const PERIOD_VALUES: StatsPeriod[] = ['today', 'week', 'month', 'all'];

const CEFR_ORDER: string[] = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

/** 词性中文标签 */
const POS_LABELS: Record<string, string> = {
  noun: '名词',
  verb: '动词',
  adj: '形容词',
  adv: '副词',
  prep: '介词',
  conj: '连词',
  pron: '代词',
  interj: '感叹词',
  other: '其他',
};

/** 饼图调色板（与 brand 协调） */
const PIE_COLORS: string[] = [
  BrandPalette.b400,
  BrandPalette.b600,
  ColorPalette.blue400,
  ColorPalette.green400,
  ColorPalette.orange400,
  ColorPalette.yellow400,
  ColorPalette.red400,
  ColorPalette.pink400,
  GrayPalette.g400,
];

// ─────────────────────────────────────────────
// VocabStats 页面
// ─────────────────────────────────────────────

@Entry
@Component
struct VocabStats {
  @State private periodIndex: number = 3; // 默认全部
  @State private vocab: VocabStatsDto | null = null;
  @State private reading: ReadingStats | null = null;
  @State private loading: boolean = false;
  @State private errorMessage: string = '';

  @Provide('theme') theme: EffectiveTheme = 'day';

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    const period = PERIOD_VALUES[this.periodIndex] ?? 'all';
    try {
      const [vocab, reading] = await Promise.all([
        StatsApi.getVocabStats(period),
        StatsApi.getReadingStats(period),
      ]);
      this.vocab = vocab;
      this.reading = reading;
    } catch (e) {
      this.errorMessage = (e as Error).message ?? '加载失败';
      this.vocab = null;
      this.reading = null;
    } finally {
      this.loading = false;
    }
  }

  private formatPercent(v: number): string {
    return `${Math.round(v * 100)}%`;
  }

  private formatMinutes(min: number): string {
    if (min < 60) return `${min} 分钟`;
    const h = Math.floor(min / 60);
    const m = min % 60;
    return m === 0 ? `${h} 小时` : `${h}h ${m}m`;
  }

  // ─────────────────────────────────────────────
  // 顶部 Hero：总词汇量 + CEFR 等级
  // ─────────────────────────────────────────────

  @Builder
  heroBuilder() {
    AppCard({ variant: 'elevated', padding: 'lg' }) {
      Column({ space: Spacing.s2 }) {
        Text('总词汇量')
          .fontSize(LabelStyles.medium.fontSize)
          .fontColor(useColor(TextColors.secondary, this.isDark))

        Text(`${this.vocab?.totalWords ?? 0}`)
          .fontFamily(HeadlineStyles.large.fontFamily)
          .fontSize(48)
          .fontWeight(FontWeight.Bold)
          .fontColor(useColor(AccentColors.primary, this.isDark))

        Row({ space: Spacing.s2 }) {
          Text('CEFR')
            .fontSize(CaptionStyle.fontSize)
            .fontColor(useColor(TextColors.tertiary, this.isDark))
          Text(this.vocab?.estimatedLevel ?? '—')
            .fontSize(LabelStyles.large.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .padding({ left: Spacing.s2, right: Spacing.s2, top: 2, bottom: 2 })
            .backgroundColor(useColor(AccentColors.primary, this.isDark))
            .borderRadius(Radius.sm)
        }
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  // ─────────────────────────────────────────────
  // 指标卡片（小）
  // ─────────────────────────────────────────────

  @Builder
  metricCard(title: string, value: string, subtitle: string, accent: ResourceColor) {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Column({ space: Spacing.s1 }) {
        Text(title)
          .fontSize(CaptionStyle.fontSize)
          .fontColor(useColor(TextColors.secondary, this.isDark))
          .maxLines(1)
        Text(value)
          .fontFamily(TitleStyles.large.fontFamily)
          .fontSize(TitleStyles.large.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(accent)
        Text(subtitle)
          .fontSize(CaptionStyle.fontSize)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  // ─────────────────────────────────────────────
  // Sparkline（7 天新增）
  // 用 Polyline 在固定 viewBox 内归一化绘制
  // ─────────────────────────────────────────────

  @Builder
  sparkline(points: SparkPoint[]) {
    Stack({ alignContent: Alignment.BottomStart }) {
      // viewBox: 100 x 30
      Polyline()
        .width('100%')
        .height(30)
        .points(this.normalizeSparkPoints(points))
        .strokeWidth(2)
        .stroke(useColor(AccentColors.primary, this.isDark))
        .fill('transparent')
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
    }
    .width('100%')
    .height(30)
  }

  private normalizeSparkPoints(points: SparkPoint[]): Array<Array<number>> {
    if (!points || points.length === 0) return [[0, 30], [100, 30]];
    const max = Math.max(...points.map((p) => p.count), 1);
    const step = points.length === 1 ? 0 : 100 / (points.length - 1);
    return points.map((p, i) => {
      const x = i * step;
      const y = 30 - (p.count / max) * 28; // 留 2px 边
      return [x, y];
    });
  }

  // ─────────────────────────────────────────────
  // CEFR 柱状图（6 根固定柱）
  // ─────────────────────────────────────────────

  @Builder
  cefrChart() {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Column({ space: Spacing.s3 }) {
        Text('CEFR 等级分布')
          .fontSize(TitleStyles.small.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(useColor(TextColors.primary, this.isDark))

        Row({ space: Spacing.s2 }) {
          ForEach(CEFR_ORDER, (level: string) => {
            this.cefrBar(level)
          }, (level: string) => level)
        }
        .width('100%')
        .height(140)
        .alignItems(VerticalAlign.Bottom)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  private cefrCount(level: string): number {
    const buckets = this.vocab?.cefrDistribution ?? [];
    const found = buckets.find((b) => b.level === level);
    return found ? found.count : 0;
  }

  private cefrMax(): number {
    const buckets = this.vocab?.cefrDistribution ?? [];
    return Math.max(1, ...buckets.map((b) => b.count));
  }

  @Builder
  cefrBar(level: string) {
    Column({ space: Spacing.s1 }) {
      // count label
      Text(`${this.cefrCount(level)}`)
        .fontSize(CaptionStyle.fontSize)
        .fontColor(useColor(TextColors.secondary, this.isDark))

      // bar
      Column()
        .width('100%')
        .height(`${(this.cefrCount(level) / this.cefrMax()) * 100}%`)
        .backgroundColor(useColor(AccentColors.primary, this.isDark))
        .borderRadius({ topLeft: Radius.sm, topRight: Radius.sm, bottomLeft: 0, bottomRight: 0 })
        .constraintSize({ minHeight: 2 })

      Text(level)
        .fontSize(CaptionStyle.fontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(useColor(TextColors.secondary, this.isDark))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.End)
    .height('100%')
  }

  // ─────────────────────────────────────────────
  // 词性饼图（用 SVG Path 绘制扇形）
  // ─────────────────────────────────────────────

  @Builder
  posChart() {
    AppCard({ variant: 'elevated', padding: 'md' }) {
      Column({ space: Spacing.s3 }) {
        Text('词性分布')
          .fontSize(TitleStyles.small.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(useColor(TextColors.primary, this.isDark))

        Row({ space: Spacing.s4 }) {
          // 饼图
          Stack() {
            ForEach(this.computePieSlices(), (slice: PieSlice, idx?: number) => {
              Path()
                .commands(slice.pathCmd)
                .fill(slice.color)
                .stroke(useColor(BgColors.primary, this.isDark))
                .strokeWidth(1)
            }, (slice: PieSlice, idx?: number) => `${idx ?? 0}-${slice.color}`)
          }
          .width(120)
          .height(120)

          // 图例
          Column({ space: Spacing.s2 }) {
            ForEach(this.posDistribution(), (b: PosBucket, idx?: number) => {
              Row({ space: Spacing.s2 }) {
                Column()
                  .width(10)
                  .height(10)
                  .borderRadius(Radius.sm)
                  .backgroundColor(PIE_COLORS[(idx ?? 0) % PIE_COLORS.length])
                Text(`${POS_LABELS[b.pos] ?? b.pos} ${b.count}`)
                  .fontSize(CaptionStyle.fontSize)
                  .fontColor(useColor(TextColors.secondary, this.isDark))
              }
              .alignItems(VerticalAlign.Center)
            }, (b: PosBucket, idx?: number) => `${idx ?? 0}-${b.pos}`)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  private posDistribution(): PosBucket[] {
    return this.vocab?.posDistribution ?? [];
  }

  /**
   * 把词性分布换算成扇形 SVG path 命令。
   * 圆心 (60,60), 半径 56；按比例分配 0~360°。
   */
  private computePieSlices(): PieSlice[] {
    const buckets = this.posDistribution();
    const total = buckets.reduce((s, b) => s + b.count, 0);
    if (total <= 0) return [];

    const cx = 60;
    const cy = 60;
    const r = 56;
    const slices: PieSlice[] = [];
    let acc = 0;

    for (let i = 0; i < buckets.length; i++) {
      const b = buckets[i];
      const start = (acc / total) * 2 * Math.PI;
      acc += b.count;
      const end = (acc / total) * 2 * Math.PI;
      const sweep = end - start;
      const largeArc = sweep > Math.PI ? 1 : 0;

      const x1 = cx + r * Math.cos(start - Math.PI / 2);
      const y1 = cy + r * Math.sin(start - Math.PI / 2);
      const x2 = cx + r * Math.cos(end - Math.PI / 2);
      const y2 = cy + r * Math.sin(end - Math.PI / 2);

      // 全圆兜底（一个分类占 100%）
      let cmd: string;
      if (sweep >= 2 * Math.PI - 0.001) {
        cmd = `M ${cx - r} ${cy} a ${r} ${r} 0 1 0 ${r * 2} 0 a ${r} ${r} 0 1 0 ${-r * 2} 0 Z`;
      } else {
        cmd =
          `M ${cx} ${cy} ` +
          `L ${x1.toFixed(2)} ${y1.toFixed(2)} ` +
          `A ${r} ${r} 0 ${largeArc} 1 ${x2.toFixed(2)} ${y2.toFixed(2)} Z`;
      }

      slices.push({
        pathCmd: cmd,
        color: PIE_COLORS[i % PIE_COLORS.length],
      });
    }
    return slices;
  }

  // ─────────────────────────────────────────────
  // 顶部导航条
  // ─────────────────────────────────────────────

  @Builder
  topBar() {
    Row() {
      Text('‹')
        .fontSize(28)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s2, bottom: Spacing.s2 })
        .onClick(() => RouterService.back())
      Text('学习数据')
        .fontSize(TitleStyles.medium.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .layoutWeight(1)
      Text('弱点分析')
        .fontSize(LabelStyles.medium.fontSize)
        .fontColor(useColor(AccentColors.primary, this.isDark))
        .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s2, bottom: Spacing.s2 })
        .onClick(() => RouterService.push(RoutePath.WEAKNESS_ANALYSIS))
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(useColor(BgColors.primary, this.isDark))
  }

  // ─────────────────────────────────────────────
  // 主体
  // ─────────────────────────────────────────────

  build() {
    Column() {
      this.topBar()

      // 时间维度切换
      AppTabs({
        labels: PERIOD_LABELS,
        currentIndex: $periodIndex,
        variant: 'segmented',
        isDark: this.isDark,
        onChange: (idx: number) => {
          this.periodIndex = idx;
          this.load();
        },
      })
        .height(56)

      if (this.loading && this.vocab === null) {
        AppEmptyState({
          variant: 'no-data',
          title: '加载中…',
          description: '正在汇总你的学习数据',
        })
      } else if (this.errorMessage.length > 0 && this.vocab === null) {
        AppEmptyState({
          variant: 'error',
          description: this.errorMessage,
          actionLabel: '重试',
          onAction: () => this.load(),
        })
      } else {
        Scroll() {
          Column({ space: Spacing.s4 }) {
            // Hero
            this.heroBuilder()

            // 指标卡片网格（2 列）
            Grid() {
              GridItem() {
                this.metricCard(
                  '今日新增',
                  `${this.vocab?.todayAdded ?? 0}`,
                  '7 天趋势 ↗',
                  useColor(AccentColors.primary, this.isDark),
                )
              }
              GridItem() {
                this.metricCard(
                  '本周复习',
                  `${this.vocab?.weekReviewed ?? 0}`,
                  `准确率 ${this.formatPercent(this.vocab?.weekAccuracy ?? 0)}`,
                  ColorPalette.blue400,
                )
              }
              GridItem() {
                this.metricCard(
                  '已掌握',
                  `${this.vocab?.mastered ?? 0}`,
                  `占比 ${this.formatPercent(this.vocab?.masteredRatio ?? 0)}`,
                  ColorPalette.green400,
                )
              }
              GridItem() {
                this.metricCard(
                  '待复习',
                  `${this.vocab?.dueCount ?? 0}`,
                  `紧急度 ${this.formatPercent(this.vocab?.urgency ?? 0)}`,
                  ColorPalette.orange400,
                )
              }
              GridItem() {
                this.metricCard(
                  '连续天数',
                  `${this.vocab?.streakDays ?? 0} 天`,
                  '保持每日学习',
                  ColorPalette.yellow400,
                )
              }
              GridItem() {
                this.metricCard(
                  '累计阅读',
                  this.formatMinutes(this.reading?.totalMinutes ?? 0),
                  `本期 ${this.formatMinutes(this.reading?.periodMinutes ?? 0)}`,
                  ColorPalette.red400,
                )
              }
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(Spacing.s3)
            .rowsGap(Spacing.s3)
            .width('100%')
            .height(360)

            // Sparkline 单独一行（7 天新增趋势）
            AppCard({ variant: 'elevated', padding: 'md' }) {
              Column({ space: Spacing.s2 }) {
                Text('近 7 天新增词汇')
                  .fontSize(TitleStyles.small.fontSize)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(useColor(TextColors.primary, this.isDark))
                this.sparkline(this.vocab?.recentSpark ?? [])
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            }

            // CEFR 柱状图
            this.cefrChart()

            // 词性饼图
            this.posChart()

            Column().height(Spacing.s8)
          }
          .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s2, bottom: Spacing.s8 })
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

// 内部类型
interface PieSlice {
  pathCmd: string;
  color: string;
}
