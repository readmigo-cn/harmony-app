/**
 * LookupPage — 划词查询元服务页面（W11-C1）
 *
 * 由 LookupAbility 通过 windowStage.loadContent('pages/atomic/LookupPage') 拉起。
 * 元服务全屏页：
 *   - 顶部：当前词显示 + 输入框（用户可改词重查）
 *   - 主体：ExplainCard expanded 模式（流式 SSE 解释）
 *   - 底部：保存到生词本 / 跳到主 App 完整阅读 / 关闭
 *
 * 数据来源：
 *   - LookupAbility 把 want.parameters.word/context 写入 AppStorage
 *     (LOOKUP_CURRENT_WORD_KEY / LOOKUP_CURRENT_CONTEXT_KEY)
 *   - 本页 @StorageLink 监听 word 变化 → 重新触发 ExplainCard
 *
 * 元服务 vs 主 App 边界：
 *   - 共享：bundleName 同包，AppStorage 同进程；NoteRepository / VocabRepository 同 RDB
 *   - 隔离：本页不依赖 RouterService / NavPathStack（元服务 cold 启动时主 App 未启）
 *           所有外链跳转走 AtomicLauncher.launchMainAppFromAtomic
 */

import { AppColors } from '../../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../../core/theme/AppSpacing';
import { ExplainCard } from '../../../../features/ai-tools/components/ExplainCard';
import { AppButton } from '../../../../ui/primitives/Button';
import { AppInput } from '../../../../ui/primitives/Input';
import { LoadingIndicator } from '../../../../ui/primitives/Loading';
import { ExplainData } from '../../../../model/ExplainData';
import { AtomicLauncher } from '../../../../core/atomic/AtomicLauncher';
import {
  LOOKUP_CURRENT_WORD_KEY,
  LOOKUP_CURRENT_CONTEXT_KEY,
  LOOKUP_CURRENT_SOURCE_KEY,
  LOOKUP_RESULT_KEY,
} from '../../../../abilities/LookupAbility';
import { NoteRepository, LocalNote } from '../../../../core/persistence/NoteRepository';
import { ThemeProvider } from '../../../../core/theme/ThemeProvider';
import promptAction from '@ohos.promptAction';
import util from '@ohos.util';
import common from '@ohos.app.ability.common';

@Entry
@Component
struct LookupPage {
  /** 当前要查询的词；与 LookupAbility 共享同一 AppStorage key */
  @StorageLink(LOOKUP_CURRENT_WORD_KEY) currentWord: string = '';
  /** 上下文句子（可选） */
  @StorageLink(LOOKUP_CURRENT_CONTEXT_KEY) currentContext: string = '';
  /** 来源：'main_app' / 'nfc' / 'deep_link' / 'unknown' */
  @StorageLink(LOOKUP_CURRENT_SOURCE_KEY) source: string = 'unknown';

  /** 输入框双向绑定（与 currentWord 解耦：用户可改值再「查询」） */
  @State private inputWord: string = '';
  /** ExplainCard remount 触发器：每次 word 变更 +1，用 if/key 强制重建 */
  @State private explainKey: number = 0;
  /** 是否展示「跳到主 App」加载态 */
  @State private launchingMainApp: boolean = false;
  /** 错误态（输入校验等） */
  @State private inputError: string = '';

  // ---------- lifecycle ----------

  aboutToAppear(): void {
    if (this.currentWord) {
      this.inputWord = this.currentWord;
    }
  }

  /**
   * 监听 currentWord 变化（NFC hot-relaunch / 用户修改）→ remount ExplainCard
   * StorageLink 自带响应，但 ExplainCard 是基于 @Prop，需要 key bump 触发 remount。
   */
  private onWordSync(): void {
    if (this.currentWord && this.currentWord !== this.inputWord) {
      this.inputWord = this.currentWord;
    }
    this.explainKey++;
  }

  // ---------- actions ----------

  private onSubmitInput(): void {
    const trimmed = this.inputWord.trim();
    if (!trimmed) {
      this.inputError = '请输入要查询的单词';
      return;
    }
    this.inputError = '';
    this.currentWord = trimmed;
    this.currentContext = '';
    this.explainKey++;
  }

  /**
   * 保存到生词本：写本地 RDB（NoteRepository），后台 sync 服务会自动推到云端。
   * 元服务和主 App 同包，DB 共享。
   */
  private async onSaveToVocab(data: ExplainData): Promise<void> {
    try {
      const u = util as ESObject;
      const id: string = u.generateRandomUUID
        ? u.generateRandomUUID(true)
        : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const note: LocalNote = {
        id,
        bookId: 'atomic_lookup',
        chapterId: null,
        blockIndex: 0,
        charOffset: 0,
        charLength: data.word.length,
        originalText: data.word,
        noteText: data.definition,
        createdAt: Date.now(),
      };
      await NoteRepository.insert(note);
      // 写入 LOOKUP_RESULT_KEY，供 LookupAbility.terminateSelfWithResult 回包给 caller
      AppStorage.SetOrCreate<string>(
        LOOKUP_RESULT_KEY,
        JSON.stringify({ saved: true, word: data.word, id }),
      );
      promptAction.showToast({ message: '已加入生词本' });
    } catch (e) {
      console.error(`LookupPage saveToVocab failed: ${(e as Error).message}`);
      promptAction.showToast({ message: '保存失败，请稍后重试' });
    }
  }

  /** 跳到主 App 阅读器（携带 word，主 App 跳 Reader 后自动搜索）。 */
  private async onOpenInMainApp(): Promise<void> {
    if (!this.currentWord) {
      promptAction.showToast({ message: '请先选择要查询的单词' });
      return;
    }
    this.launchingMainApp = true;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await AtomicLauncher.launchMainAppFromAtomic(ctx, this.currentWord);
    } catch (e) {
      console.error(`LookupPage launchMainApp failed: ${(e as Error).message}`);
      promptAction.showToast({ message: '无法打开主 App' });
    } finally {
      this.launchingMainApp = false;
    }
  }

  /** 关闭元服务窗口。 */
  private async onClose(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await ctx.terminateSelf();
    } catch (e) {
      console.warn(`LookupPage terminateSelf failed: ${(e as Error).message}`);
    }
  }

  /** 来源标签（顶部小提示，让用户知道入口）。 */
  private get sourceLabel(): string {
    switch (this.source) {
      case 'nfc': return '碰一碰';
      case 'deep_link': return '链接';
      case 'main_app': return '阅读';
      default: return '元服务';
    }
  }

  // ---------- builders ----------

  build() {
    // ThemeProvider 提供 @Provide('theme')，AppInput / AppButton 内部 @Consume 才能拿到
    ThemeProvider({ content: () => { this.lookupContent() } })
  }

  @Builder
  lookupContent() {
    Column() {
      this.header()
      Divider().color(AppColors.divider)
      // 主体：ExplainCard 全屏 expanded
      Scroll() {
        if (this.currentWord && this.currentWord.length > 0) {
          // key bump 强制 remount → ExplainCard 重新发起 SSE
          ExplainCard({
            word: this.currentWord,
            context: this.currentContext,
            mode: 'word',
            variant: 'expanded',
            level: 'B1',
            onSaveToVocab: (d: ExplainData) => this.onSaveToVocab(d),
            onClose: () => this.onClose(),
          })
        } else {
          this.emptyState()
        }
      }
      .layoutWeight(1)
      .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.sm })

      Divider().color(AppColors.divider)
      this.bottomBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
    .onAppear(() => this.onWordSync())
  }

  @Builder
  header() {
    Column({ space: AppSpacing.xs }) {
      Row({ space: AppSpacing.sm }) {
        Text(this.sourceLabel)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.brand)
          .backgroundColor(AppColors.bgSecondary)
          .padding({ left: AppSpacing.xs, right: AppSpacing.xs, top: 2, bottom: 2 })
          .borderRadius(AppRadius.sm)
        Text('划词查词')
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.semibold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('✕')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
          .padding(AppSpacing.xs)
          .onClick(() => this.onClose())
      }
      .width('100%')

      AppInput({
        value: $inputWord,
        placeholder: '输入要查询的英文单词',
        size: 'md',
        autoFocus: false,
        showClear: true,
        errorMessage: this.inputError,
        onSubmit: () => this.onSubmitInput(),
      })

      if (this.currentContext && this.currentContext.length > 0) {
        Text(`上下文：${this.currentContext}`)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding(AppSpacing.base)
  }

  @Builder
  emptyState() {
    Column({ space: AppSpacing.base }) {
      Text('🔍')
        .fontSize(48)
      Text('请输入要查询的单词')
        .fontSize(AppFontSize.md)
        .fontColor(AppColors.textPrimary)
      Text('支持碰一碰 NFC 词卡、短链 readmigo://lookup?word=xxx')
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textTertiary)
        .textAlign(TextAlign.Center)
      AppButton({
        label: '查询',
        variant: 'primary',
        size: 'md',
        onClick: () => this.onSubmitInput(),
      })
    }
    .width('100%')
    .padding(AppSpacing.lg)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  bottomBar() {
    Row({ space: AppSpacing.sm }) {
      AppButton({
        label: '完整阅读',
        variant: 'ghost',
        size: 'md',
        onClick: () => this.onOpenInMainApp(),
      })
      .layoutWeight(1)

      if (this.launchingMainApp) {
        LoadingIndicator({ size: 'sm' })
      }

      AppButton({
        label: '关闭',
        variant: 'secondary',
        size: 'md',
        onClick: () => this.onClose(),
      })
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.sm, bottom: AppSpacing.base })
  }
}
