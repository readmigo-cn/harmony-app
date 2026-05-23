/**
 * PersonalNoteSyncer.ets — 用户笔记 entity 同步器
 *
 * 策略：
 *   - 默认 LWW（updatedAt 大者胜，noteText/highlightText 整体覆盖）
 *   - deleted: 任一方为 true 即删除
 */

import { EntitySyncer, PushResult, SyncableEntity, SyncApi, lastWriteWins } from '../SyncEngine';

export interface PersonalNoteEntity extends SyncableEntity {
  bookId: string;
  chapterId?: string;
  blockIndex?: number;
  charOffset?: number;
  charLength?: number;
  originalText: string;
  noteText: string;
  kind: 'highlight' | 'note' | 'word';
  color?: string;
  createdAt: string;
}

export class PersonalNoteSyncer implements EntitySyncer<PersonalNoteEntity> {
  entityType: string = 'personal-note';

  pull(since?: Date): Promise<PersonalNoteEntity[]> {
    return SyncApi.pullEntity<PersonalNoteEntity>(this.entityType, since);
  }

  push(items: PersonalNoteEntity[]): Promise<PushResult<PersonalNoteEntity>> {
    return SyncApi.pushEntity<PersonalNoteEntity>(this.entityType, items);
  }

  resolveConflict(local: PersonalNoteEntity, server: PersonalNoteEntity): PersonalNoteEntity {
    const winner = lastWriteWins(local, server);
    const deleted = (local.deleted === true) || (server.deleted === true);
    return {
      id: winner.id,
      updatedAt: winner.updatedAt,
      bookId: winner.bookId,
      chapterId: winner.chapterId,
      blockIndex: winner.blockIndex,
      charOffset: winner.charOffset,
      charLength: winner.charLength,
      originalText: winner.originalText,
      noteText: winner.noteText,
      kind: winner.kind,
      color: winner.color,
      createdAt: winner.createdAt,
      deleted,
    };
  }
}
