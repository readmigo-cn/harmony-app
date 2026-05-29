// L4 Feature - Badges - Component
import type { Badge } from '../service/BadgesService';

const TIER_COLORS: Record<string, string> = {
  bronze: '#CD7F32',
  silver: '#C0C0C0',
  gold: '#FFD700',
  platinum: '#E5E4E2',
};

@Component
export struct BadgeShareCard {
  badge: Badge = { id: '', name: '', description: '', tier: 'bronze', modelKey: '' };

  private tierColor(): string {
    return TIER_COLORS[this.badge.tier] ?? '#CD7F32';
  }

  build() {
    Column({ space: 16 }) {
      Rect()
        .width(120)
        .height(120)
        .fill(this.tierColor())
        .radius(24)

      Column({ space: 4 }) {
        Text(this.badge.name)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .textAlign(TextAlign.Center)

        Text(this.badge.description)
          .fontSize(13)
          .fontColor('#666666')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
      .width('100%')

      Text('Readmigo')
        .fontSize(11)
        .fontColor('#AAAAAA')
        .textAlign(TextAlign.Center)
    }
    .width(280)
    .padding(24)
    .borderRadius(20)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Center)
  }
}
