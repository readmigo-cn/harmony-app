/**
 * CarPlayer — 车机听书播放页（W16-C1）
 *
 * 极简：书名 + 章节 + 进度 + 大按钮（播放/暂停/上一章/下一章）
 * 不展示任何文字段落（只听不读）
 * 倒计时关闭：睡眠定时（15 / 30 / 60 / 章末）
 *
 * 行驶中（car_lock_active=true）：所有触控按钮被遮罩吃掉，仅语音 / 方向盘按键可控制
 */

import { BrandPalette, GrayPalette } from '../../../../core/theme/AppColors';
import { Spacing, Radius } from '../../../../core/theme/AppSpacing';
import { audioPlayerStore } from '../../../../store/AudioPlayerStore';
import { VoiceCommand } from '../../../../features/multi-platform/service/VoiceCommand';

@Entry
@Component
struct CarPlayer {
  @StorageLink('car_lock_active') lockActive: boolean = false;

  @State bookTitle: string = '';
  @State chapterTitle: string = '';
  @State progressPct: number = 0;
  @State remainingText: string = '--:--';
  @State isPlaying: boolean = false;
  /** 当前睡眠定时选项（null / 15 / 30 / 60 / 'end_of_chapter'） */
  @State sleepLabel: string = '关闭';

  aboutToAppear(): void {
    audioPlayerStore.subscribe((s) => {
      this.bookTitle = s.audiobook?.title ?? '未选择书籍';
      this.chapterTitle = s.currentChapter?.title ?? '';
      this.progressPct = s.getProgress();
      this.remainingText = s.formatTime(s.getRemainingTime());
      this.isPlaying = s.isPlaying;
      this.sleepLabel = this.formatSleep(s.sleepTimer);
    });
    // 首次刷新
    this.bookTitle = audioPlayerStore.audiobook?.title ?? '未选择书籍';
    this.chapterTitle = audioPlayerStore.currentChapter?.title ?? '';
    this.progressPct = audioPlayerStore.getProgress();
    this.remainingText = audioPlayerStore.formatTime(audioPlayerStore.getRemainingTime());
    this.isPlaying = audioPlayerStore.isPlaying;
  }

  private formatSleep(opt: number | string | null): string {
    if (opt === null || opt === undefined) return '关闭';
    if (opt === 'end_of_chapter') return '本章结束';
    return `${opt} 分钟`;
  }

  private guarded(action: () => void): void {
    if (this.lockActive) return;
    action();
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column({ space: Spacing.xl }) {
        // ---- 书名 + 章节 ----
        Column({ space: Spacing.md }) {
          Text(this.bookTitle)
            .fontSize(44)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.chapterTitle)
            .fontSize(32)
            .fontColor(GrayPalette.g300)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('92%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: Spacing.xl })

        // ---- 进度条 + 剩余时间 ----
        Column({ space: Spacing.sm }) {
          Progress({ value: this.progressPct, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(12)
            .color(BrandPalette.b400)
            .backgroundColor(GrayPalette.g700)
          Row() {
            Text(`剩余 ${this.remainingText}`)
              .fontSize(28)
              .fontColor(GrayPalette.g400)
            Blank()
            Text(`睡眠：${this.sleepLabel}`)
              .fontSize(28)
              .fontColor(this.sleepLabel === '关闭' ? GrayPalette.g500 : BrandPalette.b400)
          }
          .width('100%')
        }
        .width('92%')

        Blank()

        // ---- 三大控制按钮 ----
        Row({ space: Spacing.xl }) {
          this.controlBtn('上一章', GrayPalette.g700, () => this.guarded(() => VoiceCommand.getInstance().dispatch('prev_chapter')))
          this.controlBtn(this.isPlaying ? '暂停' : '播放', BrandPalette.b400, () => {
            this.guarded(() => VoiceCommand.getInstance().dispatch(this.isPlaying ? 'pause' : 'play'));
          })
          this.controlBtn('下一章', GrayPalette.g700, () => this.guarded(() => VoiceCommand.getInstance().dispatch('next_chapter')))
        }
        .margin({ bottom: Spacing.xl })

        // ---- 睡眠定时（倒计时关闭）按钮组 ----
        Row({ space: Spacing.md }) {
          this.sleepBtn('关闭', null)
          this.sleepBtn('15 分钟', 15)
          this.sleepBtn('30 分钟', 30)
          this.sleepBtn('60 分钟', 60)
          this.sleepBtn('本章末', 'end_of_chapter')
        }
        .margin({ bottom: Spacing.xl })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#000000')

      // ---- 行驶锁定遮罩 ----
      if (this.lockActive) {
        Column() {
          Text('行驶中，请使用语音')
            .fontSize(44)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('rgba(0,0,0,0.55)')
        .onClick(() => { /* 吃掉点击 */ })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  controlBtn(label: string, bg: string, handler: () => void) {
    Button() {
      Text(label)
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
    }
    .width(180)
    .height(180)
    .borderRadius(90)
    .backgroundColor(bg)
    .onClick(handler)
  }

  @Builder
  sleepBtn(label: string, opt: number | string | null) {
    Button() {
      Text(label)
        .fontSize(28)
        .fontColor('#FFFFFF')
    }
    .height(72)
    .padding({ left: Spacing.lg, right: Spacing.lg })
    .borderRadius(Radius.md)
    .backgroundColor(this.sleepLabel === this.formatSleep(opt) ? BrandPalette.b400 : GrayPalette.g700)
    .onClick(() => {
      this.guarded(() => {
        // SleepTimerOption 类型为 15|30|60|'end_of_chapter'|null
        audioPlayerStore.setSleepTimer(opt as 15 | 30 | 60 | 'end_of_chapter' | null);
      });
    })
  }
}
