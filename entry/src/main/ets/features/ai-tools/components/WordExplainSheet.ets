import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { AiApi } from '../../../api/ai/AiApi';
import { NotesApi } from '../../../api/notes/NotesApi';
import { NoteRepository, LocalNote } from '../../../core/persistence/NoteRepository';
import { UserStore } from '../../../store/UserStore';
import { SettingsStore } from '../../../store/SettingsStore';
import { ExplainCard, StructuredExplain, parseExplainJson } from './ExplainCard';
import promptAction from '@ohos.promptAction';
import util from '@ohos.util';

export interface WordExplainContext {
  word: string;
  contextSentence: string;
  bookId: string;
  chapterId: string;
  blockIndex: number;
  charOffset: number;
  charLength: number;
}

@CustomDialog
export struct WordExplainSheet {
  controller?: CustomDialogController;
  ctx: WordExplainContext = {
    word: '',
    contextSentence: '',
    bookId: '',
    chapterId: '',
    blockIndex: 0,
    charOffset: 0,
    charLength: 0,
  };

  @State streamedText: string = '';
  @State streaming: boolean = true;
  @State errMsg: string = '';
  @State saved: boolean = false;
  @State structured: StructuredExplain | null = null;
  private stopFn: (() => void) | null = null;

  aboutToAppear(): void {
    this.startStream();
  }

  aboutToDisappear(): void {
    this.stopFn?.();
    this.stopFn = null;
  }

  private startStream(): void {
    this.streamedText = '';
    this.errMsg = '';
    this.streaming = true;
    this.structured = null;

    this.stopFn = AiApi.explainWordStream(
      {
        word: this.ctx.word,
        context: this.ctx.contextSentence,
        locale: SettingsStore.getLocale(),
        cefrLevel: 'B1',
      },
      {
        onChunk: (delta: string) => {
          this.streamedText += delta;
        },
        onDone: () => {
          this.streaming = false;
          // 流式结束尝试解析为结构化卡片
          const parsed = parseExplainJson(this.streamedText);
          if (parsed) {
            this.structured = parsed;
          }
        },
        onError: (e: Error) => {
          this.streaming = false;
          this.errMsg = e.message ?? '请求失败';
        },
      },
    );
  }

  private async onSave(): Promise<void> {
    if (this.saved) return;
    const localId = util.generateRandomUUID(true);
    // 优先存结构化中的 definition；否则存 raw 流式文本
    const noteText = this.structured?.definition ?? this.streamedText;
    const note: LocalNote = {
      id: localId,
      bookId: this.ctx.bookId,
      chapterId: this.ctx.chapterId,
      blockIndex: this.ctx.blockIndex,
      charOffset: this.ctx.charOffset,
      charLength: this.ctx.charLength,
      originalText: this.ctx.word,
      noteText,
      createdAt: Date.now(),
    };
    try {
      await NoteRepository.insert(note);
      this.saved = true;
      promptAction.showToast({ message: '已保存到笔记' });
    } catch (e) {
      promptAction.showToast({ message: '本地保存失败' });
      return;
    }

    // 登录态下后台异步推到 server-cn
    if (UserStore.isLoggedIn()) {
      NotesApi.create({
        bookId: this.ctx.bookId,
        chapterId: this.ctx.chapterId,
        blockIndex: this.ctx.blockIndex,
        charOffset: this.ctx.charOffset,
        charLength: this.ctx.charLength,
        originalText: this.ctx.word,
        noteText,
        kind: 'word',
      }).catch(() => {
        // 静默：本地已存，下次同步任务再推
      });
    }
  }

  build() {
    Column({ space: AppSpacing.base }) {
      Row() {
        Text(this.ctx.word)
          .fontSize(AppFontSize.xl)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('×')
          .fontSize(AppFontSize.xl)
          .fontColor(AppColors.textSecondary)
          .padding(AppSpacing.xs)
          .onClick(() => this.controller?.close())
      }
      .width('100%')

      Text(this.ctx.contextSentence)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textTertiary)
        .fontStyle(FontStyle.Italic)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Divider().color(AppColors.divider)

      Scroll() {
        Column() {
          if (this.errMsg) {
            Text(this.errMsg)
              .fontSize(AppFontSize.sm)
              .fontColor(AppColors.danger)
              .width('100%')
          } else if (this.structured) {
            ExplainCard({ data: this.structured })
          } else {
            Text(this.streamedText.length > 0 ? this.streamedText : '...')
              .fontSize(AppFontSize.base)
              .fontColor(AppColors.textPrimary)
              .lineHeight(24)
              .width('100%')
          }
          if (this.streaming) {
            LoadingProgress()
              .width(20).height(20).color(AppColors.brand)
              .margin({ top: AppSpacing.sm })
          }
        }
        .alignItems(HorizontalAlign.Start)
      }
      .height(280)
      .width('100%')

      Row({ space: AppSpacing.sm }) {
        Button(this.saved ? '已保存' : '保存笔记')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.saved ? AppColors.bgSecondary : AppColors.brand)
          .fontColor(this.saved ? AppColors.textSecondary : AppColors.textInverse)
          .borderRadius(AppRadius.base)
          .enabled(!this.streaming && !this.saved && !this.errMsg)
          .onClick(() => this.onSave())

        Button(this.errMsg ? '重试' : '关闭')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(AppColors.bgSecondary)
          .fontColor(AppColors.textPrimary)
          .borderRadius(AppRadius.base)
          .onClick(() => {
            if (this.errMsg) {
              this.startStream();
            } else {
              this.controller?.close();
            }
          })
      }
      .width('100%')
    }
    .padding(AppSpacing.lg)
    .backgroundColor(AppColors.bgPrimary)
    .borderRadius({ topLeft: AppRadius.xl, topRight: AppRadius.xl })
    .width('100%')
  }
}
