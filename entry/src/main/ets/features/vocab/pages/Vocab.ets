/**
 * Vocab.ets — W9-C1 生词本主页
 *
 * 三段式：
 *   1) 顶部 Tab：「全部 / 待复习 / 已掌握」
 *   2) 搜索 + 排序栏（最近添加 / 最近复习 / 难度）
 *   3) 统计卡片 + 列表（LazyForEach）+ CTA「开始复习」
 *
 * 数据：
 *   - listVocab() / searchVocab() / getReviewStats() 走 NotesApi（云端权威）
 *   - 删除 / 标记掌握 通过 NotesApi.deleteVocab / NotesApi.updateVocab
 *   - 不使用本地 NoteService 缓存（W8 NoteService 缓存的是 ExplainData 结构，与
 *     SRS 后端 entity 不对齐；后续若需要 local-first 再补桥接层）
 *
 * 路由：
 *   - 列表项点击 → 弹 VocabDetailSheet
 *   - 「开始复习」CTA → push FLASHCARD_SESSION 路由
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
} from '../../../core/theme/AppColors';
import {
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius, Elevation } from '../../../core/theme/AppSpacing';
import { AppEmptyState } from '../../../ui/primitives/EmptyState';
import { ToastManager } from '../../../ui/primitives/Toast';
import { VocabDetailSheet, VocabDetailActions } from '../../../features/vocab/components/VocabDetailSheet';
import { RoutePath } from '../../../core/router/RouteConstants';
import {
  NotesApi,
  VocabNoteRecord,
  ReviewStats,
} from '../../../api/notes/NotesApi';
import { TtsService } from '../../../features/audiobook/service/TtsService';
// W13-C2：跨端剪贴板（复制到其它设备）
import { DistributedClipboard, VocabPayload } from '../../../features/multi-device/service/distributed/DistributedClipboard';
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
// W18-C1：Vocab 页面曝光埋点
import { Analytics } from '../../../core/analytics/AnalyticsProvider';
import { SaEvents } from '../../../core/analytics/SensorsAnalytics';

type FilterTab = 'all' | 'due' | 'known';
type SortKind = 'createdAt' | 'lastReviewedAt' | 'difficulty';

interface TabSpec {
  key: FilterTab;
  label: string;
}

const TABS: TabSpec[] = [
  { key: 'all',   label: '全部'    },
  { key: 'due',   label: '待复习'  },
  { key: 'known', label: '已掌握'  },
];

@Entry
@Component
struct Vocab {
  @Provide('theme') theme: EffectiveTheme = 'day';

  @State private activeTab: FilterTab = 'all';
  @State private sort: SortKind = 'createdAt';
  @State private searchText: string = '';
  @State private items: VocabNoteRecord[] = [];
  @State private stats: ReviewStats | null = null;
  @State private loading: boolean = false;
  @State private refreshing: boolean = false;
  @State private isError: boolean = false;
  /** 当前打开的详情 sheet */
  @State private detailVocab: VocabNoteRecord | null = null;

  private detailController: CustomDialogController | null = null;

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  aboutToAppear(): void {
    this.refresh();
    Analytics.track(SaEvents.PAGE_VIEW, { page: 'vocab' });
  }

  // ─── 数据加载 ───────────────────────────────────────────────

  private async refresh(): Promise<void> {
    this.refreshing = true;
    this.isError = false;
    try {
      await Promise.all([this.loadItems(), this.loadStats()]);
    } catch (_e) {
      this.isError = true;
    } finally {
      this.refreshing = false;
    }
  }

  private async loadItems(): Promise<void> {
    this.loading = true;
    try {
      const q = this.searchText.trim();
      let raw: VocabNoteRecord[];
      if (q.length > 0) {
        raw = await NotesApi.searchVocab({ q, limit: 100 });
      } else {
        const resp = await NotesApi.listVocab({
          limit: 200,
          dueOnly: this.activeTab === 'due' ? true : undefined,
        });
        raw = resp.items;
      }
      // 客户端二次过滤 + 排序（活动 tab + sort）
      this.items = this.applyClientFilter(raw);
    } catch (_e) {
      this.isError = true;
      this.items = [];
    } finally {
      this.loading = false;
    }
  }

  private async loadStats(): Promise<void> {
    try {
      this.stats = await NotesApi.getReviewStats('today');
    } catch (_e) {
      this.stats = null;
    }
  }

  /** 客户端补充：活动 tab 过滤 + 排序。 */
  private applyClientFilter(list: VocabNoteRecord[]): VocabNoteRecord[] {
    const now = Date.now();
    let filtered = list;
    if (this.activeTab === 'known') {
      // 「已掌握」启发式：reviewCount >= 5 且 interval >= 21 天
      filtered = list.filter((v) => v.reviewCount >= 5 && v.interval >= 21);
    } else if (this.activeTab === 'due') {
      filtered = list.filter((v) => {
        if (!v.nextReviewAt) return true;
        const t = new Date(v.nextReviewAt).getTime();
        return !Number.isNaN(t) && t <= now;
      });
    }
    return this.sortItems(filtered);
  }

  private sortItems(list: VocabNoteRecord[]): VocabNoteRecord[] {
    const arr = list.slice();
    if (this.sort === 'createdAt') {
      arr.sort((a, b) => {
        const ta = new Date(a.createdAt).getTime();
        const tb = new Date(b.createdAt).getTime();
        return tb - ta;
      });
    } else if (this.sort === 'lastReviewedAt') {
      arr.sort((a, b) => {
        const ta = a.lastReviewedAt ? new Date(a.lastReviewedAt).getTime() : 0;
        const tb = b.lastReviewedAt ? new Date(b.lastReviewedAt).getTime() : 0;
        return tb - ta;
      });
    } else {
      arr.sort((a, b) => (b.difficulty ?? 0) - (a.difficulty ?? 0));
    }
    return arr;
  }

  // ─── 操作 ────────────────────────────────────────────────────

  private async deleteVocab(v: VocabNoteRecord): Promise<void> {
    try {
      await NotesApi.deleteVocab(v.id);
      this.items = this.items.filter((x) => x.id !== v.id);
      ToastManager.show({ message: '已删除', type: 'success' });
    } catch (_e) {
      ToastManager.show({ message: '删除失败', type: 'error' });
    }
  }

  private async markKnown(v: VocabNoteRecord): Promise<void> {
    try {
      // 后端没有 known 字段；用「+10000 天 nextReviewAt」让其几乎永不出现在待复习
      await NotesApi.updateVocab(v.id, { userTag: 'known' });
      this.items = this.items.filter((x) => x.id !== v.id);
      ToastManager.show({ message: '已标记掌握', type: 'success' });
    } catch (_e) {
      ToastManager.show({ message: '操作失败', type: 'error' });
    }
  }

  private confirmDelete(v: VocabNoteRecord): void {
    AlertDialog.show({
      title: '删除该生词？',
      message: '此操作不可恢复',
      primaryButton: {
        value: '取消',
        action: () => {},
      },
      secondaryButton: {
        value: '删除',
        fontColor: useColor(StateColors.error, this.isDark),
        action: () => { this.deleteVocab(v); },
      },
    });
  }

  private showLongPressMenu(v: VocabNoteRecord): void {
    promptAction.showActionMenu({
      title: v.word,
      buttons: [
        { text: '编辑详情',         color: useColor(TextColors.primary, this.isDark) as string },
        { text: '标记掌握',         color: useColor(AccentColors.primary, this.isDark) as string },
        // W13-C2：跨端剪贴板，目标设备弹起 PasteFromOtherDeviceSheet
        { text: '复制到其它设备',   color: useColor(AccentColors.primary, this.isDark) as string },
        { text: '删除',             color: useColor(StateColors.error, this.isDark) as string },
      ],
    }).then((result) => {
      if (result.index === 0) {
        this.openDetail(v);
      } else if (result.index === 1) {
        this.markKnown(v);
      } else if (result.index === 2) {
        this.copyVocabToOtherDevice(v);
      } else if (result.index === 3) {
        this.confirmDelete(v);
      }
    }).catch(() => {});
  }

  /** W13-C2：把生词写入分布式剪贴板，其它登录同账号设备会自动收到。 */
  private async copyVocabToOtherDevice(v: VocabNoteRecord): Promise<void> {
    const payload: VocabPayload = {
      word: v.word ?? '',
      phonetic: v.pronunciation,
      definition: v.definition,
      context: v.sourceContext,
      bookId: undefined,
      bookTitle: undefined,
      timestamp: Date.now(),
    };
    try {
      await DistributedClipboard.copyVocab(payload);
      ToastManager.show({ message: '已复制，到其它设备粘贴或自动接收', type: 'success' });
    } catch (_e) {
      ToastManager.show({ message: '复制失败', type: 'error' });
    }
  }

  private openDetail(v: VocabNoteRecord): void {
    this.detailVocab = v;
    const actions: VocabDetailActions = {
      onMarkKnown: (vc) => this.markKnown(vc),
      onDelete: (vc) => this.confirmDelete(vc),
      onShare: (vc) => {
        ToastManager.show({ message: `分享 "${vc.word}"（待 W11 接入）`, type: 'info' });
      },
      onReExplain: () => {
        ToastManager.show({ message: 'AI 重新解释（待 W11 接入）', type: 'info' });
      },
      onSave: async (vc, _note, tags) => {
        try {
          // 后端 schema：仅 userTag 是单值，aiTags 是数组
          await NotesApi.updateVocab(vc.id, {
            userTag: tags[0],
            aiTags: tags.length > 1 ? tags.slice(1) : undefined,
          });
        } catch (_e) {
          // 静默失败，避免打断 UI
        }
      },
      onClose: () => {
        this.detailVocab = null;
      },
      onTtsRead: (text) => {
        TtsService.getInstance().speak(text).catch(() => {
          ToastManager.show({ message: '朗读失败', type: 'error' });
        });
      },
    };
    this.detailController = new CustomDialogController({
      builder: VocabDetailSheet({
        vocab: v,
        theme: this.theme,
        actions,
      }),
      alignment: DialogAlignment.Bottom,
      customStyle: true,
      autoCancel: true,
    });
    this.detailController.open();
  }

  private startFlashcards(): void {
    if (!this.stats || this.stats.dueToday === 0) {
      ToastManager.show({ message: '今天暂无待复习生词，明天再来吧', type: 'info' });
      return;
    }
    router.pushUrl({ url: RoutePath.FLASHCARD_SESSION_URL }).catch(() => {
      ToastManager.show({ message: '页面跳转失败', type: 'error' });
    });
  }

  // ─── builders ───────────────────────────────────────────────

  @Builder
  topBar() {
    Row() {
      Text('\u{2039}')
        .fontSize(FontSizeToken.title2)
        .fontColor(useColor(AccentColors.primary, this.isDark))
        .padding(Spacing.s2)
        .onClick(() => router.back())
      Text('我的生词本')
        .fontSize(FontSizeToken.headline)
        .fontWeight(FontWeightToken.semibold)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
      Blank()
    }
    .width('100%')
    .padding({ left: Spacing.s2, right: Spacing.s4 })
  }

  @Builder
  statsCard() {
    Row({ space: Spacing.s4 }) {
      this.statsCell(`${this.items.length}`, '总词数')
      Divider().vertical(true).color(useColor(BorderColors.secondary, this.isDark)).height(40)
      this.statsCell(`${this.stats?.dueToday ?? 0}`, '今日待复习')
      Divider().vertical(true).color(useColor(BorderColors.secondary, this.isDark)).height(40)
      this.statsCell(`${this.stats?.accuracy ?? 0}%`, '7日正确率')
    }
    .width('92%')
    .padding(Spacing.s4)
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
    .borderRadius(Radius.lg)
    .shadow(Elevation.e1)
    .justifyContent(FlexAlign.SpaceAround)
  }

  @Builder
  statsCell(value: string, label: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(FontSizeToken.title2)
        .fontWeight(FontWeightToken.bold)
        .fontColor(useColor(AccentColors.primary, this.isDark))
      Text(label)
        .fontSize(FontSizeToken.caption1)
        .fontColor(useColor(TextColors.secondary, this.isDark))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  searchBar() {
    Row({ space: Spacing.s2 }) {
      Text('\u{1F50D}')
        .fontSize(FontSizeToken.subheadline)
      TextInput({ placeholder: '搜索单词 / 释义', text: this.searchText })
        .placeholderColor(useColor(TextColors.tertiary, this.isDark))
        .fontSize(FontSizeToken.subheadline)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .backgroundColor('transparent')
        .layoutWeight(1)
        .height(36)
        .onChange((v: string) => {
          this.searchText = v;
        })
        .onSubmit(() => this.loadItems())
      if (this.searchText.length > 0) {
        Text('\u{2715}')
          .fontSize(FontSizeToken.footnote)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
          .padding(Spacing.s1)
          .onClick(() => {
            this.searchText = '';
            this.loadItems();
          })
      }
    }
    .width('92%')
    .padding({ left: Spacing.s3, right: Spacing.s3 })
    .backgroundColor(useColor(BgColors.secondary, this.isDark))
    .borderRadius(Radius.full)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  tabRow() {
    Row({ space: Spacing.s2 }) {
      ForEach(TABS, (t: TabSpec) => {
        Text(t.label)
          .fontSize(FontSizeToken.subheadline)
          .fontWeight(this.activeTab === t.key ? FontWeightToken.semibold : FontWeightToken.regular)
          .fontColor(this.activeTab === t.key
            ? useColor(TextColors.inverse, this.isDark)
            : useColor(TextColors.secondary, this.isDark))
          .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s1, bottom: Spacing.s1 })
          .borderRadius(Radius.full)
          .backgroundColor(this.activeTab === t.key
            ? useColor(AccentColors.primary, this.isDark)
            : useColor(BgColors.secondary, this.isDark))
          .onClick(() => {
            this.activeTab = t.key;
            this.loadItems();
          })
      }, (t: TabSpec) => t.key)
    }
    .width('100%')
    .padding({ left: Spacing.s4, right: Spacing.s4 })
  }

  @Builder
  sortRow() {
    Row({ space: Spacing.s3 }) {
      this.sortChip('createdAt', '最近添加')
      this.sortChip('lastReviewedAt', '最近复习')
      this.sortChip('difficulty', '难度')
      Blank()
      Text(`共 ${this.items.length} 条`)
        .fontSize(FontSizeToken.caption1)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
    }
    .width('100%')
    .padding({ left: Spacing.s4, right: Spacing.s4 })
  }

  @Builder
  sortChip(kind: SortKind, label: string) {
    Text(label)
      .fontSize(FontSizeToken.caption1)
      .fontColor(this.sort === kind
        ? useColor(AccentColors.primary, this.isDark)
        : useColor(TextColors.tertiary, this.isDark))
      .padding({ left: Spacing.s2, right: Spacing.s2, top: 2, bottom: 2 })
      .borderRadius(Radius.sm)
      .backgroundColor(this.sort === kind ? BrandPalette.b50 : 'transparent')
      .onClick(() => {
        this.sort = kind;
        this.items = this.sortItems(this.items);
      })
  }

  @Builder
  vocabRow(v: VocabNoteRecord) {
    Column({ space: Spacing.s1 }) {
      Row({ space: Spacing.s2 }) {
        Text(v.word)
          .fontSize(FontSizeToken.body)
          .fontWeight(FontWeightToken.semibold)
          .fontColor(useColor(TextColors.primary, this.isDark))
        if (v.pronunciation) {
          Text(`/${v.pronunciation}/`)
            .fontSize(FontSizeToken.caption1)
            .fontColor(useColor(TextColors.tertiary, this.isDark))
        }
        if (v.partOfSpeech) {
          Text(v.partOfSpeech)
            .fontSize(FontSizeToken.caption2)
            .fontColor(useColor(AccentColors.primary, this.isDark))
            .padding({ left: Spacing.s1, right: Spacing.s1 })
            .borderRadius(Radius.sm)
            .backgroundColor(BrandPalette.b50)
        }
        Blank()
        if (v.difficulty !== null && v.difficulty !== undefined) {
          Text(`L${v.difficulty}`)
            .fontSize(FontSizeToken.caption2)
            .fontColor(useColor(TextColors.inverse, this.isDark))
            .padding({ left: Spacing.s1, right: Spacing.s1 })
            .borderRadius(Radius.sm)
            .backgroundColor(useColor(AccentColors.primary, this.isDark))
        }
      }
      .width('100%')

      if (v.definition) {
        Text(v.definition)
          .fontSize(FontSizeToken.subheadline)
          .fontColor(useColor(TextColors.secondary, this.isDark))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(LineHeightToken.subheadline)
          .width('100%')
      }

      Row({ space: Spacing.s3 }) {
        Text(`复习 ${v.reviewCount}次`)
          .fontSize(FontSizeToken.caption2)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
        Text(`下次：${this.formatNextReview(v.nextReviewAt)}`)
          .fontSize(FontSizeToken.caption2)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(Spacing.s4)
    .width('100%')
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
    .borderRadius(Radius.md)
    .onClick(() => this.openDetail(v))
    .gesture(
      LongPressGesture({ repeat: false }).onAction(() => this.showLongPressMenu(v)),
    )
  }

  @Builder
  emptyView() {
    AppEmptyState({
      variant: this.searchText.length > 0 ? 'no-results' : 'no-data',
      title: this.searchText.length > 0 ? '没有匹配的单词' : '生词本是空的',
      description: this.searchText.length > 0
        ? '换个关键词试试'
        : '在阅读中长按生词点「保存到生词本」，生词会出现在这里',
    })
  }

  @Builder
  errorView() {
    AppEmptyState({
      variant: 'error',
      title: '加载失败',
      description: '请下拉刷新重试',
      actionLabel: '重试',
      onAction: () => this.refresh(),
    })
  }

  @Builder
  reviewCta() {
    Row({ space: Spacing.s2 }) {
      Text('\u{1F525}')
        .fontSize(FontSizeToken.title3)
      Text(`开始复习${this.stats && this.stats.dueToday > 0 ? `（${this.stats.dueToday}）` : ''}`)
        .fontSize(FontSizeToken.body)
        .fontWeight(FontWeightToken.semibold)
        .fontColor(useColor(TextColors.inverse, this.isDark))
    }
    .width('92%')
    .height(52)
    .justifyContent(FlexAlign.Center)
    .borderRadius(Radius.full)
    .backgroundColor(useColor(AccentColors.primary, this.isDark))
    .shadow(Elevation.e2)
    .onClick(() => this.startFlashcards())
  }

  // ─── helpers ────────────────────────────────────────────────

  private formatNextReview(iso: string | null): string {
    if (!iso) return '尚未安排';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '—';
    const now = new Date();
    const diffMs = d.getTime() - now.getTime();
    const dayMs = 24 * 60 * 60 * 1000;
    if (diffMs <= 0) return '今天';
    const days = Math.ceil(diffMs / dayMs);
    if (days === 1) return '明天';
    if (days < 30) return `${days} 天后`;
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  // ─── build ──────────────────────────────────────────────────

  build() {
    Stack() {
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column({ space: Spacing.s3 }) {
            this.topBar()
            this.statsCard()
            this.searchBar()
            this.tabRow()
            this.sortRow()

            if (this.loading && this.items.length === 0) {
              Column() {
                LoadingProgress()
                  .width(40)
                  .height(40)
                  .color(useColor(AccentColors.primary, this.isDark))
              }
              .width('100%')
              .padding({ top: Spacing.s16 })
              .alignItems(HorizontalAlign.Center)
            } else if (this.isError && this.items.length === 0) {
              this.errorView()
            } else if (this.items.length === 0) {
              this.emptyView()
            } else {
              Column({ space: Spacing.s2 }) {
                ForEach(
                  this.items,
                  (v: VocabNoteRecord) => {
                    this.vocabRow(v)
                  },
                  (v: VocabNoteRecord) => v.id,
                )
              }
              .width('92%')
              .padding({ bottom: 96 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
      }
      .onRefreshing(() => this.refresh())
      .width('100%')
      .height('100%')

      // 浮动 CTA
      Column() {
        Blank()
        this.reviewCta()
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: Spacing.s4 })
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(useColor(BgColors.primary, this.isDark))
  }
}
