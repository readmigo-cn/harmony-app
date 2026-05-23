import formProvider from '@ohos.app.form.formProvider';
import formBindingData from '@ohos.app.form.formBindingData';

/**
 * 万能卡片中心适配（W12-C4）。
 *
 * HarmonyOS 万能卡片中心（FormCenter）允许多个 form 注册到桌面/负一屏的统一卡片库；
 * 用户在卡片库浏览时，需要看到每张卡片的预览图与文案。本组件做：
 *
 *  1. 集中维护 widget 元数据（labelKey / descKey / preview / 默认 deeplink）
 *  2. 提供 onClick 时的 deeplink 路由参数（router push 到主 App）
 *  3. 暴露 createFormInstance() 帮助 EntryAbility 在用户从卡片中心拖拽出新卡时初始化
 *  4. 暴露 routePayloadFor(formName) 给主 App 解析点击 want.parameters
 *
 * 注意：preview 图片直接走 form_config.json 的 src 渲染（系统会自动截屏作为预览）；
 * 如果需要自定义预览，可在每张 card 同目录下放 *_preview.png，由系统在卡片中心展示。
 * 我们这里采用「component-based preview」策略——即让 build() 在无数据时
 * 用 fallback 占位渲染，系统截图即合格 preview，不需要额外 PNG 资源。
 */

// ---------- Types ----------

export interface WidgetFormMeta {
  /** 与 form_config.json forms[].name 对齐 */
  formName: string;
  /** Display label（i18n key） */
  labelKey: string;
  descKey: string;
  /** 默认尺寸 */
  defaultDimension: string;
  /** 支持的尺寸列表 */
  supportDimensions: string[];
  /** 点击卡片时跳转的主 App route name（NavPathStack） */
  defaultRoute: string;
  /** Component-based preview：是否依赖系统自动截屏作 preview */
  componentPreview: boolean;
  /** 备用：自定义 preview 资源 id（PNG/SVG），componentPreview=false 时使用 */
  previewResource?: string;
}

export interface WidgetClickPayload {
  /** 主 App NavPathStack push 的目标 route */
  route: string;
  /** 透传参数（bookId / prompt / etc） */
  params: Record<string, string>;
}

// ---------- Registry ----------

/**
 * 已注册卡片表。新增卡片时 form_config.json + 此表 + extensionAbilities 三处同步。
 */
export const WIDGET_REGISTRY: WidgetFormMeta[] = [
  {
    formName: 'DailyWordCard',
    labelKey: 'widget_daily_word_label',
    descKey: 'widget_daily_word_desc',
    defaultDimension: '2*2',
    supportDimensions: ['2*2', '2*4'],
    defaultRoute: 'Reader',
    componentPreview: true,
  },
  {
    formName: 'ReadingProgressCard',
    labelKey: 'widget_reading_progress_label',
    descKey: 'widget_reading_progress_desc',
    defaultDimension: '2*2',
    supportDimensions: ['1*2', '2*2', '2*4'],
    defaultRoute: 'Reader',
    componentPreview: true,
  },
  {
    formName: 'AiTipCard',
    labelKey: 'widget_ai_tip_label',
    descKey: 'widget_ai_tip_desc',
    defaultDimension: '2*2',
    supportDimensions: ['2*2', '2*4'],
    defaultRoute: 'ContentQA',
    componentPreview: true,
  },
];

// ---------- Adapter ----------

export class UniversalCardAdapter {
  /** 根据 formName 找元数据 */
  static getMeta(formName: string): WidgetFormMeta | null {
    for (const m of WIDGET_REGISTRY) {
      if (m.formName === formName) return m;
    }
    return null;
  }

  /** 注册到卡片中心需要的所有 form 名（供主 App 在启动时校验 form_config.json 一致性） */
  static getRegisteredFormNames(): string[] {
    return WIDGET_REGISTRY.map((m) => m.formName);
  }

  /**
   * 用户从卡片中心拖出一张新卡时由对应 ExtensionAbility.onAddForm 调用，
   * 返回一个安全的占位 binding（带尺寸信息），实际数据由 ability 异步拉取。
   */
  static createPlaceholderBinding(
    formName: string,
    dimension: string,
  ): formBindingData.FormBindingData {
    const meta = UniversalCardAdapter.getMeta(formName);
    return formBindingData.createFormBindingData({
      formName,
      formDimension: dimension || meta?.defaultDimension || '2*2',
    });
  }

  /**
   * 解析点击 want（postCardAction params）为统一的路由 payload。
   * EntryAbility.onWant / onCreate 收到 want 时调用本方法，避免每张卡片各写解析。
   */
  static parseClickPayload(wantParams: Record<string, string> | undefined): WidgetClickPayload | null {
    if (!wantParams) return null;
    const route = wantParams['route'];
    if (!route || route.length === 0) return null;
    const params: Record<string, string> = {};
    const keys = Object.keys(wantParams);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (k === 'route' || k === 'abilityName' || k === 'action') continue;
      params[k] = String(wantParams[k] ?? '');
    }
    return { route, params };
  }

  /**
   * 主动通知 form 更新（主 App 翻页 / 完成阅读后调用）。
   * 用于联动场景：用户在主 App 翻页 → form 同步进度。
   */
  static async pushUpdate(
    formId: string,
    data: Record<string, string | number | boolean>,
  ): Promise<void> {
    try {
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (err) {
      console.error(`UniversalCardAdapter.pushUpdate err: ${(err as Error).message}`);
    }
  }

  /**
   * Component-based preview 兜底数据：当 form 无网无数据时，
   * 让卡片渲染一份「示例」状态，系统截图作为卡片中心的预览图。
   */
  static fallbackPreviewData(formName: string): Record<string, string | number> {
    if (formName === 'ReadingProgressCard') {
      return {
        bookId: 'preview',
        bookTitle: '《小王子》',
        chapterTitle: '第三章 玫瑰',
        percentComplete: 42,
        currentChapterIndex: 2,
        totalReadMinutes: 320,
        todayMinutes: 18,
        streakDays: 7,
        recommendBookTitle: '《老人与海》',
        recommendBookId: 'preview-rec',
        lastReadAt: new Date().toISOString(),
      } as Record<string, string | number>;
    }
    if (formName === 'AiTipCard') {
      return {
        tip: '每天坚持阅读 15 分钟，一年可以读完 12 本书。',
        day: new Date().getDay(),
      } as Record<string, string | number>;
    }
    if (formName === 'DailyWordCard') {
      return {
        word: 'serendipity',
        partOfSpeech: 'noun',
        definition: '美好的偶然',
        exampleEn: 'Finding this café was pure serendipity.',
        exampleZh: '发现这家咖啡馆完全是美好的偶然。',
        date: new Date().toISOString().slice(0, 10),
      } as Record<string, string | number>;
    }
    return {};
  }
}
