// L4 Feature - Quotes - QuoteCard component
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeLikeQuoteIntent, makeOpenDetailIntent } from '../intent/QuotesIntents';
import type { Quote } from '../../../model/Quote';

@Component
export struct QuoteCard {
  @Prop quote: Quote;

  build() {
    Column({ space: AppSpacing.sm }) {
      Text(`"${this.quote.text}"`)
        .fontSize(AppFontSize.md)
        .fontColor(AppColors.textPrimary)
        .fontStyle(FontStyle.Italic)
        .maxLines(6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row() {
        Column({ space: 2 }) {
          Text(this.quote.author)
            .fontSize(AppFontSize.sm)
            .fontWeight(AppFontWeight.medium)
            .fontColor(AppColors.textSecondary)
          if (this.quote.bookTitle) {
            Text(this.quote.bookTitle)
              .fontSize(AppFontSize.xs)
              .fontColor(AppColors.textTertiary)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row({ space: AppSpacing.sm }) {
          Text(this.quote.liked ? '♥' : '♡')
            .fontSize(AppFontSize.lg)
            .fontColor(this.quote.liked ? AppColors.danger : AppColors.textTertiary)
            .onClick(() => {
              IntentBus.getInstance().publish(makeLikeQuoteIntent(this.quote.id));
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .padding(AppSpacing.base)
    .backgroundColor(AppColors.bgPrimary)
    .borderRadius(AppRadius.base)
    .width('100%')
    .onClick(() => {
      IntentBus.getInstance().publish(makeOpenDetailIntent(this.quote.id));
    })
  }
}
