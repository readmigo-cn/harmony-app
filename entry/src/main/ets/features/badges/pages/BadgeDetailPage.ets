// L4 Feature - Badges - Detail Page (single badge + progress to next)
import { IntentBus } from '../../../core/intent/IntentBus';
import { BadgesViewModel } from '../viewmodel/BadgesViewModel';
import { BadgesIntents } from '../intent/BadgesIntents';
import { BadgeProgressBar } from '../components/BadgeProgressBar';
import { BadgeShareCard } from '../components/BadgeShareCard';
import type { Badge, BadgeProgress } from '../service/BadgesService';

const TIER_COLORS: Record<string, string> = {
  bronze: '#CD7F32',
  silver: '#C0C0C0',
  gold: '#FFD700',
  platinum: '#E5E4E2',
};

@Entry
@Component
struct BadgeDetailPage {
  @State private showShareCard: boolean = false;
  private vm: BadgesViewModel = new BadgesViewModel();

  aboutToAppear(): void {
    IntentBus.getInstance().publish(BadgesIntents.loadProgress());
    IntentBus.getInstance().publish(BadgesIntents.loadNext());
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  private tierColor(tier: string): string {
    return TIER_COLORS[tier] ?? '#CD7F32';
  }

  build() {
    Stack() {
      Column() {
        if (this.vm.state.status === 'loading') {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#F4A261')
            .layoutWeight(1)
        } else if (this.vm.state.status === 'error') {
          Column({ space: 12 }) {
            Text(this.vm.state.error?.message ?? 'Error')
              .fontSize(14)
              .fontColor('#CC0000')
            Button('Retry')
              .onClick(() => IntentBus.getInstance().publish(BadgesIntents.loadProgress()))
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.vm.state.status === 'data') {
          this.DetailContent()
        } else {
          Text('Loading...')
            .fontSize(14)
            .fontColor('#999999')
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF')

      if (this.showShareCard && this.vm.state.status === 'data' && this.vm.state.data.selected) {
        this.ShareOverlay(this.vm.state.data.selected)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  DetailContent() {
    if (this.vm.state.status === 'data') {
      const data = this.vm.state.data;
      const badge: Badge | undefined = data.selected;
      const next: BadgeProgress | undefined = data.nextBadge;

      Scroll() {
        Column({ space: 24 }) {
          if (badge) {
            Rect()
              .width(140)
              .height(140)
              .fill(this.tierColor(badge.tier))
              .radius(28)
              .margin({ top: 32 })

            Column({ space: 8 }) {
              Text(badge.name)
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1A1A1A')
                .textAlign(TextAlign.Center)

              Text(badge.description)
                .fontSize(14)
                .fontColor('#666666')
                .textAlign(TextAlign.Center)
                .padding({ left: 24, right: 24 })

              Text(badge.tier.toUpperCase())
                .fontSize(11)
                .fontColor('#FFFFFF')
                .backgroundColor(this.tierColor(badge.tier))
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .borderRadius(20)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)

            Button('Share Badge')
              .width(200)
              .height(44)
              .backgroundColor('#F4A261')
              .fontColor('#FFFFFF')
              .fontSize(15)
              .borderRadius(22)
              .onClick(() => {
                this.showShareCard = true;
                IntentBus.getInstance().publish(BadgesIntents.shareBadge(badge.id));
              })
          }

          if (next) {
            Column({ space: 12 }) {
              Text('Next Badge Progress')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1A1A1A')
                .alignSelf(ItemAlign.Start)

              BadgeProgressBar({ progress: next })
            }
            .width('100%')
            .padding({ left: 24, right: 24 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 40 })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
  }

  @Builder
  ShareOverlay(badge: Badge) {
    Stack() {
      Rect()
        .width('100%')
        .height('100%')
        .fill('rgba(0,0,0,0.5)')
        .onClick(() => { this.showShareCard = false; })

      BadgeShareCard({ badge: badge })
    }
    .width('100%')
    .height('100%')
  }
}
