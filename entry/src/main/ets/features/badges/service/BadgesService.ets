// L2 Feature - Badges - Service
import { BadgesApi } from '../../../api/badges/BadgesApi';
import type { Badge, BadgeProgress, BadgeWithProgress } from '../../../api/badges/BadgesApi';

export type { Badge, BadgeProgress, BadgeWithProgress };

export class BadgesService {
  static async fetchGallery(): Promise<BadgeWithProgress[]> {
    return BadgesApi.listUserWithProgress();
  }

  static async fetchProgress(): Promise<BadgeProgress[]> {
    const items = await BadgesApi.listUserWithProgress();
    return items.map((b) => b.progress);
  }

  static async fetchDetail(badgeId: string): Promise<Badge> {
    return BadgesApi.getDetail(badgeId);
  }

  static async checkNewlyUnlocked(): Promise<Badge[]> {
    return BadgesApi.checkUnlocked();
  }

  static async fetchNextBadge(): Promise<BadgeProgress> {
    return BadgesApi.getNextBadge();
  }
}
