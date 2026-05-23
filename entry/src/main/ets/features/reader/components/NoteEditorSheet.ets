/**
 * NoteEditorSheet.ets — W8 笔记编辑底部 sheet
 *
 * 基于 W6 AppSheet（snap [0.6, 0.95]）。
 * 支持两态：
 *   - 新建笔记（无 noteId 传入）
 *   - 编辑现有笔记（noteId 已知，显示删除按钮）
 *
 * 内容：
 *   1. 关联 highlight 文本预览（quote 风格）— 仅在 highlightText 不为空时显示
 *   2. 多行输入框（基于 W6 AppTextArea），最大 1000 字
 *   3. 标签选择 chip：预设标签 + 自定义新建
 *   4. 字数计数 200/1000（< 200 提示「再写一点」）
 *   5. 底部 action：保存 / 取消 / 删除（仅编辑态显示）
 *
 * 外部回调：
 *   - onSave(content, tags): Promise<void>
 *   - onDelete(): Promise<void>（可选）
 *
 * 加载态：
 *   保存/删除按钮在 await 期间显示 loading 并禁用其他按钮，
 *   防止双击重复提交。
 */

import {
  TextColors,
  BgColors,
  AccentColors,
  BorderColors,
  SurfaceColors,
  StateColors,
  useColor,
} from '../../../core/theme/AppColors';
import {
  FontFamily,
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius } from '../../../core/theme/AppSpacing';
import { AppSheet } from '../../../ui/primitives/Modal';
import { AppTextArea } from './Input';
import { AppButton } from './Button';
import { ToastManager } from './Toast';

/** 预设标签（按用户高频场景） */
const DEFAULT_PRESET_TAGS: string[] = [
  '生词',
  '语法',
  '金句',
  '想法',
  '疑问',
  '后续重读',
];

/** 内容字数下限，低于该值给提示但不阻止保存 */
const MIN_CONTENT_LEN = 5;
/** 字数上限 */
const MAX_CONTENT_LEN = 1000;

@Component
export struct NoteEditorSheet {
  // ── 双向显示控制 ──
  @Link visible: boolean;

  // ── 业务上下文 ──
  @Prop bookId: string = '';
  @Prop chapterIndex: number = -1;
  /** 关联的 highlight ID（可选）*/
  @Prop highlightId: string = '';
  /** 关联的 highlight 文字（用于 quote 预览）*/
  @Prop highlightText: string = '';
  /** 编辑现有笔记时传入；空字符串视为新建 */
  @Prop noteId: string = '';
  /** 编辑态初始内容 */
  @Prop initialContent: string = '';
  /** 编辑态初始标签 */
  @Prop initialTags: string[] = [];

  // ── 外观 ──
  @Prop isDark: boolean = false;

  // ── 回调 ──
  onSave?: (content: string, tags: string[]) => Promise<void>;
  onDelete?: () => Promise<void>;

  // ── 内部状态 ──
  @State private content: string = '';
  @State private tags: string[] = [];
  @State private newTagInput: string = '';
  @State private showCustomTagInput: boolean = false;
  @State private saving: boolean = false;
  @State private deleting: boolean = false;
  /** 用户可见的「全部可选标签」= 预设 ∪ 已选 */
  @State private allKnownTags: string[] = DEFAULT_PRESET_TAGS.slice();

  aboutToAppear(): void {
    this.resetState();
  }

  /** 把 Prop 同步到内部 State（每次显示前调用）*/
  private resetState(): void {
    this.content = this.initialContent;
    this.tags = this.initialTags ? this.initialTags.slice() : [];
    this.newTagInput = '';
    this.showCustomTagInput = false;
    this.saving = false;
    this.deleting = false;
    // 合并预设 + 已选，去重
    const merged = DEFAULT_PRESET_TAGS.slice();
    this.tags.forEach((t) => {
      if (!merged.includes(t)) merged.push(t);
    });
    this.allKnownTags = merged;
  }

  /** 是否编辑态 */
  private get isEditMode(): boolean {
    return this.noteId.length > 0;
  }

  /** 字数 */
  private get charCount(): number {
    return this.content.length;
  }

  private get charCountColor(): ResourceColor {
    if (this.charCount > MAX_CONTENT_LEN) {
      return useColor(StateColors.error, this.isDark);
    }
    if (this.charCount < MIN_CONTENT_LEN) {
      return useColor(TextColors.tertiary, this.isDark);
    }
    return useColor(TextColors.secondary, this.isDark);
  }

  private get sheetTitle(): string {
    return this.isEditMode ? '编辑笔记' : '新建笔记';
  }

  /** 切换标签选中态 */
  private toggleTag(tag: string): void {
    const idx = this.tags.indexOf(tag);
    if (idx >= 0) {
      this.tags.splice(idx, 1);
    } else {
      this.tags.push(tag);
    }
    // 触发 @State 数组变更
    this.tags = this.tags.slice();
  }

  /** 添加自定义标签 */
  private addCustomTag(): void {
    const t = this.newTagInput.trim();
    if (t.length === 0) {
      ToastManager.warning('请输入标签名');
      return;
    }
    if (t.length > 12) {
      ToastManager.warning('标签最多 12 字');
      return;
    }
    if (this.allKnownTags.includes(t)) {
      // 已存在则只勾选
      if (!this.tags.includes(t)) this.tags.push(t);
      this.tags = this.tags.slice();
    } else {
      this.allKnownTags = this.allKnownTags.concat([t]);
      this.tags = this.tags.concat([t]);
    }
    this.newTagInput = '';
    this.showCustomTagInput = false;
  }

  /** 保存 */
  private async handleSave(): Promise<void> {
    if (this.saving || this.deleting) return;
    if (this.content.trim().length === 0) {
      ToastManager.warning('笔记内容不能为空');
      return;
    }
    if (this.charCount > MAX_CONTENT_LEN) {
      ToastManager.warning(`笔记内容超过 ${MAX_CONTENT_LEN} 字`);
      return;
    }
    if (!this.onSave) {
      ToastManager.error('保存回调未配置');
      return;
    }
    this.saving = true;
    try {
      await this.onSave(this.content.trim(), this.tags.slice());
      ToastManager.success(this.isEditMode ? '已更新' : '已保存');
      this.visible = false;
    } catch (e) {
      ToastManager.error('保存失败，请重试');
    } finally {
      this.saving = false;
    }
  }

  /** 取消 */
  private handleCancel(): void {
    if (this.saving || this.deleting) return;
    this.visible = false;
  }

  /** 删除（仅编辑态）*/
  private async handleDelete(): Promise<void> {
    if (this.saving || this.deleting) return;
    if (!this.onDelete) {
      ToastManager.error('删除回调未配置');
      return;
    }
    this.deleting = true;
    try {
      await this.onDelete();
      ToastManager.success('已删除');
      this.visible = false;
    } catch (e) {
      ToastManager.error('删除失败，请重试');
    } finally {
      this.deleting = false;
    }
  }

  // ─────────────────────────────────────────────
  // Builder 区
  // ─────────────────────────────────────────────

  /** 关联 highlight 的 quote 预览 */
  @Builder
  private highlightQuote() {
    if (this.highlightText.length > 0) {
      Row() {
        // 左侧竖条
        Column()
          .width(3)
          .height('100%')
          .backgroundColor(useColor(AccentColors.primary, this.isDark))
          .borderRadius(Radius.sm)

        Column() {
          Text('原文摘录')
            .fontSize(FontSizeToken.caption2)
            .fontFamily(FontFamily.ui)
            .fontWeight(FontWeightToken.medium)
            .fontColor(useColor(AccentColors.primary, this.isDark))
            .margin({ bottom: Spacing.s1 })

          Text(this.highlightText)
            .fontSize(FontSizeToken.footnote)
            .fontFamily(FontFamily.body)
            .lineHeight(LineHeightToken.footnote)
            .fontColor(useColor(TextColors.secondary, this.isDark))
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: Spacing.s3 })
      }
      .width('100%')
      .padding(Spacing.s3)
      .backgroundColor(useColor(BgColors.secondary, this.isDark))
      .borderRadius(Radius.md)
      .margin({ bottom: Spacing.s4 })
    }
  }

  /** 单个标签 chip */
  @Builder
  private tagChip(tag: string) {
    Text(tag)
      .fontSize(FontSizeToken.footnote)
      .fontFamily(FontFamily.ui)
      .fontWeight(
        this.tags.includes(tag)
          ? FontWeightToken.medium
          : FontWeightToken.regular,
      )
      .fontColor(
        this.tags.includes(tag)
          ? '#FFFFFF'
          : useColor(TextColors.secondary, this.isDark),
      )
      .backgroundColor(
        this.tags.includes(tag)
          ? useColor(AccentColors.primary, this.isDark)
          : useColor(BgColors.secondary, this.isDark),
      )
      .padding({
        left: Spacing.s3,
        right: Spacing.s3,
        top: Spacing.s2,
        bottom: Spacing.s2,
      })
      .borderRadius(Radius.full)
      .border({
        width: this.tags.includes(tag) ? 0 : 1,
        color: useColor(BorderColors.primary, this.isDark),
      })
      .onClick(() => this.toggleTag(tag))
  }

  /** 标签选择区 */
  @Builder
  private tagsSection() {
    Column({ space: Spacing.s2 }) {
      Text('标签')
        .fontSize(FontSizeToken.footnote)
        .fontFamily(FontFamily.ui)
        .fontWeight(FontWeightToken.medium)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .width('100%')

      // chip 流式排布
      Flex({ wrap: FlexWrap.Wrap, space: { main: { value: Spacing.s2 }, cross: { value: Spacing.s2 } } }) {
        ForEach(this.allKnownTags, (tag: string) => {
          this.tagChip(tag)
        }, (tag: string) => tag)

        // 「+ 新建」按钮 / 输入框
        if (this.showCustomTagInput) {
          Row({ space: Spacing.s2 }) {
            TextInput({
              text: this.newTagInput,
              placeholder: '输入标签…',
            })
              .height(32)
              .width(120)
              .fontSize(FontSizeToken.footnote)
              .padding({ left: Spacing.s3, right: Spacing.s3 })
              .borderRadius(Radius.full)
              .backgroundColor(useColor(BgColors.secondary, this.isDark))
              .maxLength(12)
              .onChange((v: string) => {
                this.newTagInput = v;
              })
              .onSubmit(() => this.addCustomTag())

            Text('确认')
              .fontSize(FontSizeToken.footnote)
              .fontColor(useColor(AccentColors.primary, this.isDark))
              .onClick(() => this.addCustomTag())
            Text('取消')
              .fontSize(FontSizeToken.footnote)
              .fontColor(useColor(TextColors.tertiary, this.isDark))
              .onClick(() => {
                this.showCustomTagInput = false;
                this.newTagInput = '';
              })
          }
        } else {
          Text('+ 新建')
            .fontSize(FontSizeToken.footnote)
            .fontFamily(FontFamily.ui)
            .fontColor(useColor(AccentColors.primary, this.isDark))
            .padding({
              left: Spacing.s3,
              right: Spacing.s3,
              top: Spacing.s2,
              bottom: Spacing.s2,
            })
            .borderRadius(Radius.full)
            .border({
              width: 1,
              color: useColor(AccentColors.primary, this.isDark),
              style: BorderStyle.Dashed,
            })
            .onClick(() => {
              this.showCustomTagInput = true;
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: Spacing.s4 })
  }

  /** 字数计数行 */
  @Builder
  private counterRow() {
    Row() {
      // 左侧提示
      if (this.charCount < MIN_CONTENT_LEN && this.charCount > 0) {
        Text('再写一点会更有用')
          .fontSize(FontSizeToken.caption2)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
      }
      Blank()
      // 右侧字数
      Text(`${this.charCount} / ${MAX_CONTENT_LEN}`)
        .fontSize(FontSizeToken.caption2)
        .fontColor(this.charCountColor)
    }
    .width('100%')
    .margin({ top: Spacing.s1, bottom: Spacing.s4 })
  }

  /** 底部按钮区 */
  @Builder
  private actionRow() {
    Row({ space: Spacing.s3 }) {
      // 删除（仅编辑态）
      if (this.isEditMode && this.onDelete) {
        AppButton({
          label: '删除',
          variant: 'destructive',
          size: 'md',
          loading: this.deleting,
          disabled: this.saving,
          onClick: () => {
            this.handleDelete();
          },
        })
      }

      // 取消
      AppButton({
        label: '取消',
        variant: 'ghost',
        size: 'md',
        disabled: this.saving || this.deleting,
        onClick: () => this.handleCancel(),
      })

      // 保存
      AppButton({
        label: this.isEditMode ? '更新' : '保存',
        variant: 'primary',
        size: 'md',
        fullWidth: false,
        loading: this.saving,
        disabled: this.deleting || this.charCount === 0,
        onClick: () => {
          this.handleSave();
        },
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
  }

  /** Sheet 主体内容 */
  @Builder
  private sheetContent() {
    Column() {
      // 关联 highlight 引用
      this.highlightQuote()

      // 多行内容输入
      AppTextArea({
        label: '笔记内容',
        placeholder: '记录你的想法、疑问或学习要点…',
        value: $$this.content,
        maxLength: MAX_CONTENT_LEN,
        minRows: 4,
        maxRows: 10,
      })

      // 字数计数
      this.counterRow()

      // 标签选择
      this.tagsSection()

      // 底部操作按钮
      this.actionRow()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    AppSheet({
      visible: $visible,
      title: this.sheetTitle,
      snapPoints: [0.6, 0.95],
      isDark: this.isDark,
      sheetBody: () => {
        this.sheetContent()
      },
    })
  }
}
