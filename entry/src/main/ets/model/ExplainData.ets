/**
 * ExplainData — 划词/选句解释结构化数据
 *
 * 服务端 (server-cn) DeepSeek prompt 输出 JSON，客户端解析为该结构。
 * 与 W8-B (翻译) / W8-C (笔记 / 高亮) 共享，避免重复定义。
 */

/** 单个例句（英文 + 中文翻译） */
export interface ExplainExample {
  /** 英文原文 */
  en: string;
  /** 中文翻译 */
  zh: string;
}

/**
 * 划词解释数据
 *
 * 字段尽量保持向后兼容：旧版 explain prompt 仅返回 word/definition/exampleEn/exampleZh，
 * 新增字段（pronunciation/relatedWords/...）允许 undefined。
 */
export interface ExplainData {
  /** 单词或句子原文 */
  word: string;
  /** 国际音标（可选） */
  pronunciation?: string;
  /** 词性，如 'n.' / 'v.' / 'adj.' */
  partOfSpeech?: string;
  /** 主释义（中文） */
  definition: string;
  /** 中文翻译（与 definition 等价时可省略） */
  translation: string;
  /** 例句列表（1~3 条） */
  examples: ExplainExample[];
  /** 词源 / 扩展说明 */
  etymology?: string;
  /** 同义词 / 反义词 / 派生词 */
  relatedWords?: string[];
  /** CEFR 难度等级 */
  difficulty?: 'A1' | 'A2' | 'B1' | 'B2' | 'C1' | 'C2';
  /** 上下文句子（用于 prompt 构造，也回传以便保存到笔记） */
  context: string;
  /** 关联书籍 ID（可选，用于跨书统计 + 排重） */
  bookId?: string;
}

/**
 * 工具：从原始 SSE 累积文本解析 ExplainData。
 *
 * 容错：
 *  - 去掉 ```json``` fence、首尾空白
 *  - 找第一个 { 到最后一个 }
 *  - 缺失字段填默认值
 */
export function parseExplainData(raw: string, fallbackWord: string, fallbackContext: string): ExplainData | null {
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
    const definition = typeof obj.definition === 'string' ? obj.definition : '';
    if (definition.length === 0) return null;

    const examples: ExplainExample[] = [];
    // 兼容旧字段 exampleEn/exampleZh
    if (typeof obj.exampleEn === 'string' && (obj.exampleEn as string).length > 0) {
      examples.push({
        en: String(obj.exampleEn),
        zh: typeof obj.exampleZh === 'string' ? String(obj.exampleZh) : '',
      });
    }
    // 兼容新字段 examples: [{en,zh}]
    if (Array.isArray(obj.examples)) {
      for (const ex of obj.examples) {
        const e = ex as Record<string, unknown>;
        if (e && typeof e.en === 'string') {
          examples.push({
            en: String(e.en),
            zh: typeof e.zh === 'string' ? String(e.zh) : '',
          });
        }
      }
    }

    let related: string[] | undefined;
    if (Array.isArray(obj.relatedWords)) {
      related = obj.relatedWords.filter((w) => typeof w === 'string').map((w) => String(w));
    }

    const difficultyRaw = typeof obj.difficulty === 'string' ? String(obj.difficulty) : undefined;
    const difficulty = (difficultyRaw && /^(A1|A2|B1|B2|C1|C2)$/.test(difficultyRaw))
      ? (difficultyRaw as ExplainData['difficulty'])
      : undefined;

    return {
      word: typeof obj.word === 'string' && (obj.word as string).length > 0 ? String(obj.word) : fallbackWord,
      pronunciation: typeof obj.pronunciation === 'string' ? String(obj.pronunciation) : undefined,
      partOfSpeech: typeof obj.partOfSpeech === 'string' ? String(obj.partOfSpeech) : undefined,
      definition,
      translation: typeof obj.translation === 'string' ? String(obj.translation) : definition,
      examples,
      etymology: typeof obj.etymology === 'string' ? String(obj.etymology) : undefined,
      relatedWords: related,
      difficulty,
      context: typeof obj.context === 'string' ? String(obj.context) : fallbackContext,
      bookId: typeof obj.bookId === 'string' ? String(obj.bookId) : undefined,
    };
  } catch (_e) {
    return null;
  }
}
