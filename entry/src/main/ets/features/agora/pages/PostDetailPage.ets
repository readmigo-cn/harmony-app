// L4 - features/agora - Page
import { CommentRow } from '../components/CommentRow';
import type { AgoraPost, AgoraComment } from '../viewmodel/AgoraViewModel';

@Component
export struct PostDetailPage {
  @Prop post: AgoraPost | undefined = undefined;
  @State comments: AgoraComment[] = [];
  @State status: string = 'idle';

  build() {
    Column() {
      if (!this.post) {
        Text('帖子不存在').fontSize(14).fontColor('#888').margin({ top: 40 })
      } else {
        Column({ space: 8 }) {
          Text(this.post.text).fontSize(15).lineHeight(22).padding(16)
          Text(`${this.post.likeCount} 赞 · ${this.post.commentCount} 评论`)
            .fontSize(13)
            .fontColor('#888')
            .padding({ left: 16 })

          if (this.status === 'loading') {
            Text('加载评论…').fontSize(13).fontColor('#aaa').margin({ top: 12 })
          } else {
            List() {
              ForEach(this.comments, (c: AgoraComment) => {
                ListItem() {
                  CommentRow({ comment: c })
                }
              })
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 16, right: 16 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#fff')
  }
}
