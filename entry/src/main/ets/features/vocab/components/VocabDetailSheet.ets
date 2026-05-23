/**
 * VocabDetailSheet.ets — W9-C1 生词详情底部 Sheet
 *
 * 展示完整的 ExplainData 信息（释义 / 例句 / 词源 / CEFR），
 * 提供：
 *   - 备注编辑（textarea，保存到本地 vocab.note 字段）
 *   - 标签管理（chip 添加 / 删除）
 *   - 「重新查询 AI」按钮（重新调用 explain stream，仅传给上层回调由其执行）
 *   - 「标记掌握」/「删除」/「分享」action bar
 *
 * 用法：
 *   通过 CustomDialogController 弹出，传入 vocab + 回调即可。
 *   组件不直接调用 NoteService / NotesApi，所有持久化由上层接管。
 */

import { EffectiveTheme } from '../../../core/theme/Theme.types';
import {
  useColor,
  TextColors,
  BgColors,
  BorderColors,
  AccentColors,
  BrandPalette,
} from '../../../core/theme/AppColors';
import {
  FontFamily,
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius } from '../../../core/theme/AppSpacing';
import { VocabNoteRecord } from '../../../api/notes/NotesApi';

// ─────────────────────────────────────────────
// 数据契约
// ─────────────────────────────────────────────

export interface VocabDetailActions {
  onMarkKnown?: (vocab: VocabNoteRecord) => void;
  onDelete?: (vocab: VocabNoteRecord) => void;
  onShare?: (vocab: VocabNoteRecord) => void;
  onReExplain?: (vocab: VocabNoteRecord) => void;
  /** 备注 / 标签变更后回调（上层做持久化） */
  onSave?: (vocab: VocabNoteRecord, note: string, tags: string[]) => void;
  onClose?: () => void;
  onTtsRead?: (text: string) => void;
}

@CustomDialog
export struct VocabDetailSheet {
  controller: CustomDialogController;
  /** 必传：当前生词条目 */
  @Prop vocab: VocabNoteRecord = {} as VocabNoteRecord;
  /** 主题（默认 day） */
  @Prop theme: EffectiveTheme = 'day';
  /** 操作回调集合 */
  actions: VocabDetailActions = {};

  @State private note: string = '';
  @State private tagInput: string = '';
  @State private tags: string[] = [];

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  aboutToAppear(): void {
    // 用 sourceContext 字段兜底备注（SRS 后端目前没有独立 note 字段，复用 sourceContext 显示用户输入）
    this.note = this.vocab.sourceContext ?? '';
    this.tags = (this.vocab.aiTags ?? []).slice();
    if (this.vocab.userTag && !this.tags.includes(this.vocab.userTag)) {
      this.tags.push(this.vocab.userTag);
    }
  }

  private addTag(): void {
    const t = this.tagInput.trim();
    if (!t || this.tags.includes(t)) {
      this.tagInput = '';
      return;
    }
    this.tags = [...this.tags, t];
    this.tagInput = '';
  }

  private removeTag(t: string): void {
    this.tags = this.tags.filter((x) => x !== t);
  }

  private handleSave(): void {
    this.actions.onSave?.(this.vocab, this.note, this.tags);
  }

  private handleClose(): void {
    this.handleSave();
    this.actions.onClose?.();
    this.controller.close();
  }

  // ─── builders ───────────────────────────────────────────────

  @Builder
  header() {
    Row({ space: Spacing.s2 }) {
      Text(this.vocab.word ?? '')
        .fontFamily(FontFamily.ui)
        .fontSize(FontSizeToken.title2)
        .fontWeight(FontWeightToken.bold)
        .fontColor(useColor(TextColors.primary, this.isDark))

      if (this.vocab.pronunciation) {
        Text(`/${this.vocab.pronunciation}/`)
          .fontSize(FontSizeToken.subheadline)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
      }

      if (this.vocab.partOfSpeech) {
        Text(this.vocab.partOfSpeech)
          .fontSize(FontSizeToken.caption1)
          .fontColor(useColor(AccentColors.primary, this.isDark))
          .padding({ left: Spacing.s2, right: Spacing.s2, top: 2, bottom: 2 })
          .borderRadius(Radius.sm)
          .backgroundColor(BrandPalette.b100)
      }

      Blank()

      Text('\u{1F50A}') // 🔊
        .fontSize(FontSizeToken.title3)
        .padding(Spacing.s1)
        .onClick(() => this.actions.onTtsRead?.(this.vocab.word ?? ''))

      Text('\u{2715}') // ✕
        .fontSize(FontSizeToken.title3)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
        .padding(Spacing.s1)
        .onClick(() => this.handleClose())
    }
    .width('100%')
  }

  @Builder
  sectionLabel(label: string) {
    Text(label)
      .fontSize(FontSizeToken.caption1)
      .fontWeight(FontWeightToken.medium)
      .fontColor(useColor(TextColors.tertiary, this.isDark))
      .margin({ top: Spacing.s2, bottom: Spacing.s1 })
  }

  @Builder
  definitionBlock() {
    if (this.vocab.definition && this.vocab.definition.length > 0) {
      this.sectionLabel('释义')
      Text(this.vocab.definition)
        .fontSize(FontSizeToken.body)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .lineHeight(LineHeightToken.body)
        .width('100%')
    }
  }

  @Builder
  exampleBlock() {
    if (this.vocab.exampleSentence && this.vocab.exampleSentence.length > 0) {
      this.sectionLabel('例句')
      Column({ space: Spacing.s1 }) {
        Text(this.vocab.exampleSentence)
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
  }

  @Builder
  contextBlock() {
    if (this.vocab.sourceContext && this.vocab.sourceContext.length > 0) {
      this.sectionLabel('上下文')
      Text(this.vocab.sourceContext)
        .fontSize(FontSizeToken.footnote)
        .fontColor(useColor(TextColors.secondary, this.isDark))
        .lineHeight(LineHeightToken.footnote)
        .width('100%')
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  metaRow() {
    Row({ space: Spacing.s2 }) {
      if (this.vocab.difficulty !== null && this.vocab.difficulty !== undefined) {
        Text(`难度 ${this.vocab.difficulty}`)
          .fontSize(FontSizeToken.caption2)
          .fontColor(useColor(TextColors.inverse, this.isDark))
          .padding({ left: Spacing.s2, right: Spacing.s2, top: 2, bottom: 2 })
          .borderRadius(Radius.sm)
          .backgroundColor(useColor(AccentColors.primary, this.isDark))
      }
      Text(`复习 ${this.vocab.reviewCount}次`)
        .fontSize(FontSizeToken.caption2)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
      if (this.vocab.nextReviewAt) {
        Text(`下次：${this.formatDate(this.vocab.nextReviewAt)}`)
          .fontSize(FontSizeToken.caption2)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
      }
    }
    .width('100%')
  }

  @Builder
  tagsBlock() {
    this.sectionLabel('标签')
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(
        this.tags,
        (t: string) => {
          Row({ space: 4 }) {
            Text(t)
              .fontSize(FontSizeToken.caption1)
              .fontColor(useColor(AccentColors.primary, this.isDark))
            Text('\u{2715}')
              .fontSize(FontSizeToken.caption2)
              .fontColor(useColor(TextColors.tertiary, this.isDark))
              .onClick(() => this.removeTag(t))
          }
          .padding({ left: Spacing.s2, right: Spacing.s2, top: 2, bottom: 2 })
          .borderRadius(Radius.full)
          .backgroundColor(BrandPalette.b50)
          .margin({ right: Spacing.s2, bottom: Spacing.s2 })
        },
        (t: string) => t,
      )
      // tag 输入
      Row({ space: 4 }) {
        TextInput({ placeholder: '+ 标签', text: this.tagInput })
          .placeholderColor(useColor(TextColors.tertiary, this.isDark))
          .placeholderFont({ size: FontSizeToken.caption1 })
          .fontSize(FontSizeToken.caption1)
          .fontColor(useColor(TextColors.primary, this.isDark))
          .backgroundColor('transparent')
          .height(28)
          .width(96)
          .onChange((v: string) => { this.tagInput = v; })
          .onSubmit(() => this.addTag())
      }
      .padding({ left: Spacing.s2, right: Spacing.s2 })
      .borderRadius(Radius.full)
      .border({ width: 1, color: useColor(BorderColors.primary, this.isDark), style: BorderStyle.Dashed })
      .margin({ right: Spacing.s2, bottom: Spacing.s2 })
    }
    .width('100%')
  }

  @Builder
  noteBlock() {
    this.sectionLabel('我的备注')
    TextArea({ placeholder: '记录你的理解 / 联想 / 助记...', text: this.note })
      .placeholderColor(useColor(TextColors.tertiary, this.isDark))
      .fontSize(FontSizeToken.subheadline)
      .fontColor(useColor(TextColors.primary, this.isDark))
      .backgroundColor(useColor(BgColors.secondary, this.isDark))
      .borderRadius(Radius.md)
      .padding(Spacing.s2)
      .width('100%')
      .height(96)
      .onChange((v: string) => { this.note = v; })
  }

  @Builder
  actionBar() {
    Row({ space: Spacing.s2 }) {
      Text('\u{2728} 重新查询 AI')
        .layoutWeight(1)
        .fontSize(FontSizeToken.subheadline)
        .fontColor(useColor(TextColors.inverse, this.isDark))
        .textAlign(TextAlign.Center)
        .padding({ top: Spacing.s2, bottom: Spacing.s2 })
        .borderRadius(Radius.md)
        .backgroundColor(useColor(AccentColors.primary, this.isDark))
        .onClick(() => {
          this.handleSave();
          this.actions.onReExplain?.(this.vocab);
        })

      Text('\u{2705}')
        .fontSize(FontSizeToken.title3)
        .padding(Spacing.s2)
        .borderRadius(Radius.md)
        .backgroundColor(useColor(BgColors.secondary, this.isDark))
        .onClick(() => {
          this.handleSave();
          this.actions.onMarkKnown?.(this.vocab);
          this.controller.close();
        })

      Text('\u{1F4E4}')
        .fontSize(FontSizeToken.title3)
        .padding(Spacing.s2)
        .borderRadius(Radius.md)
        .backgroundColor(useColor(BgColors.secondary, this.isDark))
        .onClick(() => this.actions.onShare?.(this.vocab))

      Text('\u{1F5D1}')
        .fontSize(FontSizeToken.title3)
        .padding(Spacing.s2)
        .borderRadius(Radius.md)
        .backgroundColor(useColor(BgColors.secondary, this.isDark))
        .onClick(() => {
          this.actions.onDelete?.(this.vocab);
          this.controller.close();
        })
    }
    .width('100%')
  }

  private formatDate(iso: string): string {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return iso;
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    return `${d.getFullYear()}-${m}-${dd}`;
  }

  build() {
    Column({ space: Spacing.s2 }) {
      // drag handle
      Row()
        .width(40)
        .height(4)
        .backgroundColor(useColor(BorderColors.primary, this.isDark))
        .borderRadius(Radius.full)
        .margin({ top: Spacing.s2, bottom: Spacing.s2 })

      this.header()
      this.metaRow()

      Scroll() {
        Column({ space: Spacing.s2 }) {
          this.definitionBlock()
          this.exampleBlock()
          this.contextBlock()
          this.tagsBlock()
          this.noteBlock()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')

      this.actionBar()
    }
    .width('100%')
    .height('80%')
    .padding({ left: Spacing.s4, right: Spacing.s4, bottom: Spacing.s4 })
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
    .borderRadius({ topLeft: Radius.xl, topRight: Radius.xl })
    .alignItems(HorizontalAlign.Center)
  }
}
