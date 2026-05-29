/**
 * LookupAbility — 划词查询元服务（W11-C1）
 *
 * 元服务（Atomic Service，免安装）入口；以最小代价让用户在不打开主 App 的情况下
 * 查一个英文单词的释义、例句、词源，并可选保存到云端生词本。
 *
 * 三种入口（共用一个 UIAbility，singleton）：
 *   1. 主 App / 第三方 App 通过 startAbility 拉起
 *      want.parameters: { word: string, context?: string, bookId?: string }
 *   2. NFC 碰一碰：贴近一张 NDEF text-record 标签时系统派发
 *      action: ohos.nfc.tag.action.TAG_FOUND
 *      payload: 通过 NfcDecoder.decodeTextRecord(want) 提取 word
 *   3. 短链 readmigo://lookup?word=foo&context=bar
 *      action: ohos.want.action.viewData
 *      解析 want.uri 取 query
 *
 * 完成后通过 callerSendBackResult 回传保存结果给调用方（若是 startAbilityForResult）。
 *
 * 注意：元服务运行在与主 App 相同的 bundleName 下（同包），但不一定保证
 *   EntryAbility 已启动。所以本 ability 内部所有依赖 AppStorage 的逻辑都做 lazy 兜底。
 */

import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import common from '@ohos.app.ability.common';
import { decodeTextRecord, parseNdef } from '../core/atomic/NfcDecoder';
import tag from '@ohos.nfc.tag';
import { StoreKeys } from '../store/StoreKeys';

const TAG = 'LookupAbility';

/** AppStorage key：当前查询的词（LookupPage 监听） */
export const LOOKUP_CURRENT_WORD_KEY: string = 'atomic_lookup_word';
/** AppStorage key：当前查询的上下文（可选） */
export const LOOKUP_CURRENT_CONTEXT_KEY: string = 'atomic_lookup_context';
/** AppStorage key：来源 bundle，便于 callerSendBackResult */
export const LOOKUP_CURRENT_SOURCE_KEY: string = 'atomic_lookup_source';
/** AppStorage key：lookup 完成后的结果 payload（LookupPage 写入） */
export const LOOKUP_RESULT_KEY: string = 'atomic_lookup_result';

/** 解析后的 want 入参 */
interface LookupParams {
  word: string;
  context: string;
  bookId: string;
  source: 'main_app' | 'nfc' | 'deep_link' | 'unknown';
}

export default class LookupAbility extends UIAbility {
  private currentParams: LookupParams = {
    word: '',
    context: '',
    bookId: '',
    source: 'unknown',
  };

  // ---------- lifecycle ----------

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.currentParams = this.parseWant(want);
    this.publishToAppStorage();
    console.info(`${TAG} onCreate word="${this.currentParams.word}" source=${this.currentParams.source}`);
  }

  /**
   * 单例 hot 启动：用户在元服务页面没退出时再次拉起（NFC 碰一碰场景常见）。
   * 直接覆盖 AppStorage，让 LookupPage 监听到变化后重新发起查询。
   */
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    const next = this.parseWant(want);
    if (!next.word) {
      console.warn(`${TAG} onNewWant got empty word, ignored`);
      return;
    }
    this.currentParams = next;
    this.publishToAppStorage();
    console.info(`${TAG} onNewWant word="${next.word}" source=${next.source}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 直接渲染 LookupPage（main_pages.json 里的 atomic 页面）
    windowStage.loadContent('pages/atomic/LookupPage', (error) => {
      if (error.code) {
        console.error(`${TAG} loadContent failed: ${error.code} ${error.message}`);
      }
    });
  }

  onWindowStageDestroy(): void {
    // 离开 → 把缓存的 result 通过 caller 回传（若有）
    this.tryCallerSendBack();
  }

  onForeground(): void {
    console.info(`${TAG} onForeground`);
  }

  onBackground(): void {
    console.info(`${TAG} onBackground`);
  }

  onDestroy(): void {
    console.info(`${TAG} onDestroy`);
  }

  // ---------- want 解析 ----------

  /**
   * 把进入 ability 的 want 解析成 LookupParams。
   * 优先级：parameters.word > NFC NDEF > URI query
   */
  private parseWant(want: Want | undefined): LookupParams {
    const out: LookupParams = { word: '', context: '', bookId: '', source: 'unknown' };
    if (!want) return out;

    // 1) 主 App / 第三方 App 直接传 parameters
    if (want.parameters) {
      const params = want.parameters as Record<string, Object>;
      const w = params.word as string | undefined;
      if (w && w.length > 0) {
        out.word = w;
        out.context = (params.context as string) ?? '';
        out.bookId = (params.bookId as string) ?? '';
        out.source = 'main_app';
        return out;
      }
    }

    // 2) NFC TAG_FOUND：优先用 @ohos.nfc.tag.NdefTag 真实解析，fallback 到字节流解析
    if (want.action === 'ohos.nfc.tag.action.TAG_FOUND') {
      try {
        const ndefTag = tag.getNdef(want);
        if (ndefTag) {
          const result = parseNdef(ndefTag);
          if (result.word && result.word.length > 0) {
            out.word = result.word;
            out.context = result.context ?? '';
            out.source = 'nfc';
            return out;
          }
        }
      } catch (_e) { /* fallback below */ }
      // fallback：从 want.parameters bytes 解析
      const decoded = decodeTextRecord(want);
      if (decoded && decoded.length > 0) {
        out.word = decoded;
        out.source = 'nfc';
        return out;
      }
    }

    // 3) 短链 readmigo://lookup?word=foo&context=bar
    if (want.uri && want.uri.startsWith('readmigo://lookup')) {
      const parsed = this.parseLookupUri(want.uri);
      if (parsed.word.length > 0) {
        out.word = parsed.word;
        out.context = parsed.context;
        out.source = 'deep_link';
        return out;
      }
    }

    return out;
  }

  /**
   * 极简 query 解析（不依赖 url 模块；避免 polyfill）。
   * 仅识别 ?word=... 与 &context=...，对 URL-encoded 做 decodeURIComponent。
   */
  private parseLookupUri(uri: string): { word: string; context: string } {
    const out = { word: '', context: '' };
    const qIdx = uri.indexOf('?');
    if (qIdx < 0) return out;
    const query = uri.slice(qIdx + 1);
    const pairs = query.split('&');
    for (const p of pairs) {
      const eqIdx = p.indexOf('=');
      if (eqIdx < 0) continue;
      const k = p.slice(0, eqIdx);
      const v = p.slice(eqIdx + 1);
      try {
        if (k === 'word') out.word = decodeURIComponent(v);
        else if (k === 'context') out.context = decodeURIComponent(v);
      } catch (_e) {
        // 异常 query 直接忽略，让 LookupPage 显示「请输入要查询的单词」空态
      }
    }
    return out;
  }

  // ---------- AppStorage 桥 ----------

  private publishToAppStorage(): void {
    AppStorage.SetOrCreate<string>(LOOKUP_CURRENT_WORD_KEY, this.currentParams.word);
    AppStorage.SetOrCreate<string>(LOOKUP_CURRENT_CONTEXT_KEY, this.currentParams.context);
    AppStorage.SetOrCreate<string>(LOOKUP_CURRENT_SOURCE_KEY, this.currentParams.source);
    if (this.currentParams.bookId) {
      // 复用主 App 的 reading current book key，让 ExplainCard 能拿到 bookId 用于个性化
      AppStorage.SetOrCreate<string>(StoreKeys.READING_CURRENT_BOOK, this.currentParams.bookId);
    }
  }

  // ---------- 回传给调用方 ----------

  /**
   * 把保存到生词本的结果回传给调用方。
   * - 主 App 用 startAbilityForResult 拉起的话能收到
   * - NFC / 短链场景没有 caller，静默忽略即可
   *
   * 实际 IPC 见 @ohos.app.ability.UIAbility.context.terminateSelfWithResult
   */
  private async tryCallerSendBack(): Promise<void> {
    const result = AppStorage.Get<string>(LOOKUP_RESULT_KEY) ?? '';
    if (!result) return;
    try {
      const ctx = this.context as common.UIAbilityContext;
      const want: Want = {
        bundleName: 'com.readmigo.harmony.cn',
        parameters: {
          word: this.currentParams.word,
          result,
        },
      };
      // resultCode 0 表示成功；没有 caller 时该调用会在内部 noop
      await ctx.terminateSelfWithResult({ resultCode: 0, want });
    } catch (e) {
      console.warn(`${TAG} terminateSelfWithResult failed: ${(e as Error).message}`);
    } finally {
      // 清空，避免下次 cold 启动残留
      AppStorage.SetOrCreate<string>(LOOKUP_RESULT_KEY, '');
    }
  }
}
