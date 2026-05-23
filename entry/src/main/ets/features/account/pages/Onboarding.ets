import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import { RoutePath } from '../../../core/router/RouteConstants';
import { UserStore } from '../../../store/UserStore';

/**
 * Onboarding —— 三页 Swiper（W4-C4）。
 * P1: 欢迎介绍
 * P2: CEFR 英语水平选择 (A1–C2)
 * P3: 阅读兴趣多选（文学经典/科幻/历史/商业/学术…）
 *
 * Skip / 开始：根据登录状态分流到 Login 或 Main。
 * 选择写入 UserStore.setProfile（cefr） + AppStorage('onboarding_interests')。
 */

const CEFR_LEVELS: string[] = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
const INTERESTS: string[] = ['文学经典', '科幻', '历史', '商业', '学术', '心理', '传记', '童书'];

const KEY_INTERESTS = 'onboarding_interests';

@Component
export struct Onboarding {
  @State pageIndex: number = 0;
  @State cefr: string = 'B1';
  @State interests: string[] = [];
  private controller: SwiperController = new SwiperController();

  private goNext(): void {
    if (this.pageIndex < 2) {
      this.controller.showNext();
    } else {
      this.finish();
    }
  }

  private finish(): void {
    const prev = UserStore.getProfile();
    UserStore.setProfile({
      id: prev?.id ?? '',
      phone: prev?.phone,
      nickname: prev?.nickname ?? '',
      avatarUrl: prev?.avatarUrl,
      cefr: this.cefr,
    });
    AppStorage.SetOrCreate<string[]>(KEY_INTERESTS, this.interests);
    if (UserStore.isLoggedIn()) {
      RouterService.replace(RoutePath.MAIN);
    } else {
      RouterService.replace(RoutePath.LOGIN);
    }
  }

  private toggleInterest(tag: string): void {
    const idx = this.interests.indexOf(tag);
    if (idx >= 0) {
      this.interests = this.interests.filter((t: string) => t !== tag);
    } else {
      this.interests = [...this.interests, tag];
    }
  }

  @Builder
  PageWelcome() {
    Column({ space: AppSpacing.lg }) {
      Text($r('app.string.onboarding_welcome'))
        .fontSize(AppFontSize.title)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)

      Text($r('app.string.onboarding_subtitle'))
        .fontSize(AppFontSize.md)
        .fontColor(AppColors.textSecondary)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(AppSpacing.lg)
  }

  @Builder
  PageLevel() {
    Column({ space: AppSpacing.lg }) {
      Text('选择你的英语水平')
        .fontSize(AppFontSize.xl)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)

      Text('CEFR 等级，可在「我的」中随时修改')
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textSecondary)

      Grid() {
        ForEach(CEFR_LEVELS, (lv: string) => {
          GridItem() {
            Text(lv)
              .fontSize(AppFontSize.lg)
              .fontWeight(this.cefr === lv ? AppFontWeight.bold : AppFontWeight.regular)
              .fontColor(this.cefr === lv ? AppColors.textInverse : AppColors.textPrimary)
              .backgroundColor(this.cefr === lv ? AppColors.brand : AppColors.bgSecondary)
              .borderRadius(AppRadius.base)
              .padding(AppSpacing.base)
              .textAlign(TextAlign.Center)
              .width('100%')
              .onClick(() => { this.cefr = lv; });
          }
        }, (lv: string) => lv);
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(AppSpacing.sm)
      .rowsGap(AppSpacing.sm)
      .height(200)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(AppSpacing.lg)
  }

  @Builder
  PageInterests() {
    Column({ space: AppSpacing.lg }) {
      Text('选择你感兴趣的题材')
        .fontSize(AppFontSize.xl)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)

      Text('多选，影响推荐与发现页')
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textSecondary)

      Flex({ wrap: FlexWrap.Wrap, space: { main: { value: AppSpacing.sm, unit: 1 }, cross: { value: AppSpacing.sm, unit: 1 } } }) {
        ForEach(INTERESTS, (tag: string) => {
          Text(tag)
            .fontSize(AppFontSize.base)
            .fontColor(this.interests.indexOf(tag) >= 0 ? AppColors.textInverse : AppColors.textPrimary)
            .backgroundColor(this.interests.indexOf(tag) >= 0 ? AppColors.brand : AppColors.bgSecondary)
            .borderRadius(AppRadius.round)
            .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.sm, bottom: AppSpacing.sm })
            .onClick(() => this.toggleInterest(tag));
        }, (tag: string) => tag);
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(AppSpacing.lg)
  }

  build() {
    NavDestination() {
      Column() {
        // Skip 按钮
        Row() {
          Blank().layoutWeight(1)
          Text('跳过')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
            .padding(AppSpacing.base)
            .onClick(() => this.finish())
        }
        .width('100%')

        Swiper(this.controller) {
          this.PageWelcome();
          this.PageLevel();
          this.PageInterests();
        }
        .layoutWeight(1)
        .loop(false)
        .indicator(true)
        .onChange((idx: number) => { this.pageIndex = idx; })

        Button(this.pageIndex === 2
          ? $r('app.string.onboarding_start')
          : '下一步')
          .width('80%')
          .height(48)
          .fontSize(AppFontSize.md)
          .backgroundColor(AppColors.brand)
          .borderRadius(AppRadius.base)
          .margin({ bottom: AppSpacing.xl })
          .onClick(() => this.goNext());
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgPrimary)
    }
    .hideTitleBar(true)
  }
}
