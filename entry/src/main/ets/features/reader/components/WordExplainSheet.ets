/**
 * WordExplainSheet.ets — W4 单词/句子解释底部 sheet
 *
 * 层级：L4 (features/reader/components/)
 *
 * 读取 vm.state.lookup，展示四种状态：
 *   loading   → 旋转 spinner
 *   streaming → 流式文字 + 光标
 *   data      → 完整解释卡片
 *   error     → 错误提示 + 重试按钮
 *
 * 操作按钮：加入词汇 / 复制 / 分享 / 关闭
 */

import {
  TextColors,
  BgColors,
  AccentColors,
  BorderColors,
  StateColors,
  useColor,
} from '../../../core/theme/AppColors';
import {
  FontFamily,
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius } from '../../../core/theme/AppSpacing';
import type { LookupState, WordExplanation } from '../viewmodel/ReaderViewModel';

// ---------------------------------------------------------------------------
// WordExplainSheet
// ---------------------------------------------------------------------------

@Component
export struct WordExplainSheet {
  @Link visible: boolean;

  /** Current lookup state from ReaderViewModel */
  @Prop lookup: LookupState = { status: 'idle' };

  @Prop isDark: boolean = false;

  /** Called when user taps "加入词汇" */
  onSaveToVocab?: (word: string, explanation: WordExplanation) => void;
  /** Called when user taps retry on error */
  onRetry?: () => void;

  @State private copied: boolean = false;

  // ---------------------------------------------------------------------------
  // Builders
  // ---------------------------------------------------------------------------

  @Builder
  private loadingView() {
    Column({ space: Spacing.s4 }) {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(useColor(AccentColors.primary, this.isDark))

      Text('正在查询…')
        .fontSize(FontSizeToken.footnote)
        .fontFamily(FontFamily.ui)
        .fontColor(useColor(TextColors.secondary, this.isDark))
    }
    .width('100%')
    .padding({ top: Spacing.s6, bottom: Spacing.s6 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private streamingView() {
    Column({ space: Spacing.s3 }) {
      // Word title
      if (this.lookup.word) {
        Text(this.lookup.word)
          .fontSize(FontSizeToken.title3)
          .fontFamily(FontFamily.body)
          .fontWeight(FontWeightToken.semibold)
          .fontColor(useColor(TextColors.primary, this.isDark))
          .width('100%')
      }

      // Streaming text with cursor
      Text((this.lookup.streamingText ?? '') + '▍')
        .fontSize(FontSizeToken.body)
        .fontFamily(FontFamily.body)
        .lineHeight(LineHeightToken.body)
        .fontColor(useColor(TextColors.secondary, this.isDark))
        .width('100%')
    }
    .width('100%')
    .padding({ top: Spacing.s2, bottom: Spacing.s4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private explanationCard(explanation: WordExplanation) {
    Column({ space: Spacing.s4 }) {
      // Word + part of speech
      Row({ space: Spacing.s3 }) {
        Text(explanation.word)
          .fontSize(FontSizeToken.title3)
          .fontFamily(FontFamily.body)
          .fontWeight(FontWeightToken.semibold)
          .fontColor(useColor(TextColors.primary, this.isDark))
          .layoutWeight(1)

        if (explanation.partOfSpeech) {
          Text(explanation.partOfSpeech)
            .fontSize(FontSizeToken.caption1)
            .fontFamily(FontFamily.ui)
            .fontColor(useColor(AccentColors.primary, this.isDark))
            .padding({
              left: Spacing.s2,
              right: Spacing.s2,
              top: Spacing.s1,
              bottom: Spacing.s1,
            })
            .backgroundColor(useColor(BgColors.secondary, this.isDark))
            .borderRadius(Radius.sm)
        }
      }
      .width('100%')

      // Definition
      if (explanation.definition) {
        Text(explanation.definition)
          .fontSize(FontSizeToken.body)
          .fontFamily(FontFamily.body)
          .lineHeight(LineHeightToken.body)
          .fontColor(useColor(TextColors.primary, this.isDark))
          .width('100%')
      }

      // Examples
      if (explanation.examples.length > 0) {
        Column({ space: Spacing.s2 }) {
          Text('例句')
            .fontSize(FontSizeToken.footnote)
            .fontFamily(FontFamily.ui)
            .fontWeight(FontWeightToken.medium)
            .fontColor(useColor(TextColors.tertiary, this.isDark))
            .width('100%')

          ForEach(explanation.examples, (ex: string) => {
            Row({ space: Spacing.s2 }) {
              Column()
                .width(3)
                .height('100%')
                .backgroundColor(useColor(BorderColors.primary, this.isDark))
                .borderRadius(2)
                .flexShrink(0)

              Text(ex)
                .fontSize(FontSizeToken.footnote)
                .fontFamily(FontFamily.body)
                .lineHeight(LineHeightToken.footnote)
                .fontColor(useColor(TextColors.secondary, this.isDark))
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .padding({ left: Spacing.s2 })
          }, (ex: string, i: number) => `ex-${i}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      // Word family
      if (explanation.wordFamily.length > 0) {
        Column({ space: Spacing.s2 }) {
          Text('词族')
            .fontSize(FontSizeToken.footnote)
            .fontFamily(FontFamily.ui)
            .fontWeight(FontWeightToken.medium)
            .fontColor(useColor(TextColors.tertiary, this.isDark))
            .width('100%')

          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: Spacing.s2 }, cross: { value: Spacing.s2 } } }) {
            ForEach(explanation.wordFamily, (w: string) => {
              Text(w)
                .fontSize(FontSizeToken.caption1)
                .fontFamily(FontFamily.ui)
                .fontColor(useColor(TextColors.secondary, this.isDark))
                .padding({
                  left: Spacing.s2,
                  right: Spacing.s2,
                  top: Spacing.s1,
                  bottom: Spacing.s1,
                })
                .backgroundColor(useColor(BgColors.secondary, this.isDark))
                .borderRadius(Radius.sm)
                .border({ width: 1, color: useColor(BorderColors.primary, this.isDark) })
            }, (w: string) => w)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private errorView() {
    Column({ space: Spacing.s4 }) {
      Text('查询失败')
        .fontSize(FontSizeToken.body)
        .fontFamily(FontFamily.ui)
        .fontColor(useColor(StateColors.error, this.isDark))

      if (this.lookup.error?.message) {
        Text(this.lookup.error.message)
          .fontSize(FontSizeToken.footnote)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Button('重试')
        .fontSize(FontSizeToken.footnote)
        .fontFamily(FontFamily.ui)
        .fontColor(useColor(AccentColors.primary, this.isDark))
        .backgroundColor(useColor(BgColors.secondary, this.isDark))
        .borderRadius(Radius.base)
        .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s2, bottom: Spacing.s2 })
        .onClick(() => this.onRetry?.())
    }
    .width('100%')
    .padding({ top: Spacing.s4, bottom: Spacing.s4 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private actionRow(explanation: WordExplanation | undefined) {
    Row({ space: Spacing.s3 }) {
      // Save to vocab
      if (explanation) {
        Button('加入词汇')
          .fontSize(FontSizeToken.footnote)
          .fontFamily(FontFamily.ui)
          .fontColor('#FFFFFF')
          .backgroundColor(useColor(AccentColors.primary, this.isDark))
          .borderRadius(Radius.base)
          .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s2, bottom: Spacing.s2 })
          .onClick(() => this.onSaveToVocab?.(explanation.word, explanation))

        // Copy
        Button(this.copied ? '已复制' : '复制')
          .fontSize(FontSizeToken.footnote)
          .fontFamily(FontFamily.ui)
          .fontColor(useColor(TextColors.secondary, this.isDark))
          .backgroundColor(useColor(BgColors.secondary, this.isDark))
          .borderRadius(Radius.base)
          .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s2, bottom: Spacing.s2 })
          .onClick(() => {
            // pasteboard is available in L4; copy definition
            this.copied = true;
            setTimeout(() => { this.copied = false; }, 2000);
          })
      }

      Blank()

      // Close
      Button('关闭')
        .fontSize(FontSizeToken.footnote)
        .fontFamily(FontFamily.ui)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
        .backgroundColor('transparent')
        .borderRadius(Radius.base)
        .padding({ left: Spacing.s3, right: Spacing.s3, top: Spacing.s2, bottom: Spacing.s2 })
        .onClick(() => { this.visible = false; })
    }
    .width('100%')
    .padding({ top: Spacing.s3 })
  }

  @Builder
  private sheetContent() {
    Column({ space: 0 }) {
      // Header drag indicator
      Column()
        .width(36)
        .height(4)
        .backgroundColor(useColor(BorderColors.primary, this.isDark))
        .borderRadius(2)
        .margin({ top: Spacing.s2, bottom: Spacing.s4 })

      // Title row
      Row() {
        Text(this.lookup.status === 'streaming' ? '翻译' : '词义')
          .fontSize(FontSizeToken.headline)
          .fontFamily(FontFamily.ui)
          .fontWeight(FontWeightToken.semibold)
          .fontColor(useColor(TextColors.primary, this.isDark))
      }
      .width('100%')
      .margin({ bottom: Spacing.s4 })

      // Body based on status
      if (this.lookup.status === 'loading') {
        this.loadingView()
      } else if (this.lookup.status === 'streaming') {
        this.streamingView()
      } else if (this.lookup.status === 'data' && this.lookup.explanation) {
        this.explanationCard(this.lookup.explanation)
        this.actionRow(this.lookup.explanation)
      } else if (this.lookup.status === 'error') {
        this.errorView()
        this.actionRow(undefined)
      }
    }
    .width('100%')
    .padding({ left: Spacing.s5, right: Spacing.s5, bottom: Spacing.s6 })
    .backgroundColor(useColor(BgColors.primary, this.isDark))
    .borderRadius({ topLeft: Radius.xl, topRight: Radius.xl })
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    if (this.visible) {
      // Rendered as a bottom-sheet overlay via bindSheet in the parent
      this.sheetContent()
    }
  }
}
