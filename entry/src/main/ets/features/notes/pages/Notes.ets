import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import { NoteRepository, LocalNote } from '../../../core/persistence/NoteRepository';
import promptAction from '@ohos.promptAction';
// W14-C3：平板双栏布局
import {
  Breakpoint,
  FoldStatus,
  STORAGE_KEY_BREAKPOINT,
  STORAGE_KEY_FOLD_STATUS,
} from '../../../core/theme/Breakpoints';
import { NotesTabletLayout } from '../../multi-platform/pages/tablet/NotesTabletLayout';

@Component
export struct Notes {
  @State notes: LocalNote[] = [];
  @State loading: boolean = false;
  // 当前显示的所有书 id
  @State bookIds: string[] = [];
  @StorageProp(STORAGE_KEY_BREAKPOINT) currentBp: Breakpoint = Breakpoint.MD;
  @StorageProp(STORAGE_KEY_FOLD_STATUS) foldStatus: FoldStatus = FoldStatus.UNKNOWN;

  private isTabletLayout(): boolean {
    if (this.currentBp === Breakpoint.LG || this.currentBp === Breakpoint.XL) return true;
    return this.foldStatus === FoldStatus.EXPAND;
  }

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    try {
      // 没有"按用户全列"的本地接口，先列出曾保存过的 bookId 再合并
      // 简化：仅查 demo book 和当前 reading 当前书；后续 V2 schema 加 user_id 时再优化
      const ids = ['demo', 'pride-and-prejudice', 'the-adventures-of-sherlock-holmes',
                   'the-great-gatsby', 'alice-in-wonderland', 'frankenstein'];
      const all: LocalNote[] = [];
      for (const bid of ids) {
        const part = await NoteRepository.listByBook(bid);
        if (part.length > 0) all.push(...part);
      }
      all.sort((a, b) => b.createdAt - a.createdAt);
      this.notes = all;
    } finally {
      this.loading = false;
    }
  }

  private formatDate(ms: number): string {
    const d = new Date(ms);
    const yy = d.getFullYear();
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const hh = String(d.getHours()).padStart(2, '0');
    const mi = String(d.getMinutes()).padStart(2, '0');
    return `${yy}-${mm}-${dd} ${hh}:${mi}`;
  }

  private async deleteNote(id: string): Promise<void> {
    AlertDialog.show({
      title: '删除笔记？',
      message: '此操作不可恢复',
      primaryButton: {
        value: '取消',
        action: () => {},
      },
      secondaryButton: {
        value: '删除',
        fontColor: AppColors.danger,
        action: async () => {
          try {
            await NoteRepository.deleteById(id);
            promptAction.showToast({ message: '已删除' });
            await this.load();
          } catch (_e) {
            promptAction.showToast({ message: '删除失败' });
          }
        },
      },
    });
  }

  @Builder
  noteRow(n: LocalNote) {
    Column({ space: AppSpacing.xs }) {
      Row() {
        Text(n.originalText)
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text(n.bookId)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
          .padding({ left: AppSpacing.xs, right: AppSpacing.xs })
          .borderRadius(AppRadius.sm)
          .backgroundColor(AppColors.bgSecondary)
      }
      .width('100%')

      if (n.noteText && n.noteText.length > 0) {
        Text(n.noteText)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textSecondary)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(20)
          .width('100%')
      }

      Text(this.formatDate(n.createdAt))
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textTertiary)
    }
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.base)
    .width('100%')
    .backgroundColor(AppColors.bgElevated)
    .borderRadius(AppRadius.base)
    .gesture(
      LongPressGesture({ repeat: false }).onAction(() => this.deleteNote(n.id)),
    )
  }

  @Builder
  mobileBuilder() {
    Column() {
      Row() {
        Text('< 返回')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.brand)
          .onClick(() => RouterService.pop())
        Blank()
      }
      .width('100%')
      .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.sm, bottom: AppSpacing.sm })

      Text($r('app.string.notes_title'))
        .fontSize(AppFontSize.xl)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .padding({ left: AppSpacing.base, right: AppSpacing.base })
        .width('100%')
        .textAlign(TextAlign.Start)

      if (this.loading) {
        Column() {
          LoadingProgress().width(40).height(40).color(AppColors.brand)
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      } else if (this.notes.length === 0) {
        Column() {
          Text($r('app.string.notes_empty'))
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textTertiary)
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      } else {
        List({ space: AppSpacing.sm }) {
          ForEach(this.notes, (n: LocalNote) => {
            ListItem() {
              this.noteRow(n)
            }
          }, (n: LocalNote) => n.id)
        }
        .layoutWeight(1)
        .padding(AppSpacing.base)
      }

      Text('提示：长按一条笔记可删除')
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textTertiary)
        .padding({ bottom: AppSpacing.sm })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }

  build() {
    NavDestination() {
      if (this.isTabletLayout()) {
        NotesTabletLayout()
      } else {
        this.mobileBuilder()
      }
    }
    .hideTitleBar(true)
  }
}
