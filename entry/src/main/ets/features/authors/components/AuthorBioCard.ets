// L4 Feature - Authors - Component
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeFollowAuthorIntent, makeUnfollowAuthorIntent } from '../intent/AuthorsIntents';
import type { Author } from '../service/AuthorsService';

@Component
export struct AuthorBioCard {
  @Prop author: Author;

  private onFollowToggle(): void {
    const intent = this.author.followed
      ? makeUnfollowAuthorIntent(this.author.id)
      : makeFollowAuthorIntent(this.author.id);
    IntentBus.getInstance().publish(intent as never);
  }

  build() {
    Column({ space: AppSpacing.base }) {
      Row({ space: AppSpacing.base }) {
        Image(this.author.avatarUrl)
          .width(72)
          .height(72)
          .borderRadius(36)
          .backgroundColor(AppColors.bgSecondary)
        Column({ space: AppSpacing.xs }) {
          Text(this.author.name)
            .fontSize(AppFontSize.lg)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textPrimary)
          Text(`${this.author.bookCount} 部作品`)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
          Button(this.author.followed ? '已关注' : '关注')
            .height(32)
            .backgroundColor(this.author.followed ? AppColors.bgSecondary : AppColors.brand)
            .fontColor(this.author.followed ? AppColors.textSecondary : AppColors.textInverse)
            .fontSize(AppFontSize.sm)
            .borderRadius(AppRadius.base)
            .onClick(() => this.onFollowToggle())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.author.bio) {
        Text(this.author.bio)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textSecondary)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .padding(AppSpacing.base)
    .backgroundColor(AppColors.bgPrimary)
    .borderRadius(AppRadius.base)
  }
}
