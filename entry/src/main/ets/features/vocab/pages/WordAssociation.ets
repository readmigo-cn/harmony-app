/**
 * WordAssociation — 单词联想 mind-map 页（W9-C3）
 *
 * 流程：
 *   1. 输入框输入 target word（或从 Vocab 跳转携带 word 参数）
 *   2. 调 WordAnalysisApi.getAssociations(word, mode) 获取 8 个关联词
 *   3. mind-map 风格渲染：中心 target + 周围 8 个关联卡片
 *   4. 点击关联词 → 复用 ExplainCard 弹出该词解释 / 加入生词本
 *   5. 「再生成」按钮切换 mode（semantic ↔ phonetic ↔ thematic）
 *   6. 历史记录：本地 Preferences 持久化最近 10 条
 *
 * TODO(W9-A 集成)：
 *   Vocab.ets 创建后，在 Vocab item 长按菜单中加入「联想」入口，
 *   调 RouterService.push(RoutePath.WORD_ASSOCIATION, { word: ... })。
 */

import promptAction from '@ohos.promptAction';
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import {
  WordAnalysisApi,
  WordAssociation as WordAssoc,
  AssociationMode,
} from '../../../api/ai/WordAnalysisApi';
import { ExplainCard } from '../../../features/ai-tools/components/ExplainCard';
import { ExplainData } from '../../../model/ExplainData';
import { NoteRepository, LocalNote } from '../../../core/persistence/NoteRepository';
import { PreferencesManager } from '../../../core/persistence/PreferencesManager';
import util from '@ohos.util';

interface WordAssociationParams {
  word?: string;
}

const HISTORY_KEY = 'word_association_history_v1';
const HISTORY_MAX = 10;

interface HistoryEntry {
  word: string;
  at: number;
}

@Component
export struct WordAssociation {
  @Prop params: WordAssociationParams = {};

  @State private input: string = '';
  @State private target: string = '';
  @State private mode: AssociationMode = 'semantic';
  @State private loading: boolean = false;
  @State private errMsg: string = '';
  @State private items: WordAssoc[] = [];
  @State private history: HistoryEntry[] = [];

  // 详情弹窗
  @State private showDetail: boolean = false;
  @State private detailWord: string = '';
  @State private detailContext: string = '';

  aboutToAppear(): void {
    this.loadHistory();
    if (this.params && this.params.word) {
      this.input = this.params.word;
      this.run();
    }
  }

  // ---- 历史 ----

  private async loadHistory(): Promise<void> {
    try {
      const raw = await PreferencesManager.getString(HISTORY_KEY, '');
      if (!raw) return;
      const arr = JSON.parse(raw) as HistoryEntry[];
      this.history = Array.isArray(arr) ? arr.slice(0, HISTORY_MAX) : [];
    } catch (_e) {
      this.history = [];
    }
  }

  private async pushHistory(word: string): Promise<void> {
    const filtered = this.history.filter((h) => h.word.toLowerCase() !== word.toLowerCase());
    filtered.unshift({ word, at: Date.now() });
    while (filtered.length > HISTORY_MAX) filtered.pop();
    this.history = filtered;
    try {
      await PreferencesManager.setString(HISTORY_KEY, JSON.stringify(filtered));
    } catch (_e) {}
  }

  // ---- 主动作 ----

  private async run(): Promise<void> {
    const word = this.input.trim();
    if (!word) {
      promptAction.showToast({ message: '请先输入单词' });
      return;
    }
    this.target = word;
    this.loading = true;
    this.errMsg = '';
    this.items = [];
    try {
      const res = await WordAnalysisApi.getAssociations(word, this.mode);
      this.items = res.associations;
      if (this.items.length === 0) {
        this.errMsg = '未生成关联词，可点「再生成」重试';
      }
      await this.pushHistory(word);
    } catch (e) {
      this.errMsg = (e as Error).message ?? '请求失败';
    } finally {
      this.loading = false;
    }
  }

  private nextMode(): void {
    this.mode = this.mode === 'semantic' ? 'thematic' : this.mode === 'thematic' ? 'phonetic' : 'semantic';
  }

  private async regen(): Promise<void> {
    this.nextMode();
    if (this.target) {
      this.input = this.target;
    }
    await this.run();
  }

  private modeLabel(): string {
    return this.mode === 'phonetic' ? '形近' : this.mode === 'thematic' ? '场景' : '语义';
  }

  private relationLabel(rel: WordAssoc['relation']): string {
    if (rel === 'synonym') return '同义';
    if (rel === 'antonym') return '反义';
    if (rel === 'family') return '词族';
    if (rel === 'context') return '同场景';
    return '关联';
  }

  private relationColor(rel: WordAssoc['relation']): string {
    if (rel === 'synonym') return '#10B981';
    if (rel === 'antonym') return '#EF4444';
    if (rel === 'family') return '#A78BFA';
    if (rel === 'context') return '#F59E0B';
    return '#6B7280';
  }

  // ---- 详情 ----

  private openDetail(word: string): void {
    this.detailWord = word;
    this.detailContext = `In relation to the word "${this.target}"`;
    this.showDetail = true;
  }

  private closeDetail(): void {
    this.showDetail = false;
    this.detailWord = '';
    this.detailContext = '';
  }

  private async saveToVocab(data: ExplainData): Promise<void> {
    try {
      const id = (util as ESObject).generateRandomUUID
        ? (util as ESObject).generateRandomUUID(true)
        : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const note: LocalNote = {
        id,
        bookId: 'vocab',
        chapterId: null,
        blockIndex: 0,
        charOffset: 0,
        charLength: data.word.length,
        originalText: data.word,
        noteText: data.definition,
        createdAt: Date.now(),
      };
      await NoteRepository.insert(note);
      promptAction.showToast({ message: '已加入生词本' });
    } catch (_e) {
      promptAction.showToast({ message: '保存失败' });
    }
  }

  // ---- builders ----

  @Builder
  inputBar() {
    Row({ space: AppSpacing.sm }) {
      TextInput({ placeholder: '输入英文单词，如 create', text: this.input })
        .layoutWeight(1)
        .height(40)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.base)
        .onChange((v: string) => { this.input = v; })

      Button('联想')
        .height(40)
        .padding({ left: AppSpacing.base, right: AppSpacing.base })
        .backgroundColor(AppColors.brand)
        .fontColor(AppColors.textInverse)
        .borderRadius(AppRadius.base)
        .onClick(() => this.run())
    }
    .width('100%')
  }

  @Builder
  modeChips() {
    Row({ space: AppSpacing.xs }) {
      Text(`模式：${this.modeLabel()}`)
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textSecondary)
      Blank()
      Button(`再生成 (${this.modeLabel() === '语义' ? '场景' : this.modeLabel() === '场景' ? '形近' : '语义'})`)
        .height(32)
        .padding({ left: AppSpacing.sm, right: AppSpacing.sm })
        .fontSize(AppFontSize.xs)
        .backgroundColor(AppColors.bgSecondary)
        .fontColor(AppColors.textPrimary)
        .borderRadius(AppRadius.sm)
        .enabled(!this.loading && this.target.length > 0)
        .onClick(() => this.regen())
    }
    .width('100%')
  }

  @Builder
  centerNode() {
    Column() {
      Text(this.target || '?')
        .fontSize(AppFontSize.xl)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textInverse)
      Text('中心词')
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textInverse)
        .opacity(0.85)
    }
    .width(120)
    .height(120)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppColors.brand)
    .borderRadius(60)
  }

  @Builder
  assocCard(item: WordAssoc) {
    Column({ space: 4 }) {
      Row() {
        Text(item.word)
          .fontSize(AppFontSize.sm)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.relationLabel(item.relation))
          .fontSize(10)
          .fontColor(AppColors.textInverse)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .backgroundColor(this.relationColor(item.relation))
          .borderRadius(AppRadius.sm)
      }
      .width('100%')
      Text(item.brief)
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textSecondary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpacing.sm)
    .backgroundColor(AppColors.bgElevated)
    .borderRadius(AppRadius.base)
    .onClick(() => this.openDetail(item.word))
  }

  @Builder
  mindMap() {
    if (this.items.length === 0) {
      Column() {
        if (this.loading) {
          LoadingProgress().width(36).height(36).color(AppColors.brand)
          Text('AI 正在生成关联词…')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textTertiary)
            .margin({ top: AppSpacing.sm })
        } else if (this.errMsg) {
          Text('生成失败')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.danger)
          Text(this.errMsg)
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
            .margin({ top: 4 })
        } else {
          Text('输入单词后点「联想」开始')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textTertiary)
        }
      }
      .width('100%')
      .height(220)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      Column({ space: AppSpacing.sm }) {
        // 中心词
        Row() {
          Blank()
          this.centerNode()
          Blank()
        }
        .width('100%')

        // 8 卡片网格（2 列 × 4 行）
        Grid() {
          ForEach(
            this.items,
            (it: WordAssoc) => {
              GridItem() {
                this.assocCard(it)
              }
            },
            (it: WordAssoc, idx: number) => `${idx}-${it.word}`,
          )
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(AppSpacing.sm)
        .rowsGap(AppSpacing.sm)
        .width('100%')
        .height(360)
      }
      .width('100%')
    }
  }

  @Builder
  historySection() {
    if (this.history.length > 0) {
      Column({ space: AppSpacing.xs }) {
        Text('最近查询')
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
          .fontWeight(AppFontWeight.medium)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(
            this.history,
            (h: HistoryEntry) => {
              Text(h.word)
                .fontSize(AppFontSize.xs)
                .fontColor(AppColors.brand)
                .padding({ left: AppSpacing.sm, right: AppSpacing.sm, top: 4, bottom: 4 })
                .backgroundColor('#F5F3FF')
                .borderRadius(AppRadius.sm)
                .margin({ right: AppSpacing.xs, bottom: AppSpacing.xs })
                .onClick(() => {
                  this.input = h.word;
                  this.run();
                })
            },
            (h: HistoryEntry) => `${h.at}-${h.word}`,
          )
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  @Builder
  detailSheet() {
    Column() {
      Row() {
        Text(this.detailWord)
          .fontSize(AppFontSize.lg)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('×')
          .fontSize(AppFontSize.xl)
          .fontColor(AppColors.textTertiary)
          .padding(AppSpacing.xs)
          .onClick(() => this.closeDetail())
      }
      .width('100%')
      .padding(AppSpacing.base)

      Divider().color(AppColors.divider)

      Scroll() {
        ExplainCard({
          word: this.detailWord,
          context: this.detailContext,
          mode: 'word',
          variant: 'compact',
          onSaveToVocab: (d: ExplainData) => this.saveToVocab(d),
          onClose: () => this.closeDetail(),
        })
      }
      .layoutWeight(1)
      .padding(AppSpacing.base)
    }
    .width('100%')
    .height('70%')
    .backgroundColor(AppColors.bgPrimary)
    .borderRadius({ topLeft: AppRadius.lg, topRight: AppRadius.lg })
  }

  build() {
    NavDestination() {
      Column() {
        // header
        Row() {
          Text('< 返回')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.brand)
            .onClick(() => RouterService.pop())
          Blank()
          Text('单词联想')
            .fontSize(AppFontSize.lg)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textPrimary)
          Blank()
          // 占位保持 title 居中
          Text('     ').fontSize(AppFontSize.sm)
        }
        .width('100%')
        .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.sm, bottom: AppSpacing.sm })

        Scroll() {
          Column({ space: AppSpacing.base }) {
            this.inputBar();
            this.modeChips();
            this.mindMap();
            this.historySection();
          }
          .width('100%')
          .padding(AppSpacing.base)
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgPrimary)
      .bindSheet($$this.showDetail, this.detailSheet(), {
        height: '70%',
        showClose: false,
        dragBar: true,
      })
    }
    .hideTitleBar(true)
  }
}
