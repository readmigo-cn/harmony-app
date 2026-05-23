/**
 * SensitiveWordList.ets — W16-C4 内置违禁词词典 + Trie 检索
 *
 * 职责：
 *   - 维护一份静态违禁词字典（约 50 条占位，覆盖政治/色情/暴力/广告四类）
 *   - 暴露 contains(text) / highlight(text) 两个查询接口
 *   - 内部使用 Trie 数据结构，O(N) 单次扫描即可命中所有词
 *
 * 为什么不直接 RegExp.test：
 *   - 词表规模 50+ 时正则编译成本高，且无法返回命中位置
 *   - Trie 同时支持「最长匹配」与「按顺序定位」，便于 highlight 时只染最少字符
 *
 * 词典策略：
 *   - 占位列表仅含「明显合规问题」示例词，真实运营词库由后台 API 下发覆盖
 *   - replaceList(words) 支持热替换（不重启 App）
 *   - HarmonyOS NEXT 上线前需切换到「网信办公开词库 + 后台增量」双源
 *
 * 类别：
 *   politics / sexual / violence / advertising
 *
 * 与 UgcModerator 的关系：
 *   UgcModerator 以本类为「第一道防线（本地）」，再叠加长度/字符/重复规则与后端 API
 */

const TAG = 'SensitiveWordList';

/** 违禁词类别 */
export type SensitiveCategory = 'politics' | 'sexual' | 'violence' | 'advertising' | 'other';

/** 命中信息 */
export interface SensitiveHit {
  /** 命中的词 */
  word: string;
  /** 在文本中的起始位置 */
  start: number;
  /** 在文本中的结束位置（不含） */
  end: number;
  /** 类别 */
  category: SensitiveCategory;
}

/** Trie 节点 */
interface TrieNode {
  children: Map<string, TrieNode>;
  end: boolean;
  category: SensitiveCategory;
}

function newNode(): TrieNode {
  return { children: new Map<string, TrieNode>(), end: false, category: 'other' };
}

/**
 * 占位违禁词字典（生产环境必须替换为运营后台下发的列表）。
 * 这里仅放「显然不该出现」的中性占位，避免在源码中保留真实违规字面量。
 */
const DEFAULT_WORDS: { word: string; category: SensitiveCategory }[] = [
  // politics（占位 — 真实词库下发）
  { word: '违禁政治词A', category: 'politics' },
  { word: '违禁政治词B', category: 'politics' },
  { word: '违禁政治词C', category: 'politics' },
  { word: '违禁政治词D', category: 'politics' },
  { word: '违禁政治词E', category: 'politics' },
  { word: '违禁政治词F', category: 'politics' },
  { word: '违禁政治词G', category: 'politics' },
  { word: '违禁政治词H', category: 'politics' },
  { word: '违禁政治词I', category: 'politics' },
  { word: '违禁政治词J', category: 'politics' },
  // sexual
  { word: '色情占位词A', category: 'sexual' },
  { word: '色情占位词B', category: 'sexual' },
  { word: '色情占位词C', category: 'sexual' },
  { word: '色情占位词D', category: 'sexual' },
  { word: '色情占位词E', category: 'sexual' },
  { word: '色情占位词F', category: 'sexual' },
  { word: '色情占位词G', category: 'sexual' },
  { word: '色情占位词H', category: 'sexual' },
  { word: '色情占位词I', category: 'sexual' },
  { word: '色情占位词J', category: 'sexual' },
  // violence
  { word: '暴力占位词A', category: 'violence' },
  { word: '暴力占位词B', category: 'violence' },
  { word: '暴力占位词C', category: 'violence' },
  { word: '暴力占位词D', category: 'violence' },
  { word: '暴力占位词E', category: 'violence' },
  { word: '暴力占位词F', category: 'violence' },
  { word: '暴力占位词G', category: 'violence' },
  { word: '暴力占位词H', category: 'violence' },
  { word: '暴力占位词I', category: 'violence' },
  { word: '暴力占位词J', category: 'violence' },
  // advertising / spam
  { word: '加微信', category: 'advertising' },
  { word: '加QQ', category: 'advertising' },
  { word: '私聊', category: 'advertising' },
  { word: '免费送', category: 'advertising' },
  { word: '点击链接', category: 'advertising' },
  { word: '扫码领取', category: 'advertising' },
  { word: '联系电话', category: 'advertising' },
  { word: '官网下载', category: 'advertising' },
  { word: '代购', category: 'advertising' },
  { word: '刷单', category: 'advertising' },
  { word: '赌博', category: 'advertising' },
  { word: '博彩', category: 'advertising' },
  { word: '六合彩', category: 'advertising' },
  // other（测试 fixture，方便 e2e 命中）
  { word: '测试敏感词', category: 'other' },
  { word: '违禁内容', category: 'other' },
  { word: '不良信息', category: 'other' },
];

export class SensitiveWordList {
  private static root: TrieNode = SensitiveWordList.buildRoot(DEFAULT_WORDS);

  /** 构建 Trie 根。可热替换 / 测试注入。 */
  private static buildRoot(items: { word: string; category: SensitiveCategory }[]): TrieNode {
    const root = newNode();
    for (const it of items) {
      const w = it.word.toLowerCase();
      if (w.length === 0) continue;
      let cur = root;
      for (let i = 0; i < w.length; i++) {
        const ch = w.charAt(i);
        let next = cur.children.get(ch);
        if (!next) {
          next = newNode();
          cur.children.set(ch, next);
        }
        cur = next;
      }
      cur.end = true;
      cur.category = it.category;
    }
    return root;
  }

  /** 热替换词表（运营后台下发后调用）。 */
  static replaceList(items: { word: string; category: SensitiveCategory }[]): void {
    SensitiveWordList.root = SensitiveWordList.buildRoot(items);
  }

  /** 当前内置词表大小（含默认 + 已热替换的）。 */
  static size(): number {
    let count = 0;
    const walk = (node: TrieNode): void => {
      if (node.end) count += 1;
      node.children.forEach((c) => walk(c));
    };
    walk(SensitiveWordList.root);
    return count;
  }

  /** 是否含任意命中。 */
  static contains(text: string): boolean {
    return SensitiveWordList.scan(text, true).length > 0;
  }

  /** 返回所有命中（按出现顺序，不去重）。 */
  static findAll(text: string): SensitiveHit[] {
    return SensitiveWordList.scan(text, false);
  }

  /**
   * 高亮文本：把命中部分用 [[ ]] 包起来。
   * UI 层可基于此再做染色 / 替换为 ***。
   */
  static highlight(text: string): string {
    const hits = SensitiveWordList.findAll(text);
    if (hits.length === 0) return text;
    let out = '';
    let cursor = 0;
    for (const h of hits) {
      if (h.start < cursor) continue; // 重叠取最左
      out += text.substring(cursor, h.start);
      out += '[[';
      out += text.substring(h.start, h.end);
      out += ']]';
      cursor = h.end;
    }
    out += text.substring(cursor);
    return out;
  }

  /** 替换命中部分为 maskChar（默认 '*'）。 */
  static mask(text: string, maskChar: string = '*'): string {
    const hits = SensitiveWordList.findAll(text);
    if (hits.length === 0) return text;
    const arr = text.split('');
    for (const h of hits) {
      for (let i = h.start; i < h.end; i++) arr[i] = maskChar;
    }
    return arr.join('');
  }

  /**
   * Trie 扫描（最长匹配优先）。
   * @param earlyExit 命中第一个就返回，用于 contains() 的快路径
   */
  private static scan(text: string, earlyExit: boolean): SensitiveHit[] {
    const hits: SensitiveHit[] = [];
    if (!text || text.length === 0) return hits;
    const lower = text.toLowerCase();
    const n = lower.length;
    for (let i = 0; i < n; i++) {
      let node: TrieNode | undefined = SensitiveWordList.root;
      let lastEnd = -1;
      let lastCategory: SensitiveCategory = 'other';
      for (let j = i; j < n && node; j++) {
        const ch = lower.charAt(j);
        node = node.children.get(ch);
        if (!node) break;
        if (node.end) {
          lastEnd = j + 1;
          lastCategory = node.category;
        }
      }
      if (lastEnd > i) {
        hits.push({
          word: text.substring(i, lastEnd),
          start: i,
          end: lastEnd,
          category: lastCategory,
        });
        if (earlyExit) return hits;
        i = lastEnd - 1; // 跳过已命中区间，避免子串重复匹配
      }
    }
    return hits;
  }
}
