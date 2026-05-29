// L4 Feature - Badges - Component
import type { Badge, BadgeProgress } from '../service/BadgesService';
import { BadgeProgressBar } from './BadgeProgressBar';

const TIER_COLORS: Record<string, string> = {
  bronze: '#CD7F32',
  silver: '#C0C0C0',
  gold: '#FFD700',
  platinum: '#E5E4E2',
};

@Component
export struct BadgeCard {
  badge: Badge = { id: '', name: '', description: '', tier: 'bronze', modelKey: '' };
  progress: BadgeProgress | null = null;
  onTap: (badgeId: string) => void = () => {};

  private tierColor(): string {
    return TIER_COLORS[this.badge.tier] ?? '#CD7F32';
  }

  build() {
    Column({ space: 8 }) {
      // Thumbnail: mock colored Rect until XComponent integration (W5)
      Rect()
        .width(72)
        .height(72)
        .fill(this.tierColor())
        .radius(12)

      Text(this.badge.name)
        .fontSize(12)
        .fontColor('#1A1A1A')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')

      if (this.progress !== null) {
        BadgeProgressBar({ progress: this.progress })
      }
    }
    .width(100)
    .padding(8)
    .borderRadius(12)
    .backgroundColor('#F9F9F9')
    .onClick(() => this.onTap(this.badge.id))
  }
}
