// L2 - API - Badges
import { HttpClient } from '../client/HttpClient';

export interface Badge {
  id: string;
  name: string;
  description: string;
  tier: 'bronze' | 'silver' | 'gold' | 'platinum';
  modelKey: string;
}

export interface BadgeProgress {
  badgeId: string;
  current: number;
  target: number;
  percent: number;
}

export interface BadgeWithProgress extends Badge {
  progress: BadgeProgress;
  unlocked: boolean;
}

export class BadgesApi {
  static listAll(): Promise<Badge[]> {
    return HttpClient.get<Badge[]>('/badges');
  }

  static listUserBadges(): Promise<Badge[]> {
    return HttpClient.get<Badge[]>('/badges/user');
  }

  static listUserWithProgress(): Promise<BadgeWithProgress[]> {
    return HttpClient.get<BadgeWithProgress[]>('/badges/user/with-progress');
  }

  static getDetail(id: string): Promise<Badge> {
    return HttpClient.get<Badge>(`/badges/detail/${encodeURIComponent(id)}`);
  }

  static checkUnlocked(): Promise<Badge[]> {
    return HttpClient.get<Badge[]>('/medals/user/check');
  }

  static getNextBadge(): Promise<BadgeProgress> {
    return HttpClient.get<BadgeProgress>('/medals/user/next');
  }
}
