// L4 Feature - Reader - WatchSurface
// Single-card layout: progress dot + chapter title + tap-to-next-chapter.

import { ReaderViewModel } from '../viewmodel/ReaderViewModel';
import { IntentBus } from '../../../core/intent/IntentBus';
import { makeJumpToChapterIntent } from '../intent/ReaderIntents';
import type { ReaderData } from '../viewmodel/ReaderViewModel';

const BG = '#0B0F1A';
const ACCENT = '#E76F1A';
const TEXT_PRIMARY = '#FFFFFF';
const TEXT_SECONDARY = '#9AA3B2';
const RING_TRACK = '#1F2532';

@Component
export struct ReaderWatchSurface {
  @ObjectLink vm: ReaderViewModel;

  private get data(): ReaderData | null {
    const s = this.vm.getState();
    return s.status === 'data' ? s.data : null;
  }

  private get chapterTitle(): string {
    const d = this.data;
    if (!d) return '';
    return d.chapters?.[d.currentChapterIdx ?? 0]?.title ?? '';
  }

  private get progressPct(): number {
    const d = this.data;
    if (!d || !d.chapters?.length) return 0;
    return ((d.currentChapterIdx ?? 0) + 1) / d.chapters.length;
  }

  private nextChapter(): void {
    const d = this.data;
    if (!d?.chapters) return;
    const next = (d.currentChapterIdx ?? 0) + 1;
    if (next < d.chapters.length) {
      const ch = d.chapters[next];
      IntentBus.getInstance().publish(makeJumpToChapterIntent(ch.id)).catch(() => {});
    }
  }

  build() {
    Stack() {
      Column({ space: 16 }) {
        Progress({
          value: Math.round(this.progressPct * 100),
          total: 100,
          type: ProgressType.Ring,
        })
          .width(160)
          .height(160)
          .color(ACCENT)
          .style({ strokeWidth: 10, scaleCount: 0, scaleWidth: 0 })

        Text(this.chapterTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width(200)

        Text(`${Math.round(this.progressPct * 100)}%`)
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)

        Button('下一章')
          .fontSize(16)
          .fontColor('#000000')
          .width(120)
          .height(56)
          .borderRadius(28)
          .backgroundColor(ACCENT)
          .onClick(() => this.nextChapter())
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
