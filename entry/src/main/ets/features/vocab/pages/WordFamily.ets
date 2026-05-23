/**
 * WordFamily — 词族分析页（W9-C4）
 *
 * 流程：
 *   1. 输入 target word（或从 Vocab 跳转携带 word 参数）
 *   2. 调 WordAnalysisApi.getWordFamily(word) 获取词根 + 派生词
 *   3. 顶部显示词根卡（root + origin + 中文含义）
 *   4. 派生词按词性分组（名词 / 动词 / 形容词 / 副词 / 其它）网格展示
 *   5. 点击派生词 → 弹出 ExplainCard 详情 + 加入生词本
 *
 * TODO(W9-A 集成)：
 *   Vocab.ets 创建后，在 Vocab item 长按菜单中加入「词族」入口，
 *   调 RouterService.push(RoutePath.WORD_FAMILY, { word: ... })。
 */

import promptAction from '@ohos.promptAction';
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import {
  WordAnalysisApi,
  WordFamilyResult,
  WordFamilyMember,
} from '../../../api/ai/WordAnalysisApi';
import { ExplainCard } from '../../../features/ai-tools/components/ExplainCard';
import { ExplainData } from '../../../model/ExplainData';
import { NoteRepository, LocalNote } from '../../../core/persistence/NoteRepository';
import util from '@ohos.util';

interface WordFamilyParams {
  word?: string;
}

const POS_ORDER: WordFamilyMember['partOfSpeech'][] = ['noun', 'verb', 'adj', 'adv', 'other'];

@Component
export struct WordFamily {
  @Prop params: WordFamilyParams = {};

  @State private input: string = '';
  @State private target: string = '';
  @State private loading: boolean = false;
  @State private errMsg: string = '';
  @State private data: WordFamilyResult | null = null;

  @State private showDetail: boolean = false;
  @State private detailWord: string = '';
  @State private detailContext: string = '';

  aboutToAppear(): void {
    if (this.params && this.params.word) {
      this.input = this.params.word;
      this.run();
    }
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
    this.data = null;
    try {
      const res = await WordAnalysisApi.getWordFamily(word);
      this.data = res;
      if (!res.members || res.members.length === 0) {
        this.errMsg = '未生成词族，可点重试';
      }
    } catch (e) {
      this.errMsg = (e as Error).message ?? '请求失败';
    } finally {
      this.loading = false;
    }
  }

  private posLabel(pos: WordFamilyMember['partOfSpeech']): string {
    if (pos === 'noun') return '名词';
    if (pos === 'verb') return '动词';
    if (pos === 'adj') return '形容词';
    if (pos === 'adv') return '副词';
    return '其它';
  }

  private originLabel(origin: string): string {
    if (origin === 'latin') return '拉丁';
    if (origin === 'greek') return '希腊';
    if (origin === 'english') return '英语';
    return '未知';
  }

  private membersByPos(pos: WordFamilyMember['partOfSpeech']): WordFamilyMember[] {
    if (!this.data) return [];
    return this.data.members.filter((m) => m.partOfSpeech === pos);
  }

  // ---- 详情 ----

  private openDetail(word: string): void {
    this.detailWord = word;
    this.detailContext = `Member of the word family of "${this.target}"`;
    this.showDetail = true;
  }

  private closeDetail(): void {
    this.showDetail = false;
    this.detailWord = '';
    this.detailContext = '';
  }

  private async saveToVocab(d: ExplainData): Promise<void> {
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
        charLength: d.word.length,
        originalText: d.word,
        noteText: d.definition,
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

      Button(this.loading ? '...' : '分析')
        .height(40)
        .padding({ left: AppSpacing.base, right: AppSpacing.base })
        .backgroundColor(AppColors.brand)
        .fontColor(AppColors.textInverse)
        .borderRadius(AppRadius.base)
        .enabled(!this.loading)
        .onClick(() => this.run())
    }
    .width('100%')
  }

  @Builder
  rootCard() {
    if (this.data) {
      Column({ space: AppSpacing.xs }) {
        Row() {
          Text(this.data.root)
            .fontSize(AppFontSize.xl)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textInverse)
          Blank()
          Text(this.originLabel(this.data.rootOrigin))
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.brand)
            .padding({ left: AppSpacing.xs, right: AppSpacing.xs, top: 2, bottom: 2 })
            .backgroundColor(AppColors.textInverse)
            .borderRadius(AppRadius.sm)
        }
        .width('100%')
        if (this.data.rootMeaning && this.data.rootMeaning.length > 0) {
          Text(this.data.rootMeaning)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textInverse)
            .opacity(0.9)
            .width('100%')
        }
        Text(`词族成员：${this.data.members.length}`)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textInverse)
          .opacity(0.75)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(AppSpacing.base)
      .backgroundColor(AppColors.brand)
      .borderRadius(AppRadius.lg)
    }
  }

  @Builder
  memberItem(m: WordFamilyMember) {
    Column({ space: 4 }) {
      Text(m.word)
        .fontSize(AppFontSize.sm)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(m.brief)
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textSecondary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.sm)
    .backgroundColor(AppColors.bgElevated)
    .borderRadius(AppRadius.base)
    .onClick(() => this.openDetail(m.word))
  }

  @Builder
  posSection(pos: WordFamilyMember['partOfSpeech']) {
    Column({ space: AppSpacing.xs }) {
      Text(this.posLabel(pos))
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textTertiary)
        .fontWeight(AppFontWeight.medium)
      Grid() {
        ForEach(
          this.membersByPos(pos),
          (m: WordFamilyMember) => {
            GridItem() {
              this.memberItem(m)
            }
          },
          (m: WordFamilyMember, idx: number) => `${pos}-${idx}-${m.word}`,
        )
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(AppSpacing.sm)
      .rowsGap(AppSpacing.sm)
      .width('100%')
      .height(this.membersByPos(pos).length > 2 ? 160 : 80)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  contentBody() {
    if (this.loading && !this.data) {
      Column() {
        LoadingProgress().width(36).height(36).color(AppColors.brand)
        Text('AI 正在分析词族…')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textTertiary)
          .margin({ top: AppSpacing.sm })
      }
      .width('100%')
      .height(220)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.errMsg && !this.data) {
      Column({ space: AppSpacing.sm }) {
        Text('分析失败')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.danger)
        Text(this.errMsg)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
        Button('重试')
          .height(36)
          .padding({ left: AppSpacing.base, right: AppSpacing.base })
          .backgroundColor(AppColors.brand)
          .fontColor(AppColors.textInverse)
          .borderRadius(AppRadius.base)
          .onClick(() => this.run())
      }
      .width('100%')
      .padding(AppSpacing.base)
      .alignItems(HorizontalAlign.Center)
    } else if (this.data && this.data.members.length > 0) {
      Column({ space: AppSpacing.base }) {
        this.rootCard();
        ForEach(
          POS_ORDER,
          (pos: WordFamilyMember['partOfSpeech']) => {
            if (this.membersByPos(pos).length > 0) {
              this.posSection(pos);
            }
          },
          (pos: WordFamilyMember['partOfSpeech']) => pos,
        )
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      Column() {
        Text('输入单词后点「分析」开始')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textTertiary)
      }
      .width('100%')
      .height(160)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
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
        Row() {
          Text('< 返回')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.brand)
            .onClick(() => RouterService.pop())
          Blank()
          Text('词族分析')
            .fontSize(AppFontSize.lg)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textPrimary)
          Blank()
          Text('     ').fontSize(AppFontSize.sm)
        }
        .width('100%')
        .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.sm, bottom: AppSpacing.sm })

        Scroll() {
          Column({ space: AppSpacing.base }) {
            this.inputBar();
            this.contentBody();
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
