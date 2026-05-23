/**
 * VocabNoteSyncer.ets — 生词本 entity 同步器
 *
 * 字段级合并策略：
 *   - reviewCount, masteryLevel：取 max（本地反复练习不应被旧 server 数据覆盖）
 *   - lastReviewedAt：取 max
 *   - definition / example：updatedAt 大者胜（LWW 兜底）
 *   - deleted：任一方为 true 即视为删除
 */

import { EntitySyncer, PushResult, SyncableEntity, SyncApi, lastWriteWins } from '../SyncEngine';

export interface VocabNoteEntity extends SyncableEntity {
  word: string;
  definition?: string;
  example?: string;
  bookId?: string;
  reviewCount: number;
  masteryLevel: number;        // 0-5 SRS box
  lastReviewedAt?: string;     // ISO
  nextReviewAt?: string;       // ISO
}

export class VocabNoteSyncer implements EntitySyncer<VocabNoteEntity> {
  entityType: string = 'vocab-note';

  pull(since?: Date): Promise<VocabNoteEntity[]> {
    return SyncApi.pullEntity<VocabNoteEntity>(this.entityType, since);
  }

  push(items: VocabNoteEntity[]): Promise<PushResult<VocabNoteEntity>> {
    return SyncApi.pushEntity<VocabNoteEntity>(this.entityType, items);
  }

  resolveConflict(local: VocabNoteEntity, server: VocabNoteEntity): VocabNoteEntity {
    // 字段级合并 + LWW 兜底
    const base = lastWriteWins(local, server);
    const merged: VocabNoteEntity = {
      id: base.id,
      updatedAt: base.updatedAt,
      word: base.word,
      definition: base.definition,
      example: base.example,
      bookId: base.bookId,
      // SRS 字段：取 max（不丢复习进度）
      reviewCount: Math.max(local.reviewCount ?? 0, server.reviewCount ?? 0),
      masteryLevel: Math.max(local.masteryLevel ?? 0, server.masteryLevel ?? 0),
      // 时间戳取靠后的
      lastReviewedAt: VocabNoteSyncer.maxIso(local.lastReviewedAt, server.lastReviewedAt),
      nextReviewAt: VocabNoteSyncer.maxIso(local.nextReviewAt, server.nextReviewAt),
      deleted: (local.deleted === true) || (server.deleted === true),
    };
    return merged;
  }

  private static maxIso(a?: string, b?: string): string | undefined {
    if (!a) return b;
    if (!b) return a;
    return Date.parse(a) > Date.parse(b) ? a : b;
  }
}
