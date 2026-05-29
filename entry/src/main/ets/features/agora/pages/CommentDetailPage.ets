// L4 - features/agora - Page
import { CommentRow } from '../components/CommentRow';
import type { AgoraComment } from '../viewmodel/AgoraViewModel';

@Component
export struct CommentDetailPage {
  @Prop comments: AgoraComment[] = [];
  @Prop postId: string = '';
  @State status: string = 'idle';

  build() {
    Column() {
      Text('评论').fontSize(18).fontWeight(FontWeight.Bold).padding(16)

      if (this.status === 'loading') {
        Text('加载中…').fontSize(14).fontColor('#aaa').margin({ top: 20 })
      } else if (this.comments.length === 0) {
        Text('暂无评论').fontSize(14).fontColor('#aaa').margin({ top: 20 })
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
    .height('100%')
    .backgroundColor('#fff')
    .alignItems(HorizontalAlign.Start)
  }
}
