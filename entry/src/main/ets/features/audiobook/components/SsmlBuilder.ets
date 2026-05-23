/**
 * SsmlBuilder.ets — W8-C5 SSML 生成工具
 *
 * 把 plain text 或带标注的文本转成有效 SSML（W3C SSML 1.1 子集）。
 * 输出统一以 <speak version="1.0" xml:lang="..."> 包裹。
 *
 * 支持的标注：
 *   - voice            voice name=...
 *   - prosody          prosody rate / pitch / volume
 *   - break            break time=..ms
 *   - emphasis         emphasis level=strong / moderate / reduced
 *   - phoneme (IPA)    phoneme alphabet=ipa ph=..
 *   - sub              sub alias=..
 *
 * 转义：amp lt gt quot apos 全部走 escape。
 * 段落分隔：plain text 中遇到双换行 -> 自动插入 break 600ms。
 * 智能处理：URL / 大写缩写 / 数字 在 fromPlainText 中替换为 say-as。
 */

// ---------- 公共类型 ----------

export type EmphasisLevel = 'strong' | 'moderate' | 'reduced' | 'none';

/** prosody 子集，与 W3C SSML 一致 */
export interface ProsodyAttrs {
  rate?: string;
  pitch?: string;
  volume?: string;
}

export interface SsmlOptions {
  /** xml:lang，默认 zh-CN */
  lang?: string;
  /** voice name（可选）；不传则不包 voice */
  voice?: string;
  /** 全文 prosody（外层），不传则忽略 */
  prosody?: ProsodyAttrs;
}

/** 文本标注：在某个 [start, end) 区间应用某种 SSML 元素。 */
export type TextAnnotation =
  | { kind: 'emphasis'; start: number; end: number; level: EmphasisLevel }
  | { kind: 'prosody'; start: number; end: number; attrs: ProsodyAttrs }
  | { kind: 'phoneme'; start: number; end: number; ipa: string }
  | { kind: 'sub'; start: number; end: number; alias: string }
  | { kind: 'break'; start: number; end: number; ms: number };

// ---------- 主类 ----------

export class SsmlBuilder {
  /**
   * 把 plain text 转成 SSML（不带 annotation，仅做基本智能处理 + 段落 break）。
   */
  static fromPlainText(text: string, opts?: SsmlOptions): string {
    const lang = opts?.lang ?? 'zh-CN';
    const inner = SsmlBuilder.smartPlain(text);
    let body = inner;
    if (opts?.prosody) {
      body = `<prosody${SsmlBuilder.prosodyAttrs(opts.prosody)}>${body}</prosody>`;
    }
    if (opts?.voice) {
      body = `<voice name="${SsmlBuilder.escape(opts.voice)}">${body}</voice>`;
    }
    return `<speak version="1.0" xml:lang="${SsmlBuilder.escape(lang)}">${body}</speak>`;
  }

  /**
   * 把 text + annotation 列表合成 SSML。annotation 之间不允许重叠（重叠按 start 优先取一个）。
   */
  static fromAnnotated(
    text: string,
    annotations: TextAnnotation[],
    opts?: SsmlOptions,
  ): string {
    const lang = opts?.lang ?? 'zh-CN';
    const sorted = annotations.slice().sort((a, b) => a.start - b.start);
    let cursor = 0;
    let inner = '';
    for (const ann of sorted) {
      if (ann.start < cursor || ann.end <= ann.start) continue;
      if (ann.start > cursor) {
        inner += SsmlBuilder.escape(text.slice(cursor, ann.start));
      }
      const slice = text.slice(ann.start, ann.end);
      inner += SsmlBuilder.renderAnnotation(ann, slice);
      cursor = ann.end;
    }
    if (cursor < text.length) {
      inner += SsmlBuilder.escape(text.slice(cursor));
    }

    let body = inner;
    if (opts?.prosody) {
      body = `<prosody${SsmlBuilder.prosodyAttrs(opts.prosody)}>${body}</prosody>`;
    }
    if (opts?.voice) {
      body = `<voice name="${SsmlBuilder.escape(opts.voice)}">${body}</voice>`;
    }
    return `<speak version="1.0" xml:lang="${SsmlBuilder.escape(lang)}">${body}</speak>`;
  }

  /** XML 转义：amp lt gt quot apos 必须替换。 */
  static escape(text: string): string {
    if (!text) return '';
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;');
  }

  // ---------- 私有 ----------

  /**
   * 段落分隔 + 智能 say-as。
   */
  private static smartPlain(text: string): string {
    if (!text) return '';
    const paragraphs = text.split(/\n{2,}/);
    const rendered: string[] = [];
    for (const p of paragraphs) {
      rendered.push(SsmlBuilder.smartLine(p));
    }
    return rendered.join('<break time="600ms"/>');
  }

  private static smartLine(line: string): string {
    if (!line) return '';
    const urlRegex = /https?:\/\/[^\s]+/g;
    const acronymRegex = /\b[A-Z]{2,}\b/g;
    let buf = '';
    let last = 0;
    const replacements: Array<{ start: number; end: number; render: string }> = [];

    let m: RegExpExecArray | null;
    while ((m = urlRegex.exec(line)) !== null) {
      replacements.push({
        start: m.index,
        end: m.index + m[0].length,
        render: `<say-as interpret-as="characters">${SsmlBuilder.escape(m[0])}</say-as>`,
      });
    }
    while ((m = acronymRegex.exec(line)) !== null) {
      const overlap = replacements.some((r) => m!.index < r.end && m!.index + m![0].length > r.start);
      if (overlap) continue;
      replacements.push({
        start: m.index,
        end: m.index + m[0].length,
        render: `<say-as interpret-as="characters">${SsmlBuilder.escape(m[0])}</say-as>`,
      });
    }
    replacements.sort((a, b) => a.start - b.start);
    for (const r of replacements) {
      if (r.start < last) continue;
      buf += SsmlBuilder.escape(line.slice(last, r.start));
      buf += r.render;
      last = r.end;
    }
    buf += SsmlBuilder.escape(line.slice(last));
    return buf;
  }

  private static renderAnnotation(ann: TextAnnotation, slice: string): string {
    const escaped = SsmlBuilder.escape(slice);
    switch (ann.kind) {
      case 'emphasis':
        if (ann.level === 'none') return escaped;
        return `<emphasis level="${ann.level}">${escaped}</emphasis>`;
      case 'prosody':
        return `<prosody${SsmlBuilder.prosodyAttrs(ann.attrs)}>${escaped}</prosody>`;
      case 'phoneme':
        return `<phoneme alphabet="ipa" ph="${SsmlBuilder.escape(ann.ipa)}">${escaped}</phoneme>`;
      case 'sub':
        return `<sub alias="${SsmlBuilder.escape(ann.alias)}">${escaped}</sub>`;
      case 'break':
        return `${escaped}<break time="${Math.max(0, ann.ms)}ms"/>`;
      default:
        return escaped;
    }
  }

  private static prosodyAttrs(p: ProsodyAttrs): string {
    let s = '';
    if (p.rate)   s += ` rate="${SsmlBuilder.escape(p.rate)}"`;
    if (p.pitch)  s += ` pitch="${SsmlBuilder.escape(p.pitch)}"`;
    if (p.volume) s += ` volume="${SsmlBuilder.escape(p.volume)}"`;
    return s;
  }
}
