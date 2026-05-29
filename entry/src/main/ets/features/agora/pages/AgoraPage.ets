// L4 - features/agora - Page
import { AgoraPostCard } from '../components/AgoraPostCard';
import type { AgoraPost } from '../viewmodel/AgoraViewModel';

@Component
export struct AgoraPage {
  @State posts: AgoraPost[] = [];
  @State status: string = 'idle';

  build() {
    Column() {
      if (this.status === 'loading') {
        Text('加载中…').fontSize(14).fontColor('#888').margin({ top: 40 })
      } else if (this.status === 'error') {
        Text('加载失败，请重试').fontSize(14).fontColor('#f00').margin({ top: 40 })
      } else {
        List({ space: 12 }) {
          ForEach(this.posts, (post: AgoraPost) => {
            ListItem() {
              AgoraPostCard({ post })
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
    .backgroundColor('#F5F5F5')
  }
}
