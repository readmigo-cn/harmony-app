/**
 * SmartScreenAudiobook.ets — W15-C3 智慧屏听书播放
 *
 * 视觉布局（横屏）：
 *   ┌──────────────────────────┬───────────────────────────────┐
 *   │                          │  书名 (48vp)                   │
 *   │   书封大图 (560×800)     │  作者 (32vp)                   │
 *   │   带阴影 + 圆角          │  章节信息 (28vp)               │
 *   │                          │                               │
 *   │   下方：waveform 动画    │  当前句字幕 (40vp 高对比)      │
 *   │   (8 根条形上下跳动)     │                               │
 *   │                          │  ━━━━━━━━━━━━━━━━━ 进度条       │
 *   │                          │  03:24 / 12:08               │
 *   │                          │                               │
 *   │                          │  ⏮  -15s  ▶/❚❚  +15s  ⏭        │
 *   │                          │  速度: 1.0x  (DPAD UP/DOWN)   │
 *   └──────────────────────────┴───────────────────────────────┘
 *
 * 遥控器键位：
 *   - LEFT  → -15s        RIGHT → +15s
 *   - UP    → 速度档 +1   DOWN  → 速度档 -1（0.5/0.75/1.0/1.25/1.5/2.0）
 *   - SELECT/PLAY_PAUSE → 暂停 / 继续
 *   - MENU  → 章节列表（占位 toast）
 *   - CHANNEL_UP / CHANNEL_DOWN → 上一章 / 下一章
 *   - BACK  → router.back
 *
 * 字幕：
 *   - 跟随 TTS 当前句（占位用 demo 字幕轮播 4s 一句）
 *   - 高度固定 160vp，避免布局抖动
 */

import { AppColors } from '../../../../core/theme/AppColors';
import { Spacing, Radius } from '../../../../core/theme/AppSpacing';
import { RemoteController } from '../../../../features/multi-platform/service/RemoteController';
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';

const SPEEDS = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
const DEFAULT_SPEED_IDX = 2;

const DEMO_SUBTITLES: string[] = [
  'It is a truth universally acknowledged,',
  'that a single man in possession of a good fortune,',
  'must be in want of a wife.',
  'However little known the feelings or views of such a man may be on his first entering a neighbourhood,',
  'this truth is so well fixed in the minds of the surrounding families,',
  'that he is considered the rightful property of some one or other of their daughters.',
];

@Entry
@Component
struct SmartScreenAudiobook {
  @State playing: boolean = true;
  @State speedIdx: number = DEFAULT_SPEED_IDX;
  @State currentSec: number = 204; // 3:24
  @State totalSec: number = 728;   // 12:08
  @State subtitleIdx: number = 0;
  @State waveBars: number[] = [40, 70, 30, 90, 55, 75, 45, 60];
  @State focusedBtn: string = 'play';
  @StorageLink('audio_current_id') audiobookId: string = '';

  private waveTimerId: number = -1;
  private subtitleTimerId: number = -1;
  private playTimerId: number = -1;
  private unlistenRemote: (() => void) | null = null;

  aboutToAppear(): void {
    this.unlistenRemote = RemoteController.listen((key) => {
      switch (key) {
        case 'LEFT':         this.seek(-15);          return true;
        case 'RIGHT':        this.seek(+15);          return true;
        case 'UP':           this.bumpSpeed(+1);      return true;
        case 'DOWN':         this.bumpSpeed(-1);      return true;
        case 'SELECT':
        case 'PLAY_PAUSE':   this.togglePlay();       return true;
        case 'CHANNEL_UP':   this.changeChapter(+1);  return true;
        case 'CHANNEL_DOWN': this.changeChapter(-1);  return true;
        case 'MENU':
          promptAction.showToast({ message: '章节列表（占位）' });
          return true;
        case 'BACK':
          router.back();
          return true;
        default:
          return false;
      }
    });
    this.startWaveAnim();
    this.startSubtitleRotate();
    this.startPlayClock();
  }

  aboutToDisappear(): void {
    if (this.unlistenRemote) this.unlistenRemote();
    if (this.waveTimerId !== -1)     clearInterval(this.waveTimerId);
    if (this.subtitleTimerId !== -1) clearInterval(this.subtitleTimerId);
    if (this.playTimerId !== -1)     clearInterval(this.playTimerId);
  }

  private togglePlay(): void {
    this.playing = !this.playing;
    promptAction.showToast({ message: this.playing ? '播放' : '暂停' });
  }

  private seek(deltaSec: number): void {
    this.currentSec = Math.max(0, Math.min(this.totalSec, this.currentSec + deltaSec));
  }

  private bumpSpeed(delta: number): void {
    const next = Math.max(0, Math.min(SPEEDS.length - 1, this.speedIdx + delta));
    if (next !== this.speedIdx) {
      this.speedIdx = next;
      promptAction.showToast({ message: `速度 ${SPEEDS[next].toFixed(2)}x` });
    }
  }

  private changeChapter(delta: number): void {
    promptAction.showToast({ message: delta > 0 ? '下一章' : '上一章' });
    this.currentSec = 0;
  }

  private startWaveAnim(): void {
    this.waveTimerId = setInterval(() => {
      if (!this.playing) return;
      this.waveBars = this.waveBars.map(() => 20 + Math.floor(Math.random() * 80));
    }, 120);
  }

  private startSubtitleRotate(): void {
    this.subtitleTimerId = setInterval(() => {
      if (!this.playing) return;
      this.subtitleIdx = (this.subtitleIdx + 1) % DEMO_SUBTITLES.length;
    }, 4000);
  }

  private startPlayClock(): void {
    this.playTimerId = setInterval(() => {
      if (!this.playing) return;
      const step = SPEEDS[this.speedIdx];
      this.currentSec = Math.min(this.totalSec, this.currentSec + step);
    }, 1000);
  }

  private fmtTime(sec: number): string {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  }

  @Builder
  ControlButton(key: string, label: string, big: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Column().width('100%').height('100%').backgroundColor(
        this.focusedBtn === key ? AppColors.brand : AppColors.bgSecondary
      ).borderRadius(big ? 64 : 48)
      Text(label)
        .fontSize(big ? 56 : 36)
        .fontColor(this.focusedBtn === key ? '#FFFFFF' : AppColors.textPrimary)
        .fontWeight(FontWeight.Bold)
    }
    .width(big ? 128 : 96)
    .height(big ? 128 : 96)
    .scale(this.focusedBtn === key ? { x: 1.05, y: 1.05 } : { x: 1, y: 1 })
    .borderWidth(this.focusedBtn === key ? 4 : 0)
    .borderColor('#FFFFFF')
    .borderRadius(big ? 64 : 48)
    .animation({ duration: 180, curve: Curve.EaseOut })
    .focusable(true)
    .defaultFocus(key === 'play')
    .onFocus(() => { this.focusedBtn = key; })
    .onBlur(() => { if (this.focusedBtn === key) this.focusedBtn = ''; })
  }

  build() {
    Row() {
      // ── 左侧：书封 + waveform (560宽) ──
      Column({ space: Spacing.s8 }) {
        // 书封
        Stack({ alignContent: Alignment.Center }) {
          Column().width('100%').height('100%')
            .backgroundColor('#7C3AED')
            .borderRadius(Radius.xl)
          Text('傲慢与偏见')
            .fontSize(48)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(560)
        .height(800)
        .shadow({ radius: 32, color: '#00000099', offsetY: 16 })

        // Waveform
        Row({ space: 12 }) {
          ForEach(this.waveBars, (h: number, idx: number) => {
            Column()
              .width(28)
              .height(h)
              .backgroundColor(AppColors.brand)
              .borderRadius(8)
              .animation({ duration: 120, curve: Curve.EaseInOut })
          }, (_h: number, idx: number) => `bar-${idx}`)
        }
        .height(100)
        .alignItems(VerticalAlign.Center)
      }
      .width(640)
      .height('100%')
      .padding(40)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)

      // ── 右侧：信息 + 控制 ──
      Column({ space: Spacing.s5 }) {
        Text('傲慢与偏见')
          .fontSize(56)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
        Text('Jane Austen · 演播：李野默')
          .fontSize(28)
          .fontColor(AppColors.textSecondary)
        Text('第 3 章 / 共 61 章')
          .fontSize(24)
          .fontColor(AppColors.textSecondary)

        Blank().height(20)

        // 字幕区
        Column() {
          Text(DEMO_SUBTITLES[this.subtitleIdx])
            .fontSize(40)
            .fontColor('#F5F5F7')
            .lineHeight(56)
            .textAlign(TextAlign.Start)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(180)
        .padding(Spacing.s6)
        .backgroundColor('#1F2030')
        .borderRadius(Radius.lg)

        // 进度条
        Column({ space: Spacing.s2 }) {
          Progress({
            value: this.currentSec,
            total: this.totalSec,
            type: ProgressType.Linear,
          })
            .color(AppColors.brand)
            .backgroundColor('#3A3B4A')
            .style({ strokeWidth: 8 })
            .width('100%')
          Row() {
            Text(this.fmtTime(this.currentSec))
              .fontSize(24).fontColor(AppColors.textSecondary)
            Blank()
            Text(this.fmtTime(this.totalSec))
              .fontSize(24).fontColor(AppColors.textSecondary)
          }
          .width('100%')
        }

        Blank().height(16)

        // 控制按钮
        Row({ space: Spacing.s5 }) {
          this.ControlButton('prev',  '⏮',  false)
          this.ControlButton('back',  '-15', false)
          this.ControlButton('play',  this.playing ? '❚❚' : '▶', true)
          this.ControlButton('fwd',   '+15', false)
          this.ControlButton('next',  '⏭',  false)
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width('100%')

        Text(`速度 ${SPEEDS[this.speedIdx].toFixed(2)}x   (↑/↓ 调速)`)
          .fontSize(22)
          .fontColor(AppColors.textSecondary)
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .layoutWeight(1)
      .height('100%')
      .padding({ left: 60, right: 80, top: 80, bottom: 60 })
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0F1018')
  }
}
