/**
 * PasteFromOtherDeviceSheet.ets — W13-C2 跨端剪贴板接收 sheet
 *
 * 当 DistributedClipboard.subscribeIncoming 收到来自其它设备的 vocab / highlight
 * 类型 payload 时，由调用方（一般是 EntryAbility 或当前活跃页）触发本 sheet 弹起。
 *
 * Body：
 *   - 顶部：来源设备名 + 时间
 *   - 中部：内容预览（vocab → 单词 + 释义；highlight → 文本 + 备注）
 *   - 底部三按钮：「保存到生词本」/「分享回去」/「忽略」
 *
 * 不在此组件做的事：
 *   - 不直接调 NotesApi，由 onSave 回调上抛给业务层（保持组件纯）
 *   - 不直接二次写 pasteboard，由 onShareBack 回调由业务层走 DistributedClipboard.copyVocab
 */

import {
  TextColors,
  BgColors,
  AccentColors,
  BorderColors,
  useColor,
} from '../../../core/theme/AppColors';
import {
  FontFamily,
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius } from '../../../core/theme/AppSpacing';
import { AppSheet } from '../../../ui/primitives/Modal';
import { VocabPayload, HighlightPayload, IncomingEntry } from '../../../features/multi-device/service/distributed/DistributedClipboard';

export interface PasteFromOtherDeviceActions {
  /** 用户选「保存到生词本」（vocab） */
  onSaveVocab?: (v: VocabPayload) => void;
  /** 用户选「保存到笔记」（highlight） */
  onSaveHighlight?: (h: HighlightPayload) => void;
  /** 用户选「分享回去」（任意类型） */
  onShareBack?: (e: IncomingEntry) => void;
  /** 用户选「忽略」/ 关闭 */
  onIgnore?: () => void;
}

@Component
export struct PasteFromOtherDeviceSheet {
  @Link visible: boolean;
  @Prop entry: IncomingEntry;
  @Prop isDark: boolean = false;
  actions: PasteFromOtherDeviceActions = {};

  private get isVocab(): boolean { return this.entry?.kind === 'vocab' && this.entry.vocab !== undefined; }
  private get isHighlight(): boolean { return this.entry?.kind === 'highlight' && this.entry.highlight !== undefined; }

  private formatTime(ms: number): string {
    if (!ms) return '';
    const d = new Date(ms);
    if (Number.isNaN(d.getTime())) return '';
    const hh = String(d.getHours()).padStart(2, '0');
    const mm = String(d.getMinutes()).padStart(2, '0');
    return `${hh}:${mm}`;
  }

  private handleSave(): void {
    if (this.isVocab && this.entry.vocab) {
      this.actions.onSaveVocab?.(this.entry.vocab);
    } else if (this.isHighlight && this.entry.highlight) {
      this.actions.onSaveHighlight?.(this.entry.highlight);
    }
    this.visible = false;
  }

  private handleShareBack(): void {
    this.actions.onShareBack?.(this.entry);
    this.visible = false;
  }

  private handleIgnore(): void {
    this.actions.onIgnore?.();
    this.visible = false;
  }

  // ─── builders ───────────────────────────────────────────────

  @Builder
  sourceRow() {
    Row({ space: Spacing.s2 }) {
      Text('\u{1F4F2}') // 📲
        .fontSize(FontSizeToken.title3)
      Column({ space: 2 }) {
        Text(`来自 ${this.entry?.sourceDeviceName ?? '其它设备'}`)
          .fontSize(FontSizeToken.subheadline)
          .fontWeight(FontWeightToken.medium)
          .fontColor(useColor(TextColors.primary, this.isDark))
        Text(this.formatTime(this.entry?.receivedAt ?? 0))
          .fontSize(FontSizeToken.caption2)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
    }
    .width('100%')
  }

  @Builder
  vocabPreview() {
    if (this.entry?.vocab) {
      Column({ space: Spacing.s2 }) {
        Row({ space: Spacing.s2 }) {
          Text(this.entry.vocab.word)
            .fontFamily(FontFamily.ui)
            .fontSize(FontSizeToken.title2)
            .fontWeight(FontWeightToken.bold)
            .fontColor(useColor(TextColors.primary, this.isDark))
          if (this.entry.vocab.phonetic) {
            Text(`/${this.entry.vocab.phonetic}/`)
              .fontSize(FontSizeToken.subheadline)
              .fontColor(useColor(TextColors.tertiary, this.isDark))
          }
        }
        .width('100%')

        if (this.entry.vocab.definition) {
          Text(this.entry.vocab.definition)
            .fontSize(FontSizeToken.body)
            .fontColor(useColor(TextColors.primary, this.isDark))
            .lineHeight(LineHeightToken.body)
            .width('100%')
        }

        if (this.entry.vocab.context) {
          Text(this.entry.vocab.context)
            .fontSize(FontSizeToken.footnote)
            .fontColor(useColor(TextColors.secondary, this.isDark))
            .fontStyle(FontStyle.Italic)
            .lineHeight(LineHeightToken.footnote)
            .width('100%')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        if (this.entry.vocab.bookTitle) {
          Text(`《${this.entry.vocab.bookTitle}》${this.entry.vocab.chapterTitle ? ' · ' + this.entry.vocab.chapterTitle : ''}`)
            .fontSize(FontSizeToken.caption2)
            .fontColor(useColor(TextColors.tertiary, this.isDark))
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(Spacing.s3)
      .backgroundColor(useColor(BgColors.secondary, this.isDark))
      .borderRadius(Radius.md)
    }
  }

  @Builder
  highlightPreview() {
    if (this.entry?.highlight) {
      Column({ space: Spacing.s2 }) {
        Text(this.entry.highlight.text)
          .fontSize(FontSizeToken.body)
          .fontColor(useColor(TextColors.primary, this.isDark))
          .lineHeight(LineHeightToken.body)
          .width('100%')
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.entry.highlight.note) {
          Text(`备注：${this.entry.highlight.note}`)
            .fontSize(FontSizeToken.subheadline)
            .fontColor(useColor(TextColors.secondary, this.isDark))
            .lineHeight(LineHeightToken.subheadline)
            .width('100%')
        }

        if (this.entry.highlight.bookTitle) {
          Text(`《${this.entry.highlight.bookTitle}》${this.entry.highlight.chapterTitle ? ' · ' + this.entry.highlight.chapterTitle : ''}`)
            .fontSize(FontSizeToken.caption2)
            .fontColor(useColor(TextColors.tertiary, this.isDark))
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(Spacing.s3)
      .backgroundColor(useColor(BgColors.secondary, this.isDark))
      .borderRadius(Radius.md)
    }
  }

  @Builder
  actionBar() {
    Row({ space: Spacing.s2 }) {
      Text('忽略')
        .layoutWeight(1)
        .fontSize(FontSizeToken.subheadline)
        .fontColor(useColor(TextColors.secondary, this.isDark))
        .textAlign(TextAlign.Center)
        .padding({ top: Spacing.s2, bottom: Spacing.s2 })
        .borderRadius(Radius.md)
        .backgroundColor(useColor(BgColors.secondary, this.isDark))
        .onClick(() => this.handleIgnore())

      Text('分享回去')
        .layoutWeight(1)
        .fontSize(FontSizeToken.subheadline)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .textAlign(TextAlign.Center)
        .padding({ top: Spacing.s2, bottom: Spacing.s2 })
        .borderRadius(Radius.md)
        .border({ width: 1, color: useColor(BorderColors.primary, this.isDark) })
        .onClick(() => this.handleShareBack())

      Text(this.isVocab ? '保存到生词本' : '保存到笔记')
        .layoutWeight(1.4)
        .fontSize(FontSizeToken.subheadline)
        .fontWeight(FontWeightToken.medium)
        .fontColor(useColor(TextColors.inverse, this.isDark))
        .textAlign(TextAlign.Center)
        .padding({ top: Spacing.s2, bottom: Spacing.s2 })
        .borderRadius(Radius.md)
        .backgroundColor(useColor(AccentColors.primary, this.isDark))
        .onClick(() => this.handleSave())
    }
    .width('100%')
  }

  @Builder
  sheetBody() {
    Column({ space: Spacing.s3 }) {
      this.sourceRow()
      if (this.isVocab) {
        this.vocabPreview()
      } else if (this.isHighlight) {
        this.highlightPreview()
      } else {
        // 兜底：纯文本 / html
        Text(this.entry?.text ?? this.entry?.html ?? '')
          .fontSize(FontSizeToken.body)
          .fontColor(useColor(TextColors.primary, this.isDark))
          .width('100%')
          .padding(Spacing.s3)
          .backgroundColor(useColor(BgColors.secondary, this.isDark))
          .borderRadius(Radius.md)
      }
      this.actionBar()
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: Spacing.s4, right: Spacing.s4, bottom: Spacing.s4 })
  }

  build() {
    AppSheet({
      visible: $visible,
      title: '收到跨端内容',
      snapPoints: [0.45, 0.7],
      isDark: this.isDark,
      sheetBody: () => this.sheetBody(),
    })
  }
}
