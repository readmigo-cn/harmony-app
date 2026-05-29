// L4 Feature - Quotes - QuoteDetailPage
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeLikeQuoteIntent, makeShareQuoteIntent } from '../intent/QuotesIntents';
import type { Quote } from '../../../model/Quote';
import type { QuotesState } from '../viewmodel/QuotesViewModel';
import promptAction from '@ohos.promptAction';

@Component
export struct QuoteDetailPage {
  @Prop vmState: QuotesState;

  private quote(): Quote | undefined {
    return this.vmState.status === 'data' ? this.vmState.data.selected : undefined;
  }

  build() {
    NavDestination() {
      if (this.vmState.status === 'loading') {
        Column() {
          LoadingProgress().width(40).height(40).color(AppColors.brand)
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else if (this.vmState.status === 'data' && this.quote()) {
        const q = this.quote()!;
        Column({ space: AppSpacing.lg }) {
          Column({ space: AppSpacing.base }) {
            Text(`"${q.text}"`)
              .fontSize(AppFontSize.lg)
              .fontStyle(FontStyle.Italic)
              .fontColor(AppColors.textPrimary)
              .width('100%')
              .textAlign(TextAlign.Center)

            Text(`— ${q.author}`)
              .fontSize(AppFontSize.md)
              .fontColor(AppColors.textSecondary)
              .fontWeight(AppFontWeight.medium)
              .width('100%')
              .textAlign(TextAlign.Center)

            if (q.bookTitle) {
              Text(q.bookTitle)
                .fontSize(AppFontSize.sm)
                .fontColor(AppColors.textTertiary)
                .width('100%')
                .textAlign(TextAlign.Center)
            }
          }
          .padding(AppSpacing.xl)
          .backgroundColor(AppColors.bgPrimary)
          .borderRadius(AppRadius.lg)
          .width('100%')

          Row({ space: AppSpacing.base }) {
            Button(q.liked ? '已喜欢' : '喜欢')
              .width('45%')
              .backgroundColor(q.liked ? AppColors.danger : AppColors.bgSecondary)
              .fontColor(q.liked ? AppColors.textInverse : AppColors.textPrimary)
              .borderRadius(AppRadius.base)
              .onClick(() => {
                IntentBus.getInstance().publish(makeLikeQuoteIntent(q.id));
              })

            Button('分享')
              .width('45%')
              .backgroundColor(AppColors.brand)
              .fontColor(AppColors.textInverse)
              .borderRadius(AppRadius.base)
              .onClick(() => {
                IntentBus.getInstance().publish(makeShareQuoteIntent(q.id));
                promptAction.showToast({ message: '分享功能即将开放' });
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .padding(AppSpacing.lg)
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppColors.bgSecondary)
      } else {
        Column() {
          Text('内容不存在').fontSize(AppFontSize.sm).fontColor(AppColors.textTertiary)
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      }
    }
    .title('金句详情')
  }
}
