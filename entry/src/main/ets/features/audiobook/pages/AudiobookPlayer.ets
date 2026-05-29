// L4 Feature - Audiobook - Player page
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { AudiobookPlayerParams } from '../../../core/router/RouteConstants';
import { RouterService } from '../../../core/router/RouterService';
import { IntentBus } from '../../../core/intent/IntentBus';
import { AudiobookViewModel } from '../viewmodel/AudiobookViewModel';
import { audioPlayerStore } from '../../../store/AudioPlayerStore';
import {
  makePlayAudiobookIntent,
  makePauseAudiobookIntent,
  makeSetSpeedIntent,
  makeSetSleepTimerIntent,
  makeSetVoiceIntent,
} from '../intent/AudiobookIntents';
import type { PlaybackSpeed, SleepTimerOption } from '../../../model/Audiobook';
import { PLAYBACK_SPEEDS, SLEEP_TIMER_OPTIONS } from '../../../model/Audiobook';
import type { Voice } from '../service/TtsService';

// Speed labels aligned with the PLAYBACK_SPEEDS array in Audiobook.ets
const SPEED_LABELS: string[] = ['0.5x', '0.75x', '1x', '1.25x', '1.5x', '1.75x', '2x', '2.5x', '3x'];

@Component
export struct AudiobookPlayer {
  @Prop params: AudiobookPlayerParams;

  // Reactive local state bound to audioPlayerStore via subscribe()
  @State playing: boolean = false;
  @State currentTime: number = 0;
  @State duration: number = 0;
  @State speed: PlaybackSpeed = 1.0;
  @State sleepTimer: SleepTimerOption | null = null;
  @State selectedVoiceId: string = '';
  @State availableVoices: Voice[] = [];
  @State isLoading: boolean = false;

  // Sheet visibility
  @State showSpeedSheet: boolean = false;
  @State showSleepSheet: boolean = false;
  @State showVoiceSheet: boolean = false;

  private vm: AudiobookViewModel = new AudiobookViewModel();
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    this.vm.loadVoices();

    // Subscribe to store changes and mirror into @State fields for ArkUI rebuild
    this.unsubscribe = audioPlayerStore.subscribe(() => {
      this.playing = audioPlayerStore.isPlaying;
      this.currentTime = audioPlayerStore.currentTime;
      this.duration = audioPlayerStore.duration;
      this.speed = audioPlayerStore.playbackSpeed;
      this.sleepTimer = audioPlayerStore.sleepTimer;
      this.selectedVoiceId = audioPlayerStore.selectedVoiceId;
      this.availableVoices = audioPlayerStore.availableVoices;
      this.isLoading = audioPlayerStore.isLoading;
    });
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = null;
    this.vm.onDestroy();
  }

  private formatTime(seconds: number): string {
    return audioPlayerStore.formatTime(seconds);
  }

  private onPlayPause(): void {
    const bus = IntentBus.getInstance();
    const bookId = this.params?.audiobookId ?? '';
    if (this.playing) {
      bus.publish(makePauseAudiobookIntent());
    } else {
      bus.publish(makePlayAudiobookIntent(bookId));
    }
  }

  private onSeekForward(): void {
    audioPlayerStore.seekForward(15);
  }

  private onSeekBackward(): void {
    audioPlayerStore.seekBackward(15);
  }

  private onSliderChange(value: number): void {
    // value is 0-100 progress
    const posMs = (value / 100) * this.duration * 1000;
    audioPlayerStore.seek(posMs);
  }

  private onSelectSpeed(speed: PlaybackSpeed): void {
    IntentBus.getInstance().publish(makeSetSpeedIntent(speed));
    this.showSpeedSheet = false;
  }

  private onSelectSleepTimer(option: SleepTimerOption | null): void {
    IntentBus.getInstance().publish(makeSetSleepTimerIntent(option));
    this.showSleepSheet = false;
  }

  private onSelectVoice(voiceId: string): void {
    IntentBus.getInstance().publish(makeSetVoiceIntent(voiceId));
    this.showVoiceSheet = false;
  }

  private sleepTimerLabel(): string {
    if (this.sleepTimer === null) return '关闭';
    if (this.sleepTimer === 'end_of_chapter') return '本章结束';
    return `${this.sleepTimer}分钟`;
  }

  private currentVoiceName(): string {
    const v = this.availableVoices.find((voice) => voice.id === this.selectedVoiceId);
    return v?.name ?? '默认';
  }

  @Builder
  SpeedSheet() {
    Column({ space: AppSpacing.sm }) {
      Text('播放速度')
        .fontSize(AppFontSize.md)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .padding({ top: AppSpacing.base, bottom: AppSpacing.sm })

      ForEach(PLAYBACK_SPEEDS, (s: PlaybackSpeed, idx: number) => {
        Row() {
          Text(SPEED_LABELS[idx] ?? `${s}x`)
            .fontSize(AppFontSize.md)
            .fontColor(s === this.speed ? AppColors.brand : AppColors.textPrimary)
            .fontWeight(s === this.speed ? AppFontWeight.bold : AppFontWeight.normal)
        }
        .width('100%')
        .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm, left: AppSpacing.base })
        .onClick(() => this.onSelectSpeed(s))
      })
    }
    .width('100%')
    .padding({ bottom: AppSpacing.xl })
    .backgroundColor(AppColors.bgSecondary)
  }

  @Builder
  SleepSheet() {
    Column({ space: AppSpacing.sm }) {
      Text('睡眠定时')
        .fontSize(AppFontSize.md)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .padding({ top: AppSpacing.base, bottom: AppSpacing.sm })

      Row() {
        Text('关闭')
          .fontSize(AppFontSize.md)
          .fontColor(this.sleepTimer === null ? AppColors.brand : AppColors.textPrimary)
      }
      .width('100%')
      .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm, left: AppSpacing.base })
      .onClick(() => this.onSelectSleepTimer(null))

      ForEach(SLEEP_TIMER_OPTIONS, (item: { label: string; value: SleepTimerOption }) => {
        Row() {
          Text(item.label)
            .fontSize(AppFontSize.md)
            .fontColor(this.sleepTimer === item.value ? AppColors.brand : AppColors.textPrimary)
        }
        .width('100%')
        .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm, left: AppSpacing.base })
        .onClick(() => this.onSelectSleepTimer(item.value))
      })
    }
    .width('100%')
    .padding({ bottom: AppSpacing.xl })
    .backgroundColor(AppColors.bgSecondary)
  }

  @Builder
  VoiceSheet() {
    Column({ space: AppSpacing.sm }) {
      Text('音色选择')
        .fontSize(AppFontSize.md)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .padding({ top: AppSpacing.base, bottom: AppSpacing.sm })

      if (this.availableVoices.length === 0) {
        Text('暂无可用音色')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textTertiary)
          .padding(AppSpacing.base)
      } else {
        ForEach(this.availableVoices, (voice: Voice) => {
          Row() {
            Text(voice.name)
              .fontSize(AppFontSize.md)
              .fontColor(voice.id === this.selectedVoiceId ? AppColors.brand : AppColors.textPrimary)
          }
          .width('100%')
          .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm, left: AppSpacing.base })
          .onClick(() => this.onSelectVoice(voice.id))
        })
      }
    }
    .width('100%')
    .padding({ bottom: AppSpacing.xl })
    .backgroundColor(AppColors.bgSecondary)
  }

  build() {
    NavDestination() {
      Column({ space: AppSpacing.xl }) {
        // Header
        Row() {
          Text('< ')
            .fontSize(AppFontSize.md)
            .fontColor(AppColors.brand)
            .onClick(() => RouterService.pop())
          Text($r('app.string.audiobook_title'))
            .fontSize(AppFontSize.md)
            .fontColor(AppColors.textInverse)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          // Placeholder for symmetry
          Text('  ')
            .fontSize(AppFontSize.md)
        }
        .width('100%')
        .padding(AppSpacing.base)

        // Book ID (temporary placeholder until catalog integration)
        Text(`ID: ${this.params?.audiobookId ?? ''}`)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textTertiary)

        // Progress bar
        Column({ space: 4 }) {
          Slider({
            value: this.duration > 0 ? (this.currentTime / this.duration) * 100 : 0,
            min: 0,
            max: 100,
            step: 0.1,
            style: SliderStyle.OutSet,
          })
            .width('90%')
            .trackThickness(4)
            .selectedColor(AppColors.brand)
            .onChange((value: number) => this.onSliderChange(value))

          Row() {
            Text(this.formatTime(this.currentTime))
              .fontSize(AppFontSize.xs)
              .fontColor(AppColors.textTertiary)
            Blank()
            Text(this.formatTime(this.duration))
              .fontSize(AppFontSize.xs)
              .fontColor(AppColors.textTertiary)
          }
          .width('90%')
        }

        // Playback controls
        Row({ space: AppSpacing.xl }) {
          // Skip backward 15s
          Button('-15s')
            .fontSize(AppFontSize.sm)
            .backgroundColor(AppColors.bgSecondary)
            .fontColor(AppColors.textPrimary)
            .width(72)
            .height(40)
            .onClick(() => this.onSeekBackward())

          // Play/Pause
          if (this.isLoading) {
            LoadingProgress()
              .width(56)
              .height(56)
              .color(AppColors.brand)
          } else {
            Button(this.playing
              ? $r('app.string.audiobook_pause')
              : $r('app.string.audiobook_play'))
              .width(80)
              .height(56)
              .backgroundColor(AppColors.brand)
              .onClick(() => this.onPlayPause())
          }

          // Skip forward 15s
          Button('+15s')
            .fontSize(AppFontSize.sm)
            .backgroundColor(AppColors.bgSecondary)
            .fontColor(AppColors.textPrimary)
            .width(72)
            .height(40)
            .onClick(() => this.onSeekForward())
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')

        // Settings row: speed | sleep | voice
        Row({ space: AppSpacing.base }) {
          Button(`速度 ${this.speed}x`)
            .fontSize(AppFontSize.sm)
            .backgroundColor(AppColors.bgSecondary)
            .fontColor(AppColors.textPrimary)
            .height(36)
            .onClick(() => { this.showSpeedSheet = true; })

          Button(`定时: ${this.sleepTimerLabel()}`)
            .fontSize(AppFontSize.sm)
            .backgroundColor(AppColors.bgSecondary)
            .fontColor(AppColors.textPrimary)
            .height(36)
            .onClick(() => { this.showSleepSheet = true; })

          Button(`音色: ${this.currentVoiceName()}`)
            .fontSize(AppFontSize.sm)
            .backgroundColor(AppColors.bgSecondary)
            .fontColor(AppColors.textPrimary)
            .height(36)
            .onClick(() => { this.showVoiceSheet = true; })
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .padding({ left: AppSpacing.base, right: AppSpacing.base })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#0F0F1A')
      .bindSheet($$this.showSpeedSheet, this.SpeedSheet(), {
        height: SheetSize.FIT_CONTENT,
        showClose: true,
        title: { title: '播放速度' },
      })
      .bindSheet($$this.showSleepSheet, this.SleepSheet(), {
        height: SheetSize.FIT_CONTENT,
        showClose: true,
        title: { title: '睡眠定时' },
      })
      .bindSheet($$this.showVoiceSheet, this.VoiceSheet(), {
        height: SheetSize.FIT_CONTENT,
        showClose: true,
        title: { title: '音色选择' },
      })
    }
    .hideTitleBar(true)
  }
}
