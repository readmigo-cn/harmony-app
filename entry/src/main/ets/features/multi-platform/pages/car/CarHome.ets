/**
 * CarHome — 车机听书首页（W16-C1）
 *
 * 极简设计：
 *   - 黑底白字 + brand violet 强调（高对比、低视觉负担）
 *   - 字号 36 sp 起跳（行驶中视觉距离 50cm+）
 *   - 三个大按钮：继续上次 / 最近播放 / 我的书架
 *   - 顶部当前播放状态条；底部全局语音按钮
 *   - 行驶中（car_lock_active=true）整页禁触摸，仅显示文字「行驶中，请使用语音」
 *
 * 操作分发统一走 VoiceCommand.dispatch，与按键 / 语音 / 触摸三入口共享。
 */

import { BrandPalette, GrayPalette } from '../../../../core/theme/AppColors';
import { Spacing, Radius } from '../../../../core/theme/AppSpacing';
import { audioPlayerStore } from '../../../../store/AudioPlayerStore';
import { VoiceCommand } from '../../../../features/multi-platform/service/VoiceCommand';
import { CAR_STORAGE_KEYS } from '../../../../abilities/CarAbility';
import router from '@ohos.router';

@Entry
@Component
struct CarHome {
  /** 行驶锁定状态（车速 > 5km/h 时由 CarAbility.startSpeedMonitor 写入）。 */
  @StorageLink('car_lock_active') lockActive: boolean = false;
  /** 当前车速（km/h），用于状态条显示。 */
  @StorageLink('car_vehicle_speed') vehicleSpeed: number = 0;
  /** 是否正在监听语音。 */
  @StorageLink('car_voice_listening') voiceListening: boolean = false;
  /** 最近一次执行的命令（短暂展示，便于驾驶员快速确认指令已生效）。 */
  @StorageLink('car_last_command') lastCommand: string = '';

  /** 当前播放书名（来自 audioPlayerStore，启动时刷新）。 */
  @State currentBookTitle: string = '';
  /** 是否正在播放，用于状态条按钮形态。 */
  @State isPlaying: boolean = false;

  aboutToAppear(): void {
    audioPlayerStore.subscribe((s) => {
      this.currentBookTitle = s.audiobook?.title ?? '';
      this.isPlaying = s.isPlaying;
    });
    this.currentBookTitle = audioPlayerStore.audiobook?.title ?? '';
    this.isPlaying = audioPlayerStore.isPlaying;
  }

  /** 点击包装：行驶中阻断所有触摸，仅留语音入口。 */
  private guarded(action: () => void): void {
    if (this.lockActive) {
      console.info('[CarHome] touch blocked: lock active');
      return;
    }
    action();
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column({ space: Spacing.xl }) {
        // ---- 顶部状态条 ----
        Row({ space: Spacing.md }) {
          Text(this.lockActive ? '行驶中' : '停车中')
            .fontSize(28)
            .fontColor(this.lockActive ? '#FFD166' : GrayPalette.g300)
          Text(`${Math.round(this.vehicleSpeed)} km/h`)
            .fontSize(28)
            .fontColor(GrayPalette.g300)
          Blank()
          Text(this.voiceListening ? '语音聆听中' : '语音待命')
            .fontSize(28)
            .fontColor(this.voiceListening ? BrandPalette.b400 : GrayPalette.g500)
        }
        .width('100%')
        .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.lg, bottom: Spacing.md })

        // ---- 当前播放卡片 ----
        if (this.currentBookTitle) {
          Column({ space: Spacing.sm }) {
            Text('正在播放')
              .fontSize(28)
              .fontColor(GrayPalette.g400)
            Text(this.currentBookTitle)
              .fontSize(40)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('92%')
          .alignItems(HorizontalAlign.Start)
          .padding(Spacing.lg)
          .backgroundColor('#1A1A1F')
          .borderRadius(Radius.lg)
        }

        // ---- 三大按钮 ----
        Column({ space: Spacing.lg }) {
          this.bigButton('继续上次', BrandPalette.b400, () => {
            this.guarded(() => {
              VoiceCommand.getInstance().dispatch('play');
              router.pushUrl({ url: 'pages/car/CarPlayer' }).catch(() => {});
            });
          })
          this.bigButton('最近播放', GrayPalette.g700, () => {
            this.guarded(() => {
              // 占位：跳到最近播放列表（W16-C2 完成）
              console.info('[CarHome] open recent (TODO)');
            });
          })
          this.bigButton('我的书架', GrayPalette.g700, () => {
            this.guarded(() => {
              console.info('[CarHome] open library (TODO)');
            });
          })
        }
        .width('92%')

        Blank()

        // ---- 底部全局语音按钮 ----
        Button() {
          Text(this.voiceListening ? '聆听中…' : '按下说话')
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#000000')
        }
        .width(220)
        .height(220)
        .borderRadius(110)
        .backgroundColor(BrandPalette.b400)
        .margin({ bottom: Spacing.xl })
        .onClick(() => {
          // 触发语音监听（占位：交由 VoiceCommand 内部 intent 框架处理）
          AppStorage.SetOrCreate<boolean>(CAR_STORAGE_KEYS.VOICE_LISTENING, true);
        })

        if (this.lastCommand) {
          Text(`已执行：${this.lastCommand}`)
            .fontSize(24)
            .fontColor(GrayPalette.g500)
            .margin({ bottom: Spacing.lg })
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#000000')

      // ---- 行驶锁定遮罩：半透明覆盖，吃掉所有触摸事件 ----
      if (this.lockActive) {
        Column() {
          Text('行驶中，请使用语音操控')
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

  /** 大按钮 builder：高度 120 vp，全宽，圆角，36sp。 */
  @Builder
  bigButton(label: string, bg: string, handler: () => void) {
    Button() {
      Text(label)
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
    }
    .width('100%')
    .height(120)
    .borderRadius(Radius.lg)
    .backgroundColor(bg)
    .onClick(handler)
  }
}
