// L4 Feature - Reader - CarSurface
// Voice-primary: "Continue listening on phone" + huge TTS play button.

import { ReaderViewModel } from '../viewmodel/ReaderViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeOpenTocSheetIntent } from '../intent/ReaderIntents';
import type { ReaderData } from '../viewmodel/ReaderViewModel';

const BG = '#000000';
const ACCENT = '#7C3AED';
const TEXT_PRIMARY = '#FFFFFF';
const TEXT_DIM = '#9AA3B2';

@Component
export struct ReaderCarSurface {
  @ObjectLink vm: ReaderViewModel;
  @StorageLink('car_lock_active') lockActive: boolean = false;

  private get data(): ReaderData | null {
    const s = this.vm.getState();
    return s.status === 'data' ? s.data : null;
  }

  private get bookTitle(): string {
    return this.data?.book?.title ?? '正在加载…';
  }

  private get chapterTitle(): string {
    const d = this.data;
    if (!d) return '';
    return d.chapters?.[d.currentChapterIdx ?? 0]?.title ?? '';
  }

  private openToc(): void {
    if (this.lockActive) return;
    IntentBus.getInstance().publish(makeOpenTocSheetIntent()).catch(() => {});
  }

  build() {
    Stack() {
      Column({ space: 40 }) {
        Column({ space: 8 }) {
          Text('正在阅读')
            .fontSize(28)
            .fontColor(TEXT_DIM)
          Text(this.bookTitle)
            .fontSize(48)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.chapterTitle)
            .fontSize(32)
            .fontColor(TEXT_DIM)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .width('88%')

        Text('手机端继续阅读，或使用语音控制')
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .textAlign(TextAlign.Center)
          .width('88%')

        Row({ space: 32 }) {
          Button('目录')
            .fontSize(36)
            .fontColor('#000000')
            .width(200)
            .height(120)
            .borderRadius(16)
            .backgroundColor(ACCENT)
            .onClick(() => this.openToc())
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(BG)

      if (this.lockActive) {
        Column() {
          Text('行驶中，请使用语音操控')
            .fontSize(44)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('rgba(0,0,0,0.55)')
        .onClick(() => {})
      }
    }
    .width('100%')
    .height('100%')
  }
}
