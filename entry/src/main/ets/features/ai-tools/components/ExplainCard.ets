/**
 * ExplainCard — 划词/选句解释卡片（W8-C1 / C2 / C3 主入口 UI）
 *
 * 职责：
 *   - 接收 word + context（必传），mode（word | sentence），variant（compact | expanded）
 *   - 内部启动 SSE 流（AiApi.explainWordStream），@State 累积 chunks
 *   - 流式增量渲染：raw 文本（流中）→ 解析后结构化卡片（done）
 *   - 三态切换：skeleton (初始) / streaming (raw + 累积 indicator) / structured (done)
 *   - 错误态：底部 retry 按钮 + 错误文案
 *   - 底部 action bar：保存到生词本 / 再生成 / 分享 / 关闭
 *
 * 与外界的契约：
 *   - 父组件传 word + context 即可启动；无需先调 API
 *   - onSaveToVocab(data) 由父组件接管持久化（避免本卡片直接依赖 NoteRepository）
 *   - onClose 由父组件控制关闭（关闭 sheet / dialog）
 */

import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { AiApi, ExplainWordPayload } from '../../../api/ai/AiApi';
import { ExplainData, ExplainExample, parseExplainData } from '../../../model/ExplainData';
import { SettingsStore } from '../../../store/SettingsStore';
import { AiContentBadge } from './AiContentBadge';

/** 旧 StructuredExplain 兼容（WordExplainSheet 仍在用 parseExplainJson） */
export interface StructuredExplain {
  word: string;
  partOfSpeech?: string;
  definition: string;
  exampleEn?: string;
  exampleZh?: string;
  etymology?: string;
}

/**
 * 兼容旧解析函数（WordExplainSheet 在用）；本组件内部已迁到 parseExplainData。
 */
export function parseExplainJson(raw: string): StructuredExplain | null {
  if (!raw) return null;
  let s = raw.trim();
  if (s.startsWith('```')) {
    s = s.replace(/^```(?:json)?\s*/, '').replace(/```\s*$/, '').trim();
  }
  const first = s.indexOf('{');
  const last = s.lastIndexOf('}');
  if (first < 0 || last <= first) return null;
  s = s.slice(first, last + 1);
  try {
    const obj = JSON.parse(s) as Record<string, unknown>;
    if (typeof obj.error === 'string') return null;
    if (typeof obj.definition !== 'string' || (obj.definition as string).length === 0) return null;
    return {
      word: String(obj.word ?? ''),
      partOfSpeech: obj.partOfSpeech ? String(obj.partOfSpeech) : undefined,
      definition: String(obj.definition),
      exampleEn: obj.exampleEn ? String(obj.exampleEn) : undefined,
      exampleZh: obj.exampleZh ? String(obj.exampleZh) : undefined,
      etymology: obj.etymology ? String(obj.etymology) : undefined,
    };
  } catch (_e) {
    return null;
  }
}

@Component
export struct ExplainCard {
  // ---- 兼容旧 API（WordExplainSheet 在用）-------------------------------
  /**
   * 老路径：父组件已自己 stream 完且解析好 → 直接传 data 用。
   * 新路径：父组件不传 data，传 word + context，本组件内部 stream。
   */
  data?: StructuredExplain;

  // ---- 必传 props（新 API）---------------------------------------------
  @Prop word: string = '';
  @Prop context: string = '';

  // ---- 可选 props -------------------------------------------------------
  @Prop bookId: string = '';
  @Prop level: string = 'B1';
  /** 'word' 单词解释 / 'sentence' 整句解释 */
  @Prop mode: string = 'word';
  /** 'compact' 嵌入式（无 padding/标题）/ 'expanded' 完整（默认） */
  @Prop variant: string = 'expanded';

  // ---- 回调 -------------------------------------------------------------
  onSaveToVocab?: (data: ExplainData) => void;
  onClose?: () => void;
  onShare?: (data: ExplainData) => void;
  onTtsRead?: (text: string) => void;

  // ---- 内部状态 ---------------------------------------------------------
  /** 累积的 SSE 原始文本（流式增量更新） */
  @State private streamedText: string = '';
  /** 是否正在流式接收 */
  @State private streaming: boolean = true;
  /** 错误信息（非空表示错误态） */
  @State private errMsg: string = '';
  /** 解析后的结构化数据（done 后填充） */
  @State private parsed: ExplainData | null = null;
  /** 是否已保存（onSaveToVocab 回调成功后置 true） */
  @State private saved: boolean = false;

  /** SSE 取消函数 */
  private stopFn: (() => void) | null = null;

  /** 是否走兼容路径（外部已传 data） */
  private get isLegacyMode(): boolean {
    return this.data !== undefined && this.data !== null;
  }

  // ---------- lifecycle ----------

  aboutToAppear(): void {
    if (this.isLegacyMode && this.data) {
      // 老 API：把外部的 StructuredExplain 转成 ExplainData
      this.parsed = {
        word: this.data.word,
        partOfSpeech: this.data.partOfSpeech,
        definition: this.data.definition,
        translation: this.data.definition,
        examples: (this.data.exampleEn && this.data.exampleEn.length > 0) ? [{
          en: this.data.exampleEn,
          zh: this.data.exampleZh ?? '',
        }] : [],
        etymology: this.data.etymology,
        context: '',
      };
      this.streaming = false;
      return;
    }
    if (this.word && this.word.length > 0) {
      this.startStream();
    }
  }

  aboutToDisappear(): void {
    this.stopFn?.();
    this.stopFn = null;
  }

  // ---------- stream 控制 ----------

  /**
   * 启动 SSE 流。
   * 重试时复用此函数（先重置状态再 start）。
   */
  private startStream(): void {
    this.streamedText = '';
    this.errMsg = '';
    this.streaming = true;
    this.parsed = null;
    this.saved = false;

    // 把 SettingsStore 的 'en-US' 归一成 'en'，匹配后端枚举
    const rawLocale = SettingsStore.getLocale();
    const locale: 'zh-CN' | 'zh-TW' | 'en' = rawLocale === 'zh-CN'
      ? 'zh-CN'
      : rawLocale === 'zh-TW'
        ? 'zh-TW'
        : 'en';

    const payload: ExplainWordPayload = {
      word: this.word,
      context: this.context,
      locale,
      cefrLevel: this.level as ('A1' | 'A2' | 'B1' | 'B2' | 'C1' | 'C2'),
      bookId: this.bookId.length > 0 ? this.bookId : undefined,
    };

    // W11 Critical 修复：watchdog timeout — 45s 内无任何 chunk 视为 stalled，切错误态
    // 同时 onDone 后清理 timer，避免误触发
    let watchdog: number = -1;
    const armWatchdog = (): void => {
      if (watchdog !== -1) clearTimeout(watchdog);
      watchdog = setTimeout(() => {
        if (!this.streaming) return;
        this.streaming = false;
        // 已有部分解析则仍展示，否则提示超时
        if (!this.parsed) {
          this.errMsg = '响应超时，请重试';
        }
        this.stopFn?.();
        this.stopFn = null;
      }, 45000) as unknown as number;
    };
    const clearWatchdog = (): void => {
      if (watchdog !== -1) {
        clearTimeout(watchdog);
        watchdog = -1;
      }
    };

    armWatchdog();

    this.stopFn = AiApi.explainWordStream(payload, {
      onChunk: (delta: string) => {
        if (!this.streaming) return; // 防 watchdog 触发后的延迟 chunk
        this.streamedText += delta;
        armWatchdog(); // 收到 chunk 重置看门狗
        // 边收边尝试解析（很多场景 JSON 在 done 前已闭合）
        try {
          const partial = parseExplainData(this.streamedText, this.word, this.context);
          if (partial) this.parsed = partial;
        } catch (e) {
          // 解析异常不影响流，等下个 chunk 重试
        }
      },
      onDone: () => {
        clearWatchdog();
        this.streaming = false;
        try {
          const final = parseExplainData(this.streamedText, this.word, this.context);
          if (final) {
            this.parsed = final;
          } else if (!this.parsed) {
            // 解析失败且无 partial：切错误态，让用户能 retry
            this.errMsg = '解析失败，请重试';
          }
        } catch (e) {
          if (!this.parsed) {
            this.errMsg = '解析失败，请重试';
          }
        }
      },
      onError: (e: Error) => {
        clearWatchdog();
        this.streaming = false;
        this.errMsg = e.message ?? '请求失败';
      },
    });
  }

  // ---------- 操作 ----------

  private handleSave(): void {
    if (this.saved || !this.parsed) return;
    this.onSaveToVocab?.(this.parsed);
    this.saved = true;
  }

  private handleRetry(): void {
    this.stopFn?.();
    this.stopFn = null;
    this.startStream();
  }

  private handleClose(): void {
    this.stopFn?.();
    this.stopFn = null;
    this.onClose?.();
  }

  // ---------- 子构造器 ----------

  /** Header：词头 + 音标 + 词性 + 朗读 */
  @Builder
  header() {
    Row({ space: AppSpacing.sm }) {
      Text(this.parsed?.word ?? this.word)
        .fontSize(AppFontSize.xl)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
      if (this.parsed?.pronunciation) {
        Text(`/${this.parsed.pronunciation}/`)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textTertiary)
      }
      if (this.parsed?.partOfSpeech) {
        Text(this.parsed.partOfSpeech)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.brand)
          .padding({ left: AppSpacing.xs, right: AppSpacing.xs, top: 2, bottom: 2 })
          .borderRadius(AppRadius.sm)
          .backgroundColor('#EDE9FE')
      }
      if (this.parsed?.difficulty) {
        Text(this.parsed.difficulty)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textInverse)
          .padding({ left: AppSpacing.xs, right: AppSpacing.xs, top: 2, bottom: 2 })
          .borderRadius(AppRadius.sm)
          .backgroundColor(AppColors.brand)
      }
      Blank()
      Text('🔊')
        .fontSize(AppFontSize.md)
        .padding(AppSpacing.xs)
        .onClick(() => this.onTtsRead?.(this.parsed?.word ?? this.word))
    }
    .width('100%')
  }

  /** Section header（小标签：「释义」/「翻译」） */
  @Builder
  sectionLabel(label: string) {
    Text(label)
      .fontSize(AppFontSize.xs)
      .fontColor(AppColors.textTertiary)
      .fontWeight(AppFontWeight.medium)
  }

  /** Definition + Translation block */
  @Builder
  definitionBlock() {
    if (this.parsed) {
      Column({ space: AppSpacing.xs }) {
        this.sectionLabel('释义');
        Text(this.parsed.definition)
          .fontSize(AppFontSize.base)
          .fontColor(AppColors.textPrimary)
          .lineHeight(22)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      if (this.parsed.translation && this.parsed.translation.length > 0 && this.parsed.translation !== this.parsed.definition) {
        Column({ space: AppSpacing.xs }) {
          this.sectionLabel('翻译');
          Text(this.parsed.translation)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textSecondary)
            .lineHeight(20)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
    }
  }

  /** Examples block（最多渲染 3 条） */
  @Builder
  examplesBlock() {
    if (this.parsed && this.parsed.examples && this.parsed.examples.length > 0) {
      Column({ space: AppSpacing.xs }) {
        this.sectionLabel('例句');
        ForEach(
          this.parsed.examples.slice(0, 3),
          (ex: ExplainExample) => {
            Column({ space: 2 }) {
              Text(ex.en)
                .fontSize(AppFontSize.sm)
                .fontStyle(FontStyle.Italic)
                .fontColor(AppColors.textPrimary)
                .lineHeight(20)
              if (ex.zh && ex.zh.length > 0) {
                Text(ex.zh)
                  .fontSize(AppFontSize.sm)
                  .fontColor(AppColors.textSecondary)
                  .lineHeight(20)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(AppSpacing.sm)
            .backgroundColor(AppColors.bgSecondary)
            .borderRadius(AppRadius.base)
            .margin({ bottom: AppSpacing.xs })
          },
          (ex: ExplainExample, idx: number) => `${idx}-${ex.en}`,
        )
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  /** Etymology block */
  @Builder
  etymologyBlock() {
    if (this.parsed && this.parsed.etymology && this.parsed.etymology.length > 0) {
      Column({ space: AppSpacing.xs }) {
        this.sectionLabel('词源 / 扩展');
        Text(this.parsed.etymology)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textSecondary)
          .lineHeight(20)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  /** Related words block（同义词 / 反义词，flow chip） */
  @Builder
  relatedBlock() {
    if (this.parsed && this.parsed.relatedWords && this.parsed.relatedWords.length > 0) {
      Column({ space: AppSpacing.xs }) {
        this.sectionLabel('相关词');
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(
            this.parsed.relatedWords,
            (w: string) => {
              Text(w)
                .fontSize(AppFontSize.xs)
                .fontColor(AppColors.brand)
                .padding({ left: AppSpacing.xs, right: AppSpacing.xs, top: 2, bottom: 2 })
                .borderRadius(AppRadius.sm)
                .backgroundColor('#F5F3FF')
                .margin({ right: AppSpacing.xs, bottom: AppSpacing.xs })
            },
            (w: string) => w,
          )
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  /** Skeleton 占位（initial loading，无任何流式内容时） */
  @Builder
  skeleton() {
    Column({ space: AppSpacing.sm }) {
      Row()
        .width('40%').height(20)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.sm)
      Row()
        .width('100%').height(14)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.sm)
      Row()
        .width('90%').height(14)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.sm)
      Row()
        .width('60%').height(14)
        .backgroundColor(AppColors.bgSecondary)
        .borderRadius(AppRadius.sm)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm })
  }

  /** 错误态 */
  @Builder
  errorView() {
    Column({ space: AppSpacing.sm }) {
      Text('解释失败')
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.danger)
      Text(this.errMsg)
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textTertiary)
        .maxLines(3)
      Button('重试')
        .height(36)
        .backgroundColor(AppColors.brand)
        .fontColor(AppColors.textInverse)
        .borderRadius(AppRadius.base)
        .onClick(() => this.handleRetry())
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpacing.sm)
  }

  /** 底部 action bar */
  @Builder
  actionBar() {
    Row({ space: AppSpacing.sm }) {
      Button(this.saved ? '已保存' : '保存到生词本')
        .layoutWeight(1)
        .height(40)
        .backgroundColor(this.saved ? AppColors.bgSecondary : AppColors.brand)
        .fontColor(this.saved ? AppColors.textSecondary : AppColors.textInverse)
        .borderRadius(AppRadius.base)
        .enabled(!this.streaming && !this.saved && this.parsed !== null && !this.errMsg)
        .onClick(() => this.handleSave())

      Button('再生成')
        .height(40)
        .padding({ left: AppSpacing.sm, right: AppSpacing.sm })
        .backgroundColor(AppColors.bgSecondary)
        .fontColor(AppColors.textPrimary)
        .borderRadius(AppRadius.base)
        .onClick(() => this.handleRetry())

      Button('关闭')
        .height(40)
        .padding({ left: AppSpacing.sm, right: AppSpacing.sm })
        .backgroundColor(AppColors.bgSecondary)
        .fontColor(AppColors.textPrimary)
        .borderRadius(AppRadius.base)
        .onClick(() => this.handleClose())
    }
    .width('100%')
  }

  // ---------- build ----------

  build() {
    Column({ space: AppSpacing.base }) {
      // W16-C2 合规：标题区顶部插入「AI 生成」徽章（compact 模式不渲染，避免破坏嵌入式布局）
      if (this.variant !== 'compact') {
        AiContentBadge({ mode: 'prefix', label: '词义解释', showLearnMore: false });
      }
      // Header（compact 模式 / legacy 模式不显示 header）
      if (this.variant !== 'compact' && !this.isLegacyMode) {
        this.header();
        if (this.context && this.context.length > 0) {
          Text(this.context)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.textTertiary)
            .fontStyle(FontStyle.Italic)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        Divider().color(AppColors.divider)
      }

      // 内容区：错误 → 结构化 → raw streamed → skeleton
      if (this.errMsg) {
        this.errorView();
      } else if (this.parsed) {
        Column({ space: AppSpacing.base }) {
          this.definitionBlock();
          this.examplesBlock();
          this.etymologyBlock();
          this.relatedBlock();
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      } else if (this.streamedText.length > 0) {
        // streaming 中但还没解析出 JSON：直接展示原始 chunks
        Column({ space: AppSpacing.xs }) {
          Text(this.streamedText)
            .fontSize(AppFontSize.base)
            .fontColor(AppColors.textPrimary)
            .lineHeight(22)
            .width('100%')
          if (this.streaming) {
            LoadingProgress()
              .width(16).height(16).color(AppColors.brand)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      } else {
        // 初始空 → skeleton
        this.skeleton();
      }

      // expanded 模式才显示底部 action bar；legacy 模式由父组件提供 action
      if (this.variant !== 'compact' && !this.isLegacyMode) {
        Divider().color(AppColors.divider)
        this.actionBar();
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding((this.variant === 'compact' || this.isLegacyMode) ? 0 : AppSpacing.base)
  }
}
