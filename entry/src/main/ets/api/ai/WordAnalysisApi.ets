/**
 * WordAnalysisApi — 单词联想 / 词族分析（W9-C3 + C4）
 *
 * 服务端 /api/v1/ai/explain/word/stream 已支持词义解释，目前没有专门的 association /
 * family 端点。这里复用 explain 端点，通过自定义 prompt（嵌在 context 字段里）让
 * 模型按指定 JSON schema 返回结构化结果。后续若服务端落地专用 endpoint，只需替换
 * 内部实现，外层接口不变。
 *
 * 设计要点：
 *   - getAssociations(word, mode): 返回中心词 + 8 个关联词
 *   - getWordFamily(word):         返回词根 + 各词性派生词
 *   - 使用 AiApi.explainWordStream 收 SSE 累积文本，done 后 robust 解析 JSON
 *   - 缺字段 / JSON 解析失败 → 容错降级（返回空数组而非抛错）
 *   - 30 天内存 + Preferences 缓存（命中直接 resolve）
 */

import { AiApi, ExplainWordPayload } from './AiApi';
import { PreferencesManager } from '../../core/persistence/PreferencesManager';

// ---------------------------------------------------------------------------
// 类型
// ---------------------------------------------------------------------------

/** 单个关联词（mind-map 节点） */
export interface WordAssociation {
  /** 关联词词形 */
  word: string;
  /** 与 target 的关系：synonym / antonym / family / context / related */
  relation: 'synonym' | 'antonym' | 'family' | 'context' | 'related';
  /** 简短中文释义（< 24 字） */
  brief: string;
}

/** getAssociations 返回 */
export interface AssociationResult {
  target: string;
  associations: WordAssociation[];
}

/** 词族单项 */
export interface WordFamilyMember {
  word: string;
  /** 词性：noun / verb / adj / adv / other */
  partOfSpeech: 'noun' | 'verb' | 'adj' | 'adv' | 'other';
  /** 简短中文释义 */
  brief: string;
}

/** getWordFamily 返回 */
export interface WordFamilyResult {
  target: string;
  /** 词根，如 'cre-' */
  root: string;
  /** 词根来源（latin / greek / english / unknown） */
  rootOrigin: string;
  /** 词根含义中文 */
  rootMeaning: string;
  members: WordFamilyMember[];
}

/** 联想模式 */
export type AssociationMode = 'semantic' | 'phonetic' | 'thematic';

// ---------------------------------------------------------------------------
// 常量
// ---------------------------------------------------------------------------

const CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 天
const CACHE_PREFIX_ASSOC = 'word_assoc_v1:';
const CACHE_PREFIX_FAMILY = 'word_family_v1:';

interface CacheEntry<T> {
  at: number;
  data: T;
}

// ---------------------------------------------------------------------------
// Prompt 设计
// ---------------------------------------------------------------------------

function buildAssociationPrompt(word: string, mode: AssociationMode): string {
  const modeHint =
    mode === 'phonetic'
      ? '基于拼写或发音相近（同音异义词、形近词）'
      : mode === 'thematic'
        ? '基于使用场景或主题（同语境共现词）'
        : '基于语义关系（同义词、反义词、上下位词、词族派生）';
  return (
    `[ASSOCIATION_TASK] 围绕单词 "${word}" 生成 8 个关联词，关系类型：${modeHint}。` +
    `严格只返回 JSON，不要 markdown fence，不要解释。schema：` +
    `{"word":"${word}","definition":"<target 释义>","translation":"<中文翻译>",` +
    `"examples":[],"associations":[{"word":"<词形>","relation":"synonym|antonym|family|context|related","brief":"<≤24字中文释义>"}]}` +
    `必须返回恰好 8 条 associations。`
  );
}

function buildFamilyPrompt(word: string): string {
  return (
    `[FAMILY_TASK] 分析单词 "${word}" 的词族，返回词根和派生词。` +
    `严格只返回 JSON，不要 markdown fence。schema：` +
    `{"word":"${word}","definition":"<target 释义>","translation":"<中文翻译>","examples":[],` +
    `"family":{"root":"<词根，含连字符>","rootOrigin":"latin|greek|english|unknown",` +
    `"rootMeaning":"<词根中文含义>",` +
    `"members":[{"word":"<词形>","partOfSpeech":"noun|verb|adj|adv|other","brief":"<≤24字中文释义>"}]}}` +
    `members 至少 4 条，覆盖名词/动词/形容词/副词四种词性。`
  );
}

// ---------------------------------------------------------------------------
// JSON 解析：robust，从 SSE raw text 中抽取 JSON
// ---------------------------------------------------------------------------

function extractJsonObject(raw: string): Record<string, unknown> | null {
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
    return JSON.parse(s) as Record<string, unknown>;
  } catch (_e) {
    return null;
  }
}

function asString(v: unknown, def: string = ''): string {
  return typeof v === 'string' ? v : def;
}

function normalizeRelation(v: unknown): WordAssociation['relation'] {
  const s = asString(v, 'related');
  if (s === 'synonym' || s === 'antonym' || s === 'family' || s === 'context') return s;
  return 'related';
}

function normalizePos(v: unknown): WordFamilyMember['partOfSpeech'] {
  const s = asString(v, 'other');
  if (s === 'noun' || s === 'verb' || s === 'adj' || s === 'adv') return s;
  return 'other';
}

// ---------------------------------------------------------------------------
// WordAnalysisApi 主类
// ---------------------------------------------------------------------------

export class WordAnalysisApi {
  /** 调用底层 explain stream，累积全部 chunks 后 resolve raw text。 */
  private static collectStream(payload: ExplainWordPayload, timeoutMs: number = 25000): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      let buf = '';
      let done = false;
      const stop = AiApi.explainWordStream(payload, {
        onChunk: (delta: string) => { buf += delta; },
        onDone: () => {
          if (done) return;
          done = true;
          resolve(buf);
        },
        onError: (e: Error) => {
          if (done) return;
          done = true;
          reject(e);
        },
      });
      setTimeout(() => {
        if (done) return;
        done = true;
        try { stop(); } catch (_e) {}
        // 超时若已累积部分文本，仍尝试解析
        if (buf.length > 0) resolve(buf);
        else reject(new Error('请求超时'));
      }, timeoutMs);
    });
  }

  // ---- Associations ----

  static async getAssociations(word: string, mode: AssociationMode = 'semantic'): Promise<AssociationResult> {
    const trimmed = word.trim();
    if (!trimmed) return { target: word, associations: [] };

    const cacheKey = `${CACHE_PREFIX_ASSOC}${mode}:${trimmed.toLowerCase()}`;
    const cached = await WordAnalysisApi.readCache<AssociationResult>(cacheKey);
    if (cached) return cached;

    const payload: ExplainWordPayload = {
      word: trimmed,
      context: buildAssociationPrompt(trimmed, mode),
      locale: 'zh-CN',
      cefrLevel: 'B1',
    };

    let raw = '';
    try {
      raw = await WordAnalysisApi.collectStream(payload);
    } catch (e) {
      throw e as Error;
    }

    const result = WordAnalysisApi.parseAssociations(trimmed, raw);
    await WordAnalysisApi.writeCache(cacheKey, result);
    return result;
  }

  private static parseAssociations(target: string, raw: string): AssociationResult {
    const obj = extractJsonObject(raw);
    if (!obj) return { target, associations: [] };
    const arr = Array.isArray(obj.associations) ? obj.associations : [];
    const associations: WordAssociation[] = [];
    for (const item of arr) {
      const i = item as Record<string, unknown>;
      const w = asString(i?.word).trim();
      if (!w) continue;
      associations.push({
        word: w,
        relation: normalizeRelation(i?.relation),
        brief: asString(i?.brief),
      });
    }
    return { target, associations };
  }

  // ---- Word Family ----

  static async getWordFamily(word: string): Promise<WordFamilyResult> {
    const trimmed = word.trim();
    if (!trimmed) return WordAnalysisApi.emptyFamily(word);

    const cacheKey = `${CACHE_PREFIX_FAMILY}${trimmed.toLowerCase()}`;
    const cached = await WordAnalysisApi.readCache<WordFamilyResult>(cacheKey);
    if (cached) return cached;

    const payload: ExplainWordPayload = {
      word: trimmed,
      context: buildFamilyPrompt(trimmed),
      locale: 'zh-CN',
      cefrLevel: 'B1',
    };

    const raw = await WordAnalysisApi.collectStream(payload);
    const result = WordAnalysisApi.parseFamily(trimmed, raw);
    await WordAnalysisApi.writeCache(cacheKey, result);
    return result;
  }

  private static parseFamily(target: string, raw: string): WordFamilyResult {
    const obj = extractJsonObject(raw);
    if (!obj) return WordAnalysisApi.emptyFamily(target);
    const fam = (obj.family ?? {}) as Record<string, unknown>;
    const arr = Array.isArray(fam.members) ? fam.members : [];
    const members: WordFamilyMember[] = [];
    for (const item of arr) {
      const i = item as Record<string, unknown>;
      const w = asString(i?.word).trim();
      if (!w) continue;
      members.push({
        word: w,
        partOfSpeech: normalizePos(i?.partOfSpeech),
        brief: asString(i?.brief),
      });
    }
    return {
      target,
      root: asString(fam.root, '-'),
      rootOrigin: asString(fam.rootOrigin, 'unknown'),
      rootMeaning: asString(fam.rootMeaning),
      members,
    };
  }

  private static emptyFamily(target: string): WordFamilyResult {
    return { target, root: '-', rootOrigin: 'unknown', rootMeaning: '', members: [] };
  }

  // ---- 缓存 ----

  private static async readCache<T>(key: string): Promise<T | null> {
    try {
      const raw = await PreferencesManager.getString(key, '');
      if (!raw) return null;
      const entry = JSON.parse(raw) as CacheEntry<T>;
      if (!entry || typeof entry.at !== 'number') return null;
      if (Date.now() - entry.at > CACHE_TTL_MS) return null;
      return entry.data ?? null;
    } catch (_e) {
      return null;
    }
  }

  private static async writeCache<T>(key: string, data: T): Promise<void> {
    try {
      const entry: CacheEntry<T> = { at: Date.now(), data };
      await PreferencesManager.setString(key, JSON.stringify(entry));
    } catch (_e) {
      // 缓存失败不阻塞主流程
    }
  }
}
