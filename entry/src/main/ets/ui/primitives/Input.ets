/**
 * Input.ets — 米果智读输入框组件（W6-C2）
 *
 * 包含两个组件：
 *   AppInput    — 单行输入框
 *   AppTextArea — 多行输入框
 *
 * 状态：idle / focused / error / disabled
 * 特性：Label / helper / error message / prefix icon / suffix icon /
 *        clear button / counter / autoFocus / validation
 */

import { EffectiveTheme } from '../../core/theme/Theme.types';
import {
  useColor,
  TextColors,
  BgColors,
  BorderColors,
  SurfaceColors,
  StateColors,
  AccentColors,
  BrandPalette,
} from '../../core/theme/AppColors';
import {
  Typography,
  BodyStyles,
  LabelStyles,
  CaptionStyle,
} from '../../core/theme/AppTypography';
import { Spacing, Radius, MotionDuration, MotionEasing } from '../../core/theme/AppSpacing';

// ─────────────────────────────────────────────
// 类型导出
// ─────────────────────────────────────────────

/** 单行输入框尺寸 */
export type InputSize = 'sm' | 'md' | 'lg';

/** 输入类型（控制键盘和输入行为） */
export type InputType = 'text' | 'password' | 'email' | 'phone' | 'number' | 'search';

// ─────────────────────────────────────────────
// 辅助函数
// ─────────────────────────────────────────────

/** 按尺寸决定输入区高度 */
function inputHeight(size: InputSize): number {
  switch (size) {
    case 'sm': return 36;
    case 'lg': return 52;
    default:   return 44;
  }
}

/** 按尺寸决定水平内边距 */
function inputPaddingH(size: InputSize): number {
  switch (size) {
    case 'sm': return Spacing.s3;
    case 'lg': return Spacing.s4;
    default:   return Spacing.s3;
  }
}

/** 按尺寸决定图标尺寸 */
function inputIconSize(size: InputSize): number {
  switch (size) {
    case 'sm': return 14;
    case 'lg': return 20;
    default:   return 17;
  }
}

/** 将 InputType 映射到 HarmonyOS InputType 枚举 */
function mapInputType(type: InputType): InputType {
  // ArkUI TextInput 直接用 type 属性映射到系统键盘
  // 这里保持原类型字符串，调用端按需使用
  return type;
}

/** 验证值，返回 null 表示通过，否则返回错误消息 */
function validate(
  value: string,
  pattern: RegExp | undefined,
  minLength: number | undefined,
  maxLength: number | undefined,
  customValidator: ((v: string) => string | null) | undefined,
): string | null {
  if (minLength !== undefined && value.length > 0 && value.length < minLength) {
    return `至少输入 ${minLength} 个字符`;
  }
  if (maxLength !== undefined && value.length > maxLength) {
    return `最多输入 ${maxLength} 个字符`;
  }
  if (pattern && value.length > 0 && !pattern.test(value)) {
    return '格式不正确';
  }
  if (customValidator) {
    return customValidator(value);
  }
  return null;
}

// ─────────────────────────────────────────────
// AppInput — 单行输入框
// ─────────────────────────────────────────────

/**
 * AppInput — 单行输入框
 *
 * 用法示例：
 *   AppInput({
 *     label: '邮箱',
 *     placeholder: '请输入邮箱',
 *     type: 'email',
 *     value: $email,
 *     onChange: (v) => { ... }
 *   })
 */
@Component
export struct AppInput {
  // ── 双向绑定 ──
  @Link value: string;

  // ── 外观 Props ──
  @Prop size: InputSize = 'md';
  @Prop type: InputType = 'text';
  @Prop label: string = '';
  @Prop placeholder: string = '';
  @Prop helperText: string = '';
  @Prop errorMessage: string = '';   // 外部传入错误信息（优先于内部校验）
  @Prop prefixIcon: Resource | undefined = undefined;
  @Prop suffixIcon: Resource | undefined = undefined;
  @Prop showClear: boolean = true;
  @Prop maxLength: number | undefined = undefined;
  @Prop minLength: number | undefined = undefined;
  @Prop pattern: RegExp | undefined = undefined;
  @Prop autoFocus: boolean = false;
  @Prop disabled: boolean = false;

  // ── 验证 ──
  customValidator?: (v: string) => string | null;

  // ── 事件 ──
  onChange?: (value: string) => void;
  onSubmit?: (value: string) => void;
  onFocus?: () => void;
  onBlur?: () => void;

  // ── 主题 ──
  @Consume('theme') theme: EffectiveTheme;

  // ── 内部状态 ──
  @State private focused: boolean = false;
  @State private showPassword: boolean = false;
  @State private internalError: string = '';

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  /** 最终错误（外部优先） */
  private get finalError(): string {
    return this.errorMessage.length > 0 ? this.errorMessage : this.internalError;
  }

  private get hasError(): boolean {
    return this.finalError.length > 0;
  }

  /** 边框颜色：error > focused > idle */
  private get borderColor(): ResourceColor {
    if (this.disabled) {
      return useColor(BorderColors.primary, this.isDark);
    }
    if (this.hasError) {
      return useColor(BorderColors.error, this.isDark);
    }
    if (this.focused) {
      return useColor(BorderColors.focus, this.isDark);
    }
    return useColor(BorderColors.primary, this.isDark);
  }

  private get borderWidth(): number {
    return (this.focused || this.hasError) ? 1.5 : 1;
  }

  private get bgColor(): ResourceColor {
    if (this.disabled) {
      return useColor(BgColors.tertiary, this.isDark);
    }
    return useColor(SurfaceColors.input, this.isDark);
  }

  /** 实际使用的 ArkUI InputType */
  private get arkInputType(): InputType {
    if (this.type === 'password' && !this.showPassword) {
      return 'password';
    }
    if (this.type === 'password' && this.showPassword) {
      return 'text';
    }
    return this.type;
  }

  /** 是否显示 clear 按钮 */
  private get showClearButton(): boolean {
    return this.showClear && this.focused && this.value.length > 0 && !this.disabled;
  }

  /** 是否显示密码切换按钮 */
  private get showPasswordToggle(): boolean {
    return this.type === 'password' && !this.disabled;
  }

  /** 运行验证并更新 internalError */
  private runValidation(): void {
    const err = validate(
      this.value,
      this.pattern,
      this.minLength,
      this.maxLength,
      this.customValidator,
    );
    this.internalError = err ?? '';
  }

  // ─── 标签行 ───
  @Builder
  private labelRow() {
    if (this.label.length > 0) {
      Row() {
        Text(this.label)
          .fontFamily(Typography.label.medium.fontFamily)
          .fontSize(Typography.label.medium.fontSize)
          .fontWeight(Typography.label.medium.fontWeight)
          .fontColor(
            this.disabled
              ? useColor(TextColors.disabled, this.isDark)
              : useColor(TextColors.primary, this.isDark)
          )
      }
      .width('100%')
      .margin({ bottom: Spacing.s1 })
    }
  }

  // ─── 辅助/错误文字行 ───
  @Builder
  private helperRow() {
    Row() {
      Text(this.hasError ? this.finalError : this.helperText)
        .fontFamily(CaptionStyle.fontFamily)
        .fontSize(CaptionStyle.fontSize)
        .fontWeight(CaptionStyle.fontWeight)
        .fontColor(
          this.hasError
            ? useColor(StateColors.error, this.isDark)
            : useColor(TextColors.tertiary, this.isDark)
        )
        .layoutWeight(1)

      // 字数统计
      if (this.maxLength !== undefined) {
        Text(`${this.value.length}/${this.maxLength}`)
          .fontFamily(CaptionStyle.fontFamily)
          .fontSize(CaptionStyle.fontSize)
          .fontColor(
            this.value.length > (this.maxLength ?? 99999)
              ? useColor(StateColors.error, this.isDark)
              : useColor(TextColors.tertiary, this.isDark)
          )
      }
    }
    .width('100%')
    .margin({ top: Spacing.s1 })
  }

  // ─── 前缀图标 ───
  @Builder
  private prefixView() {
    if (this.prefixIcon !== undefined) {
      Image(this.prefixIcon)
        .width(inputIconSize(this.size))
        .height(inputIconSize(this.size))
        .fillColor(
          this.focused
            ? useColor(AccentColors.primary, this.isDark)
            : useColor(TextColors.tertiary, this.isDark)
        )
        .margin({ right: Spacing.s2 })
        .objectFit(ImageFit.Contain)
    }
  }

  // ─── 后缀区：密码眼睛 / clear 按钮 / 自定义 suffix ───
  @Builder
  private suffixView() {
    Row({ space: Spacing.s1 }) {
      // clear 按钮
      if (this.showClearButton) {
        Text('✕')
          .fontSize(12)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
          .width(18)
          .height(18)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.value = '';
            this.onChange?.('');
            this.internalError = '';
          })
      }

      // 密码显示/隐藏切换
      if (this.showPasswordToggle) {
        Text(this.showPassword ? '隐' : '显')
          .fontSize(12)
          .fontColor(useColor(TextColors.secondary, this.isDark))
          .width(18)
          .height(18)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.showPassword = !this.showPassword;
          })
      }

      // 自定义 suffix 图标（不与 clear 共存时显示）
      if (this.suffixIcon !== undefined && !this.showClearButton) {
        Image(this.suffixIcon)
          .width(inputIconSize(this.size))
          .height(inputIconSize(this.size))
          .fillColor(useColor(TextColors.tertiary, this.isDark))
          .objectFit(ImageFit.Contain)
      }
    }
    .margin({ left: Spacing.s2 })
  }

  build() {
    Column({ space: 0 }) {
      // 标签
      this.labelRow()

      // 输入框容器
      Row() {
        // 前缀图标
        this.prefixView()

        // 文字输入
        TextInput({
          placeholder: this.placeholder,
          text: this.value,
        })
          .layoutWeight(1)
          .fontFamily(BodyStyles.medium.fontFamily)
          .fontSize(BodyStyles.medium.fontSize)
          .fontColor(
            this.disabled
              ? useColor(TextColors.disabled, this.isDark)
              : useColor(TextColors.primary, this.isDark)
          )
          .placeholderColor(useColor(TextColors.tertiary, this.isDark))
          .placeholderFont({ size: BodyStyles.medium.fontSize })
          .backgroundColor('transparent')
          .border({ width: 0 })
          .padding(0)
          .enabled(!this.disabled)
          .maxLength(this.maxLength ?? -1)
          .onChange((v: string) => {
            this.value = v;
            this.onChange?.(v);
            this.runValidation();
          })
          .onSubmit(() => {
            this.onSubmit?.(this.value);
          })
          .onFocus(() => {
            this.focused = true;
            this.onFocus?.();
          })
          .onBlur(() => {
            this.focused = false;
            this.runValidation();
            this.onBlur?.();
          })

        // 后缀区
        this.suffixView()
      }
      .height(inputHeight(this.size))
      .padding({ left: inputPaddingH(this.size), right: inputPaddingH(this.size) })
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.bgColor)
      .borderRadius(Radius.lg)
      .border({ width: this.borderWidth, color: this.borderColor })
      .animation({
        duration: MotionDuration.fast,
        curve: MotionEasing.standard,
      })

      // 辅助文字 / 错误信息 / 字数统计
      if (this.helperText.length > 0 || this.hasError || this.maxLength !== undefined) {
        this.helperRow()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// ─────────────────────────────────────────────
// AppTextArea — 多行输入框
// ─────────────────────────────────────────────

/**
 * AppTextArea — 多行输入框，自动增高，最大行数限制
 *
 * 用法示例：
 *   AppTextArea({
 *     label: '备注',
 *     placeholder: '请输入备注...',
 *     value: $content,
 *     maxRows: 6,
 *     maxLength: 200,
 *   })
 */
@Component
export struct AppTextArea {
  // ── 双向绑定 ──
  @Link value: string;

  // ── 外观 Props ──
  @Prop label: string = '';
  @Prop placeholder: string = '';
  @Prop helperText: string = '';
  @Prop errorMessage: string = '';
  @Prop maxLength: number | undefined = undefined;
  @Prop minLength: number | undefined = undefined;
  @Prop minRows: number = 3;       // 最小行数（决定初始高度）
  @Prop maxRows: number = 8;       // 最大行数（超出后滚动）
  @Prop disabled: boolean = false;

  // ── 验证 ──
  customValidator?: (v: string) => string | null;

  // ── 事件 ──
  onChange?: (value: string) => void;
  onFocus?: () => void;
  onBlur?: () => void;

  // ── 主题 ──
  @Consume('theme') theme: EffectiveTheme;

  // ── 内部状态 ──
  @State private focused: boolean = false;
  @State private internalError: string = '';

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  private get finalError(): string {
    return this.errorMessage.length > 0 ? this.errorMessage : this.internalError;
  }

  private get hasError(): boolean {
    return this.finalError.length > 0;
  }

  private get borderColor(): ResourceColor {
    if (this.disabled) return useColor(BorderColors.primary, this.isDark);
    if (this.hasError) return useColor(BorderColors.error, this.isDark);
    if (this.focused) return useColor(BorderColors.focus, this.isDark);
    return useColor(BorderColors.primary, this.isDark);
  }

  private get borderWidth(): number {
    return (this.focused || this.hasError) ? 1.5 : 1;
  }

  private get bgColor(): ResourceColor {
    if (this.disabled) return useColor(BgColors.tertiary, this.isDark);
    return useColor(SurfaceColors.input, this.isDark);
  }

  /** 最小高度 = minRows * 单行行高(22) + 垂直内边距(16*2) */
  private get minHeight(): number {
    return this.minRows * BodyStyles.medium.lineHeight + Spacing.s4 * 2;
  }

  /** 最大高度 */
  private get maxHeight(): number {
    return this.maxRows * BodyStyles.medium.lineHeight + Spacing.s4 * 2;
  }

  private runValidation(): void {
    const err = validate(
      this.value,
      undefined,
      this.minLength,
      this.maxLength,
      this.customValidator,
    );
    this.internalError = err ?? '';
  }

  // ─── 标签行 ───
  @Builder
  private labelRow() {
    if (this.label.length > 0) {
      Row() {
        Text(this.label)
          .fontFamily(Typography.label.medium.fontFamily)
          .fontSize(Typography.label.medium.fontSize)
          .fontWeight(Typography.label.medium.fontWeight)
          .fontColor(
            this.disabled
              ? useColor(TextColors.disabled, this.isDark)
              : useColor(TextColors.primary, this.isDark)
          )
      }
      .width('100%')
      .margin({ bottom: Spacing.s1 })
    }
  }

  // ─── 辅助/错误/字数统计行 ───
  @Builder
  private helperRow() {
    Row() {
      Text(this.hasError ? this.finalError : this.helperText)
        .fontFamily(CaptionStyle.fontFamily)
        .fontSize(CaptionStyle.fontSize)
        .fontColor(
          this.hasError
            ? useColor(StateColors.error, this.isDark)
            : useColor(TextColors.tertiary, this.isDark)
        )
        .layoutWeight(1)

      if (this.maxLength !== undefined) {
        Text(`${this.value.length}/${this.maxLength}`)
          .fontFamily(CaptionStyle.fontFamily)
          .fontSize(CaptionStyle.fontSize)
          .fontColor(
            this.value.length > (this.maxLength ?? 99999)
              ? useColor(StateColors.error, this.isDark)
              : useColor(TextColors.tertiary, this.isDark)
          )
      }
    }
    .width('100%')
    .margin({ top: Spacing.s1 })
  }

  build() {
    Column({ space: 0 }) {
      // 标签
      this.labelRow()

      // 多行输入容器
      TextArea({
        placeholder: this.placeholder,
        text: this.value,
      })
        .width('100%')
        .constraintSize({ minHeight: this.minHeight, maxHeight: this.maxHeight })
        .padding({ left: Spacing.s3, right: Spacing.s3, top: Spacing.s4, bottom: Spacing.s4 })
        .fontFamily(BodyStyles.medium.fontFamily)
        .fontSize(BodyStyles.medium.fontSize)
        .fontColor(
          this.disabled
            ? useColor(TextColors.disabled, this.isDark)
            : useColor(TextColors.primary, this.isDark)
        )
        .placeholderColor(useColor(TextColors.tertiary, this.isDark))
        .placeholderFont({ size: BodyStyles.medium.fontSize })
        .backgroundColor(this.bgColor)
        .borderRadius(Radius.lg)
        .border({ width: this.borderWidth, color: this.borderColor })
        .enabled(!this.disabled)
        .maxLength(this.maxLength ?? -1)
        .onChange((v: string) => {
          this.value = v;
          this.onChange?.(v);
          this.runValidation();
        })
        .onFocus(() => {
          this.focused = true;
          this.onFocus?.();
        })
        .onBlur(() => {
          this.focused = false;
          this.runValidation();
          this.onBlur?.();
        })
        .animation({
          duration: MotionDuration.fast,
          curve: MotionEasing.standard,
        })

      // 辅助文字行
      if (this.helperText.length > 0 || this.hasError || this.maxLength !== undefined) {
        this.helperRow()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// ─────────────────────────────────────────────
// @Preview — DevEco 内联预览
// ─────────────────────────────────────────────

@Preview
@Component
struct InputPreview {
  @Provide('theme') theme: EffectiveTheme = 'day';
  @State textVal: string = '';
  @State taVal: string = '';
  @State pwdVal: string = '';

  build() {
    Column({ space: Spacing.s5 }) {
      // 普通文本输入
      AppInput({
        label: '用户名',
        placeholder: '请输入用户名',
        helperText: '3-20 个字符',
        value: $textVal,
        minLength: 3,
        maxLength: 20,
      })

      // 密码输入
      AppInput({
        label: '密码',
        placeholder: '请输入密码',
        type: 'password',
        value: $pwdVal,
      })

      // 错误状态
      AppInput({
        label: '邮箱',
        placeholder: 'example@mail.com',
        type: 'email',
        errorMessage: '邮箱格式不正确',
        value: $textVal,
      })

      // 多行输入
      AppTextArea({
        label: '备注',
        placeholder: '请输入备注内容...',
        value: $taVal,
        maxLength: 200,
        minRows: 3,
        maxRows: 6,
      })
    }
    .padding(Spacing.s6)
    .backgroundColor('#F7F8FD')
  }
}
