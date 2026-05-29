// L4 - features/agora - Component
import type { AgoraComment } from '../viewmodel/AgoraViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeLikeCommentIntent } from '../intent/AgoraIntents';

@Component
export struct CommentRow {
  @Prop comment: AgoraComment;

  build() {
    Row({ space: 10 }) {
      Text(this.comment.authorName.charAt(0))
        .width(30)
        .height(30)
        .fontSize(13)
        .fontColor('#fff')
        .backgroundColor('#9E86C8')
        .borderRadius(15)
        .textAlign(TextAlign.Center)

      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.comment.authorName).fontSize(13).fontWeight(FontWeight.Medium)
          Text(this.comment.createdAt).fontSize(11).fontColor('#aaa')
        }
        Text(this.comment.text).fontSize(14).lineHeight(20)
        Button(`${this.comment.likeCount}`)
          .fontSize(12)
          .fontColor(this.comment.liked ? '#6750A4' : '#aaa')
          .backgroundColor('transparent')
          .onClick(() => {
            IntentBus.getInstance().publish(makeLikeCommentIntent(this.comment.id) as never);
          })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .padding({ top: 10, bottom: 10 })
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
