import router from '@ohos.router';
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { UserStore, UserProfile } from '../../../store/UserStore';
import { RouterService } from '../../../core/router/RouterService';
import { RoutePath } from '../../../core/router/RouteConstants';
import { PaywallSheet } from '../../../features/account/components/PaywallSheet';
import { SubscriptionApi, SubscriptionInfo } from '../../../api/subscription/SubscriptionApi';

@Component
export struct Me {
  @State profile: UserProfile | null = null;
  @State sub: SubscriptionInfo | null = null;

  private paywallController: CustomDialogController = new CustomDialogController({
    builder: PaywallSheet({ onPurchaseSuccess: () => this.loadSubscription() }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
  });

  aboutToAppear(): void {
    this.profile = UserStore.getProfile() ?? null;
    this.loadSubscription();
  }

  private async loadSubscription(): Promise<void> {
    if (!UserStore.isLoggedIn()) return;
    try {
      this.sub = await SubscriptionApi.me();
    } catch (_e) {
      this.sub = null;
    }
  }

  private onLogout(): void {
    UserStore.clear();
    RouterService.push(RoutePath.LOGIN);
  }

  private openPaywall(): void {
    this.paywallController.open();
  }

  build() {
    Column({ space: AppSpacing.lg }) {
      Text($r('app.string.me_title'))
        .fontSize(AppFontSize.xl)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .padding(AppSpacing.base)
        .width('100%')
        .textAlign(TextAlign.Start)

      Row({ space: AppSpacing.base }) {
        Image(this.profile?.avatarUrl ?? $r('app.media.app_icon'))
          .width(64).height(64).borderRadius(AppRadius.round)
        Column({ space: AppSpacing.xs }) {
          Text(this.profile?.nickname ?? '未登录')
            .fontSize(AppFontSize.md)
            .fontColor(AppColors.textPrimary)
          Text(this.profile?.phone ?? '')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(AppSpacing.base)

      // Pro 卡片
      Column({ space: AppSpacing.xs }) {
        Row() {
          Text(this.sub?.isPro ? '✨ Pro 已开通' : '升级 Pro')
            .fontSize(AppFontSize.md)
            .fontWeight(AppFontWeight.bold)
            .fontColor(this.sub?.isPro ? AppColors.brand : AppColors.textPrimary)
            .layoutWeight(1)
          Text('>')
            .fontSize(AppFontSize.md)
            .fontColor(AppColors.textSecondary)
        }
        .width('100%')
        Text(this.sub?.isPro && this.sub.subscription?.expiresAt
          ? `续费至 ${this.sub.subscription.expiresAt.slice(0, 10)}`
          : '解锁全部图书与 AI 学习功能')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => {
        if (this.sub?.isPro) {
          router.pushUrl({ url: RoutePath.SUBSCRIPTIONS_URL })
            .catch((_e: Error) => {});
        } else {
          this.openPaywall();
        }
      })

      // 订阅管理（W17-C5）
      Row() {
        Text('订阅管理')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => {
        router.pushUrl({ url: RoutePath.SUBSCRIPTIONS_URL })
          .catch((_e: Error) => {});
      })

      // 我的笔记
      Row() {
        Text($r('app.string.me_notes'))
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => RouterService.push(RoutePath.NOTES))

      // W9-C1：我的生词本（auth required，未登录走 RouterService 触发 guard）
      Row() {
        Text('我的生词本')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => {
        if (!UserStore.isLoggedIn()) {
          RouterService.push(RoutePath.VOCAB);
          return;
        }
        router.pushUrl({ url: RoutePath.VOCAB_URL })
          .catch((_e: Error) => { /* main_pages.json 未注册时吞掉 */ });
      })

      // 学习数据（W9-C5：词汇量统计 + 弱点分析入口）
      Row() {
        Text('学习数据')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => {
        router.pushUrl({ url: RoutePath.VOCAB_STATS_URL })
          .catch((_e: Error) => {
            // 若 main_pages.json 未注册，会抛错；此处吞掉避免崩溃
          });
      })

      // 我的学习计划（W9-C6）
      Row() {
        Text('我的学习计划')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => {
        router.pushUrl({ url: RoutePath.STUDY_PLAN_URL })
          .catch((_e: Error) => {});
      })

      // 通知中心（W18-C6）
      Row() {
        Text('通知中心')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => {
        router.pushUrl({ url: RoutePath.NOTIFICATION_CENTER_URL })
          .catch((_e: Error) => { /* main_pages.json 未注册时吞掉 */ });
      })

      // 反馈与帮助（W19-C1+C2 入口）
      Row() {
        Text('反馈与帮助')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => {
        if (UserStore.isLoggedIn()) {
          RouterService.push(RoutePath.TICKET_LIST);
        } else {
          RouterService.push(RoutePath.FEEDBACK);
        }
      })

      // 常见问题 FAQ（W19-C3）
      Row() {
        Text('常见问题')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => {
        router.pushUrl({ url: RoutePath.FAQ_URL })
          .catch((_e: Error) => {});
      })

      // 联系我们（W19-C5）
      Row() {
        Text('联系我们')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => {
        router.pushUrl({ url: RoutePath.CONTACT_URL })
          .catch((_e: Error) => {});
      })

      // 关于（W19-C4）
      Row() {
        Text('关于')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => {
        router.pushUrl({ url: RoutePath.ABOUT_URL })
          .catch((_e: Error) => {});
      })

      // 开发者：原生组件 Demo（W2-C5；目前始终显示，正式版可加 BuildProfile.DEBUG 门控）
      Row() {
        Text('开发者：原生组件 Demo')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => {
        router.pushUrl({ url: RoutePath.XCOMPONENT_DEMO_URL })
          .catch((_e: Error) => {
            // 若 main_pages.json 未注册，会抛错；此处吞掉避免崩溃
          });
      })

      // 开发者：组件演示（W6-C10；DEBUG 入口，正式版可加 BuildProfile.DEBUG 门控）
      Row() {
        Text('开发者：组件演示')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text('>')
          .fontSize(AppFontSize.md)
          .fontColor(AppColors.textSecondary)
      }
      .width('90%')
      .padding(AppSpacing.base)
      .borderRadius(AppRadius.md)
      .backgroundColor(AppColors.bgElevated)
      .onClick(() => {
        router.pushUrl({ url: RoutePath.COMPONENT_GALLERY_URL })
          .catch((_e: Error) => {
            // 若 main_pages.json 未注册，会抛错；此处吞掉避免崩溃
          });
      })

      Button($r('app.string.me_logout'))
        .width('90%')
        .height(48)
        .fontColor(AppColors.danger)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.base)
        .onClick(() => this.onLogout())
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppColors.bgPrimary)
  }
}
