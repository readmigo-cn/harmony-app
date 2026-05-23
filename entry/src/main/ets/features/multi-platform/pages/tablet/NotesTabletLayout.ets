/**
 * NotesTabletLayout.ets — W14-C3 平板专属笔记双栏布局
 *
 * 布局：
 *   - 左侧 (35%)：笔记列表（按时间倒序，分组按书显示）
 *   - 右侧 (65%)：选中笔记详情 + 编辑（多行文本 + 保存）
 *
 * 与 mobile Notes 共用 NoteRepository（本地 RDB），状态隔离：
 *   左侧选中 → 右侧加载笔记内容；编辑后调 NoteRepository.update（占位）。
 */

import { AppColors } from '../../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../../core/theme/AppSpacing';
import { NoteRepository, LocalNote } from '../../../../core/persistence/NoteRepository';
import promptAction from '@ohos.promptAction';

@Component
export struct NotesTabletLayout {
  @State notes: LocalNote[] = [];
  @State loading: boolean = false;
  @State selectedId: string = '';
  @State editText: string = '';
  @State sortMode: 'time' | 'book' = 'time';
  /** 当前选中笔记缓存：避免每次 build 都 array.find */
  @State currentNoteCache: LocalNote | null = null;

  aboutToAppear(): void {
    this.load();
  }

  /** 同步刷新 currentNoteCache（selectedId / notes 变化时调用） */
  private refreshCurrentNoteCache(): void {
    this.currentNoteCache = this.notes.find((n) => n.id === this.selectedId) ?? null;
  }

  private async load(): Promise<void> {
    this.loading = true;
    try {
      // 与 mobile Notes 一致：先列出 demo + 几本常见 book
      const ids = ['demo', 'pride-and-prejudice', 'the-adventures-of-sherlock-holmes',
                   'the-great-gatsby', 'alice-in-wonderland', 'frankenstein'];
      const all: LocalNote[] = [];
      for (const bid of ids) {
        const part = await NoteRepository.listByBook(bid);
        if (part.length > 0) all.push(...part);
      }
      all.sort((a, b) => b.createdAt - a.createdAt);
      this.notes = all;
      // 自动选中第一条
      if (!this.selectedId && all.length > 0) {
        this.selectNote(all[0]);
      } else {
        // 刷新缓存（可能选中的笔记已被删除）
        this.refreshCurrentNoteCache();
      }
    } finally {
      this.loading = false;
    }
  }

  private selectNote(n: LocalNote): void {
    this.selectedId = n.id;
    this.editText = n.noteText ?? '';
    this.refreshCurrentNoteCache();
  }

  private formatDate(ms: number): string {
    const d = new Date(ms);
    const yy = d.getFullYear();
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    return `${yy}-${mm}-${dd}`;
  }

  private async deleteCurrent(): Promise<void> {
    const id = this.selectedId;
    if (!id) return;
    AlertDialog.show({
      title: '删除笔记？',
      message: '此操作不可恢复',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: AppColors.danger,
        action: async () => {
          try {
            await NoteRepository.deleteById(id);
            promptAction.showToast({ message: '已删除' });
            this.selectedId = '';
            await this.load();
          } catch (_e) {
            promptAction.showToast({ message: '删除失败' });
          }
        },
      },
    });
  }

  // ---- builders --------------------------------------------------------

  @Builder
  noteRow(n: LocalNote) {
    Column({ space: 2 }) {
      Text(n.originalText)
        .fontSize(AppFontSize.sm)
        .fontWeight(AppFontWeight.medium)
        .fontColor(AppColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (n.noteText) {
        Text(n.noteText)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textSecondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      Row() {
        Text(this.formatDate(n.createdAt))
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
          .layoutWeight(1)
        Text(n.bookId)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: AppSpacing.sm, right: AppSpacing.sm,
      top: AppSpacing.xs, bottom: AppSpacing.xs,
    })
    .backgroundColor(this.selectedId === n.id ? AppColors.bgSecondary : AppColors.bgPrimary)
    .borderRadius(AppRadius.sm)
    .onClick(() => this.selectNote(n))
  }

  @Builder
  leftPane() {
    Column() {
      // 头：标题 + 排序
      Row() {
        Text('我的笔记')
          .fontSize(AppFontSize.lg)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)
        Text(this.sortMode === 'time' ? '时间' : '书')
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.brand)
          .padding(AppSpacing.xs)
          .onClick(() => { this.sortMode = this.sortMode === 'time' ? 'book' : 'time'; })
      }
      .width('100%')
      .padding({
        left: AppSpacing.base, right: AppSpacing.base,
        top: AppSpacing.sm, bottom: AppSpacing.xs,
      })
      Divider().color(AppColors.divider)

      if (this.loading) {
        Column() {
          LoadingProgress().width(28).height(28).color(AppColors.brand)
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      } else if (this.notes.length === 0) {
        Column() {
          Text('还没有笔记')
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textTertiary)
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      } else {
        List({ space: AppSpacing.xs }) {
          ForEach(this.notes, (n: LocalNote) => {
            ListItem() { this.noteRow(n) }
          }, (n: LocalNote) => n.id)
        }
        .layoutWeight(1)
        .padding({ left: AppSpacing.sm, right: AppSpacing.sm, top: AppSpacing.xs })
        .scrollBar(BarState.Auto)
      }
    }
    .width('35%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }

  @Builder
  rightPaneEmpty() {
    Column({ space: AppSpacing.base }) {
      Text('✎').fontSize(64).opacity(0.5)
      Text('请选择一条笔记')
        .fontSize(AppFontSize.md)
        .fontColor(AppColors.textSecondary)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  @Builder
  rightPaneEditor(n: LocalNote) {
    Column() {
      // 头：原文 + 元信息 + 删除
      Column({ space: AppSpacing.sm }) {
        Row() {
          Text(`书: ${n.bookId}`)
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.textTertiary)
            .layoutWeight(1)
          Text('删除')
            .fontSize(AppFontSize.xs)
            .fontColor(AppColors.danger)
            .padding(AppSpacing.xs)
            .onClick(() => this.deleteCurrent())
        }
        .width('100%')
        Text(n.originalText)
          .fontSize(AppFontSize.lg)
          .fontWeight(AppFontWeight.medium)
          .fontColor(AppColors.textPrimary)
          .width('100%')
        Text(this.formatDate(n.createdAt))
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .padding(AppSpacing.lg)
      .width('100%')
      Divider().color(AppColors.divider)

      // 编辑区
      TextArea({ placeholder: '编辑笔记...', text: this.editText })
        .layoutWeight(1)
        .width('100%')
        .padding(AppSpacing.lg)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textPrimary)
        .backgroundColor(AppColors.bgPrimary)
        .onChange((v: string) => { this.editText = v; })

      Row({ space: AppSpacing.sm }) {
        Button('保存')
          .backgroundColor(AppColors.brand)
          .fontColor(AppColors.textInverse)
          .borderRadius(AppRadius.base)
          .onClick(() => {
            // NoteRepository 暂未提供 update API；这里 toast 占位
            promptAction.showToast({ message: '保存功能待 NoteRepository.update 接入' });
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding(AppSpacing.base)
    }
    .width('100%').height('100%')
  }

  @Builder
  rightPane() {
    Column() {
      if (this.currentNoteCache === null) {
        this.rightPaneEmpty()
      } else {
        this.rightPaneEditor(this.currentNoteCache)
      }
    }
    .width('65%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }

  build() {
    Row() {
      this.leftPane()
      Divider().vertical(true).strokeWidth(1).color(AppColors.divider).height('100%')
      this.rightPane()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }
}
