// L4 - features/agora - Component
import type { AgoraPost } from '../viewmodel/AgoraViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeLikePostIntent, makeUnlikePostIntent, makeOpenPostIntent } from '../intent/AgoraIntents';

@Component
export struct AgoraPostCard {
  @Prop post: AgoraPost;

  build() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Text(this.post.authorName.charAt(0))
          .width(36)
          .height(36)
          .fontSize(16)
          .fontColor('#fff')
          .backgroundColor('#6750A4')
          .borderRadius(18)
          .textAlign(TextAlign.Center)
        Column({ space: 2 }) {
          Text(this.post.authorName).fontSize(14).fontWeight(FontWeight.Medium)
          Text(this.post.createdAt).fontSize(12).fontColor('#888')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Text(this.post.text)
        .fontSize(15)
        .lineHeight(22)
        .width('100%')

      Row({ space: 20 }) {
        Button(`${this.post.likeCount}`)
          .fontSize(13)
          .fontColor(this.post.liked ? '#6750A4' : '#888')
          .backgroundColor('transparent')
          .onClick(() => {
            const intent = this.post.liked
              ? makeUnlikePostIntent(this.post.id)
              : makeLikePostIntent(this.post.id);
            IntentBus.getInstance().publish(intent as never);
          })
        Button(`${this.post.commentCount}`)
          .fontSize(13)
          .fontColor('#888')
          .backgroundColor('transparent')
          .onClick(() => {
            IntentBus.getInstance().publish(makeOpenPostIntent(this.post.id) as never);
          })
      }
      .width('100%')
    }
    .padding(16)
    .width('100%')
    .backgroundColor('#fff')
    .borderRadius(12)
  }
}
