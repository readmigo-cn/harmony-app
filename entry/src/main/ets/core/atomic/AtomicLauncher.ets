/**
 * AtomicLauncher
 *
 * 元服务（原子化服务）/ 卡片 → 主 App / 其他元服务的统一调度入口。
 *
 * 调用源：
 *   1. 服务卡片 postCardAction（MessageEvent / RouterEvent）→ buildCardLaunchWant
 *   2. 主 App 内启动元服务：launchLookup / launchShareWord / launchContinue
 *   3. 元服务内反向跳主 App（W11-C1 LookupPage「跳到完整阅读」按钮）
 *
 * W11-C4：扩展三个元服务调度方法
 *   - launchLookup(word, context?, fromBundle?)         → LookupAbility
 *   - launchShareWord(word, recipient?)                 → 单词分享元服务（W11-B2 占位）
 *   - launchContinue(bookId, chapterIndex, pageIndex)   → 阅读接续元服务（W11-B2 占位）
 */

import common from '@ohos.app.ability.common';
import Want from '@ohos.app.ability.Want';

export interface CardActionParams {
  /** 主 App 内目标路由 key（与 RouteConstants 对齐）。 */
  target: string;
  /** 路由参数，序列化到 want.parameters.params。 */
  params?: Record<string, string | number | boolean>;
  /** 来源 formId，便于埋点 / 跳转后回调更新卡片。 */
  formId?: string;
}

export class AtomicLauncher {
  // 主 App bundleName 与 AppScope/app.json5 保持一致
  private static readonly MAIN_BUNDLE: string = 'com.readmigo.harmony.cn';
  private static readonly MAIN_ABILITY: string = 'EntryAbility';

  // ---------- 卡片 → 主 App ----------

  /**
   * 卡片侧入口：postCardAction 触发时由 ExtensionAbility 转调。
   * 在 FormExtensionAbility 中没有 UIAbilityContext，因此实际启动应通过
   * postCardAction 的 Want 直接抛给系统，这里只组装 want。
   */
  static buildCardLaunchWant(action: CardActionParams): Want {
    const paramsObj: Record<string, string | number | boolean> = action.params ?? {};
    return {
      bundleName: AtomicLauncher.MAIN_BUNDLE,
      abilityName: AtomicLauncher.MAIN_ABILITY,
      parameters: {
        target: action.target,
        params: JSON.stringify(paramsObj),
        fromCardId: action.formId ?? '',
        fromCard: true,
      },
    };
  }

  /** 主 App 内主动启动其他 ability（占位，目前未使用）。 */
  static async launchFromCard(
    context: common.UIAbilityContext,
    action: CardActionParams,
  ): Promise<void> {
    const want = AtomicLauncher.buildCardLaunchWant(action);
    await context.startAbility(want);
  }

  // ---------- W11-C4：元服务调度 ----------

  /**
   * 拉起划词查询元服务（LookupAbility）。
   *
   * 用法：
   *   主 App 内长按选词 → AtomicLauncher.launchLookup(ctx, 'serendipity', '...')
   *   外部 App 集成接入 → fromBundle = '<source bundle>'，方便埋点 + 回包
   *
   * @param context 当前 UIAbilityContext（必须）
   * @param word 要查询的英文单词；空串会被拒绝
   * @param contextSentence 可选，所在句子，用于 LLM 个性化解释
   * @param fromBundle 可选，调用方 bundleName，便于回包匹配
   */
  static async launchLookup(
    context: common.UIAbilityContext,
    word: string,
    contextSentence?: string,
    fromBundle?: string,
  ): Promise<void> {
    if (!word || word.trim().length === 0) {
      throw new Error('launchLookup: word cannot be empty');
    }
    const want: Want = {
      bundleName: AtomicLauncher.MAIN_BUNDLE,
      abilityName: 'LookupAbility',
      parameters: {
        word: word.trim(),
        context: contextSentence ?? '',
        fromBundle: fromBundle ?? '',
      },
    };
    await context.startAbility(want);
  }

  /**
   * 拉起单词分享元服务 ShareWordAbility（W11-C2）。
   *
   * 启动流程：
   *   1. 划词得到 word + 上下文 → 走本方法
   *   2. ShareWordAbility 接 want → 渲染 ShareCardPage（独立窗口）
   *   3. 用户在卡片上选「分享 / 保存图片 / 复制 / 关闭」
   *
   * 后续：接入 @ohos.share.shareController 后，用户点「分享」可直接唤起系统分享面板。
   *
   * @param context     当前 UIAbilityContext
   * @param word        被分享的英文单词
   * @param contextSentence 上下文原句（可选）
   * @param meta        来源信息：bookTitle / chapterTitle / definition / phonetic / contextZh
   */
  static async launchShareWord(
    context: common.UIAbilityContext,
    word: string,
    contextSentence?: string,
    meta?: {
      bookTitle?: string;
      chapterTitle?: string;
      definition?: string;
      phonetic?: string;
      contextZh?: string;
    },
  ): Promise<void> {
    if (!word || word.trim().length === 0) {
      throw new Error('launchShareWord: word cannot be empty');
    }
    const want: Want = {
      bundleName: AtomicLauncher.MAIN_BUNDLE,
      abilityName: 'ShareWordAbility',
      uri: `readmigo://share-word?word=${encodeURIComponent(word.trim())}`,
      parameters: {
        word: word.trim(),
        context: contextSentence ?? '',
        contextZh: meta?.contextZh ?? '',
        definition: meta?.definition ?? '',
        phonetic: meta?.phonetic ?? '',
        bookTitle: meta?.bookTitle ?? '',
        chapterTitle: meta?.chapterTitle ?? '',
      },
    };
    await context.startAbility(want);
  }

  /**
   * 拉起阅读接续元服务 ContinueReadingAbility（W11-C3）。
   *
   * 流程：
   *   - 本地接续：本机 startAbility → ContinueReadingAbility（launchType=specified）
   *   - 跨端接续：由 ContinuationManager.transferTo(deviceId) 触发系统 onContinue
   *
   * Want 参数对齐 ContinueReadingAbility.parseParams：
   *   bookId / chapterIndex / pageIndex / percentComplete
   */
  static async launchContinue(
    context: common.UIAbilityContext,
    bookId: string,
    chapterIndex: number,
    pageIndex: number,
    percentComplete: number = 0,
  ): Promise<void> {
    if (!bookId) {
      throw new Error('launchContinue: bookId cannot be empty');
    }
    const want: Want = {
      bundleName: AtomicLauncher.MAIN_BUNDLE,
      abilityName: 'ContinueReadingAbility',
      uri: `readmigo://continue-reading?bookId=${encodeURIComponent(bookId)}&chapter=${chapterIndex}&page=${pageIndex}`,
      parameters: {
        bookId,
        chapterIndex,
        pageIndex,
        percentComplete,
      },
    };
    await context.startAbility(want);
  }

  /**
   * 元服务（LookupPage）→ 主 App EntryAbility「打开完整阅读」。
   * 携带 word 参数让主 App 自动定位到 Reader 并发起搜索。
   */
  static async launchMainAppFromAtomic(
    context: common.UIAbilityContext,
    word: string,
  ): Promise<void> {
    const want: Want = {
      bundleName: AtomicLauncher.MAIN_BUNDLE,
      abilityName: AtomicLauncher.MAIN_ABILITY,
      parameters: {
        target: 'reader',
        params: JSON.stringify({ searchWord: word }),
        fromAtomic: true,
      },
    };
    await context.startAbility(want);
  }
}
