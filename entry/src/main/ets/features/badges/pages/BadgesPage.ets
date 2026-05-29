// L4 Feature - Badges - Page (gallery grid)
import { IntentBus } from '../../../core/intent/IntentBus';
import { BadgesViewModel } from '../viewmodel/BadgesViewModel';
import { BadgesIntents } from '../intent/BadgesIntents';
import { BadgeCard } from '../components/BadgeCard';
import type { Badge, BadgeProgress } from '../service/BadgesService';

@Entry
@Component
struct BadgesPage {
  private vm: BadgesViewModel = new BadgesViewModel();

  aboutToAppear(): void {
    IntentBus.getInstance().publish(BadgesIntents.loadGallery());
    IntentBus.getInstance().publish(BadgesIntents.checkUnlocked());
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  private findProgress(badgeId: string, list: BadgeProgress[]): BadgeProgress | null {
    for (const p of list) {
      if (p.badgeId === badgeId) return p;
    }
    return null;
  }

  build() {
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
            .onClick(() => IntentBus.getInstance().publish(BadgesIntents.loadGallery()))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.vm.state.status === 'data') {
        this.GalleryContent()
      } else {
        Text('Loading badges...')
          .fontSize(14)
          .fontColor('#999999')
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  GalleryContent() {
    if (this.vm.state.status === 'data') {
      const data = this.vm.state.data;
      Scroll() {
        Column({ space: 16 }) {
          Text('My Badges')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
            .padding({ left: 16, top: 16 })

          Grid() {
            ForEach(
              data.gallery ?? [],
              (badge: Badge) => {
                GridItem() {
                  BadgeCard({
                    badge: badge,
                    progress: this.findProgress(badge.id, data.inProgress ?? []),
                    onTap: (badgeId: string) => {
                      IntentBus.getInstance().publish(BadgesIntents.openDetail(badgeId));
                    },
                  })
                }
              },
              (badge: Badge) => badge.id,
            )
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(12)
          .rowsGap(12)
          .padding({ left: 16, right: 16, bottom: 24 })
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
  }
}
