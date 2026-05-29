/**
 * PromptTemplates.ets — L2 pure prompt-building functions (no ArkUI, no network).
 *
 * All functions return a ready-to-send prompt string.
 * Structured-output features (explain / weakness / question) append a JSON schema
 * instruction so the model responds in valid JSON.
 * Plain-text features (translate / summarize) do not.
 */

// ---------------------------------------------------------------------------
// Explain word
// ---------------------------------------------------------------------------

export interface ExplainWordParams {
  word: string;
  contextSentence: string;
  targetLanguage: 'zh-CN' | 'en';
}

export function explainWord(p: ExplainWordParams): string {
  if (p.targetLanguage === 'zh-CN') {
    return (
      `你是一位英语词汇专家，请解释单词 "${p.word}"。\n` +
      `上下文句子：${p.contextSentence}\n\n` +
      `要求：严格只返回 JSON，不要 markdown code fence，不要任何额外说明。\n` +
      `JSON schema：\n` +
      `{"word":"string","phonetic":"string","partOfSpeech":"string",` +
      `"definition":"string","contextMeaning":"string",` +
      `"exampleEn":"string","exampleZh":"string","etymology":"string"}`
    );
  }
  return (
    `You are a vocabulary expert. Explain the word "${p.word}".\n` +
    `Context sentence: ${p.contextSentence}\n\n` +
    `Respond ONLY with valid JSON. No markdown fences, no extra text.\n` +
    `JSON schema:\n` +
    `{"word":"string","phonetic":"string","partOfSpeech":"string",` +
    `"definition":"string","contextMeaning":"string",` +
    `"exampleEn":"string","exampleZh":"string","etymology":"string"}`
  );
}

// ---------------------------------------------------------------------------
// Translate sentence
// ---------------------------------------------------------------------------

export interface TranslateSentenceParams {
  sentence: string;
  sourceLanguage: 'en' | 'zh' | 'auto';
  targetLanguage: 'zh-CN' | 'en';
}

export function translateSentence(p: TranslateSentenceParams): string {
  if (p.targetLanguage === 'zh-CN') {
    const fromHint = p.sourceLanguage === 'auto' ? '自动识别源语言' : `源语言为 ${p.sourceLanguage}`;
    return (
      `你是一位专业翻译，${fromHint}，将以下内容翻译为流畅自然的中文。\n` +
      `只输出译文，不要解释，不要多余文字。\n\n` +
      `原文：${p.sentence}`
    );
  }
  const fromHint = p.sourceLanguage === 'auto' ? 'auto-detect source language' : `source language: ${p.sourceLanguage}`;
  return (
    `You are a professional translator. ${fromHint}. Translate the following into natural English.\n` +
    `Output only the translation, no explanations, no extra text.\n\n` +
    `Source: ${p.sentence}`
  );
}

// ---------------------------------------------------------------------------
// Summarize chapter
// ---------------------------------------------------------------------------

export interface SummarizeChapterParams {
  chapterText: string;
  targetLanguage: 'zh-CN' | 'en';
}

export function summarizeChapter(p: SummarizeChapterParams): string {
  const maxLen = 6000;
  const text = p.chapterText.length > maxLen
    ? p.chapterText.slice(0, maxLen) + '…（已截断）'
    : p.chapterText;

  if (p.targetLanguage === 'zh-CN') {
    return (
      `你是一位阅读助手，请用 3-5 句话总结以下章节的主要内容，使用简洁的中文。\n` +
      `只输出摘要，不要标题，不要列表，不要额外说明。\n\n` +
      `章节内容：\n${text}`
    );
  }
  return (
    `You are a reading assistant. Summarize the following chapter in 3-5 concise English sentences.\n` +
    `Output only the summary. No headings, no lists, no extra text.\n\n` +
    `Chapter text:\n${text}`
  );
}

// ---------------------------------------------------------------------------
// Analyze weakness
// ---------------------------------------------------------------------------

export interface AnalyzeWeaknessParams {
  /** Recent lookup history: array of {word, failCount, totalCount} */
  lookupHistory: Array<{ word: string; failCount: number; totalCount: number }>;
  /** Reading stats per topic: array of {topic, accuracy} */
  readingHistory: Array<{ topic: string; accuracy: number }>;
}

export function analyzeWeakness(p: AnalyzeWeaknessParams): string {
  const lookupSummary = p.lookupHistory
    .slice(0, 30)
    .map((w) => `${w.word}(${w.failCount}/${w.totalCount})`)
    .join(', ');
  const readingSummary = p.readingHistory
    .slice(0, 10)
    .map((r) => `${r.topic}:${Math.round(r.accuracy * 100)}%`)
    .join(', ');

  return (
    `你是一位英语学习分析师。根据以下学习数据生成个性化弱点报告。\n\n` +
    `查词记录（词 错误次数/总次数）：${lookupSummary}\n` +
    `阅读主题准确率：${readingSummary}\n\n` +
    `要求：严格只返回 JSON，不要 markdown code fence，不要任何额外说明。\n` +
    `JSON schema：\n` +
    `{"summary":"string",` +
    `"weakWords":[{"word":"string","failureCount":0,"reviewCount":0,"avgQuality":0}],` +
    `"weakPos":[{"pos":"noun|verb|adj|adv|prep|conj|pron","accuracy":0}],` +
    `"weakTopics":[{"topic":"string","wordCount":0,"accuracy":0}],` +
    `"recommendations":["string"]}`
  );
}

// ---------------------------------------------------------------------------
// Generate question
// ---------------------------------------------------------------------------

export interface GenerateQuestionParams {
  chapterText: string;
  difficulty: 'easy' | 'medium' | 'hard';
  type: 'mcq' | 'fill' | 'short';
}

export function generateQuestion(p: GenerateQuestionParams): string {
  const maxLen = 4000;
  const text = p.chapterText.length > maxLen
    ? p.chapterText.slice(0, maxLen) + '…（已截断）'
    : p.chapterText;

  const typeLabel = p.type === 'mcq' ? '单选题' : p.type === 'fill' ? '填空题' : '简答题';
  const diffLabel = p.difficulty === 'easy' ? '简单' : p.difficulty === 'medium' ? '中等' : '困难';

  return (
    `你是一位英语阅读理解出题专家。根据以下章节内容出一道${diffLabel}${typeLabel}。\n\n` +
    `要求：严格只返回 JSON，不要 markdown code fence，不要任何额外说明。\n` +
    `JSON schema：\n` +
    `{"id":"string","type":"${p.type}","difficulty":"${p.difficulty}",` +
    `"prompt":"string","quote":"string",` +
    `"options":${p.type === 'mcq' ? '["A选项","B选项","C选项","D选项"]' : 'null'},` +
    `"answer":"string","explanation":"string"}\n\n` +
    `章节内容：\n${text}`
  );
}
