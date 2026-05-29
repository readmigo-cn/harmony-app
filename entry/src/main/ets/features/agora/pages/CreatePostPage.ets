// L4 - features/agora - Page
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeCreatePostIntent } from '../intent/AgoraIntents';

@Component
export struct CreatePostPage {
  @State text: string = '';
  @State submitting: boolean = false;

  build() {
    Column({ space: 16 }) {
      Text('发布帖子').fontSize(18).fontWeight(FontWeight.Bold).padding({ top: 16 })

      TextArea({ placeholder: '分享你的读书感想…', text: this.text })
        .height(160)
        .fontSize(15)
        .onChange((val: string) => {
          this.text = val;
        })
        .padding(12)
        .borderRadius(8)
        .backgroundColor('#F5F5F5')

      Button(this.submitting ? '发布中…' : '发布')
        .width('100%')
        .height(48)
        .fontSize(16)
        .enabled(!this.submitting && this.text.trim().length > 0)
        .onClick(() => {
          if (this.text.trim().length === 0) return;
          this.submitting = true;
          IntentBus.getInstance().publish(makeCreatePostIntent(this.text.trim()) as never)
            .finally(() => {
              this.submitting = false;
            });
        })
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor('#fff')
    .alignItems(HorizontalAlign.Start)
  }
}
