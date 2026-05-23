/**
 * DistributedClipboard.ets — W13-C2 跨端剪贴板
 *
 * 职责：
 *   - 把文本 / 富文本 / 单词 / 划线笔记写入分布式 pasteboard
 *     让其它登录同账号的 HarmonyOS 设备直接粘贴
 *   - 自定义 MIME（vocab+json / highlight+json）实现「内容级」跨端识别：
 *     接收端解析后弹起 PasteFromOtherDeviceSheet 让用户选「保存到生词本」
 *   - 维护本机最近 10 条剪贴板历史（持久化到 PreferencesManager）
 *
 * 自定义 MIME 设计：
 *   text/plain                       — 普通文本（fallback）
 *   text/html                        — 富文本（带 plain fallback）
 *   application/vocab+json           — 生词 payload（JSON，UTF-8）
 *   application/highlight+json       — 划线笔记 payload（JSON，UTF-8）
 *
 * 跨端同步：
 *   - 真机：@ohos.pasteboard 默认即为「分布式 pasteboard」（同账号设备共享）
 *   - 模拟器：仅本机 pasteboard，跨端能力 TODO 真机验证
 *   - 接收端通过 subscribeIncoming 监听 pasteboard 变化
 *
 * 不在此文件做的事：
 *   - 不直接写云端（笔记云同步走 NoteService / NotesApi）
 *   - 不做 UI（PasteFromOtherDeviceSheet 负责）
 */

import pasteboard from '@ohos.pasteboard';
import { PreferencesManager } from '../../../../core/persistence/PreferencesManager';

const TAG = 'DistributedClipboard';

/** 自定义 MIME 类型常量（与接收端约定）。 */
export const MIME_VOCAB: string = 'application/vocab+json';
export const MIME_HIGHLIGHT: string = 'application/highlight+json';

/** 生词跨端 payload（写入 pasteboard 的 JSON 结构）。 */
export interface VocabPayload {
  /** 单词原文 */
  word: string;
  /** 音标（可选） */
  phonetic?: string;
  /** 中文释义（可选） */
  definition?: string;
  /** 上下文原句（可选） */
  context?: string;
  /** 来源书 ID / 章节（可选） */
  bookId?: string;
  bookTitle?: string;
  chapterTitle?: string;
  /** 写入时刻（ms） */
  timestamp: number;
}

/** 划线笔记跨端 payload。 */
export interface HighlightPayload {
  /** 划线文本 */
  text: string;
  /** 用户备注（可选） */
  note?: string;
  /** 颜色（与本地 HighlightColor 对齐） */
  color?: string;
  bookId?: string;
  bookTitle?: string;
  chapterTitle?: string;
  timestamp: number;
}

/** 写入选项。 */
export interface ClipboardOptions {
  /** 写入后是否提示（仅 UI 层使用，本服务不直接 toast） */
  silent?: boolean;
  /** 是否记入历史（默认 true） */
  recordHistory?: boolean;
}

/** 历史条目（持久化到 prefs）。 */
export interface ClipboardEntry {
  kind: 'text' | 'html' | 'vocab' | 'highlight';
  preview: string;
  /** vocab/highlight 类型保留原始 JSON */
  raw?: string;
  /** 写入时刻 */
  timestamp: number;
}

/** 接收端回调签名。 */
export type IncomingHandler = (entry: IncomingEntry) => void;

/** 监听到的远端 pasteboard 变更。 */
export interface IncomingEntry {
  kind: 'text' | 'html' | 'vocab' | 'highlight';
  text?: string;
  html?: string;
  vocab?: VocabPayload;
  highlight?: HighlightPayload;
  /** 来源设备 name（占位，真机由 deviceManager 提供） */
  sourceDeviceName?: string;
  /** 远端写入时刻（payload.timestamp 反推） */
  receivedAt: number;
}

const PREF_KEY_HISTORY = 'distributed_clipboard_history';
const HISTORY_LIMIT = 10;

class DistributedClipboardImpl {
  private board: pasteboard.SystemPasteboard | null = null;
  private subscribers: Set<IncomingHandler> = new Set<IncomingHandler>();
  /** 上次写入的 hash，用来过滤本机写入的回调（避免自环触发 incoming）。 */
  private lastSelfWriteHash: string = '';
  /** pasteboard 监听是否已挂载 */
  private pasteboardListenerBound: boolean = false;

  // ---------- public API ----------

  /** 写入纯文本。 */
  async copyText(text: string, opts?: ClipboardOptions): Promise<void> {
    if (!text) return;
    const board = this.ensureBoard();
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    await board.setData(data);
    this.lastSelfWriteHash = this.hashOf('text', text);
    if (opts?.recordHistory !== false) {
      await this.appendHistory({
        kind: 'text',
        preview: text.slice(0, 60),
        timestamp: Date.now(),
      });
    }
    console.info(`${TAG} copyText len=${text.length}`);
  }

  /** 写入富文本（带 plain fallback）。 */
  async copyHtml(html: string, plainText: string, opts?: ClipboardOptions): Promise<void> {
    if (!html) return;
    const board = this.ensureBoard();
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_HTML, html);
    // 追加 plain text record，便于不支持 html 的接收端
    if (plainText) {
      const plainRecord = pasteboard.createRecord(pasteboard.MIMETYPE_TEXT_PLAIN, plainText);
      data.addRecord(plainRecord);
    }
    await board.setData(data);
    this.lastSelfWriteHash = this.hashOf('html', html);
    if (opts?.recordHistory !== false) {
      await this.appendHistory({
        kind: 'html',
        preview: (plainText || html).slice(0, 60),
        timestamp: Date.now(),
      });
    }
    console.info(`${TAG} copyHtml len=${html.length}`);
  }

  /**
   * 写入生词 payload（自定义 MIME）。
   *
   * 接收端识别 MIME_VOCAB 后弹「保存到生词本」sheet。
   */
  async copyVocab(word: VocabPayload, opts?: ClipboardOptions): Promise<void> {
    if (!word || !word.word) return;
    const json = JSON.stringify(word);
    const board = this.ensureBoard();
    // 自定义 MIME 用 createData(mime, value)；HarmonyOS 支持 application/* 自定义类型
    const data = pasteboard.createData(MIME_VOCAB, json);
    // 同时附带 plain text，让普通粘贴也能拿到原词 + 释义
    const plain = `${word.word}${word.phonetic ? ` /${word.phonetic}/` : ''}${word.definition ? `\n${word.definition}` : ''}`;
    data.addRecord(pasteboard.createRecord(pasteboard.MIMETYPE_TEXT_PLAIN, plain));
    await board.setData(data);
    this.lastSelfWriteHash = this.hashOf('vocab', json);
    if (opts?.recordHistory !== false) {
      await this.appendHistory({
        kind: 'vocab',
        preview: word.word,
        raw: json,
        timestamp: word.timestamp,
      });
    }
    console.info(`${TAG} copyVocab word=${word.word}`);
  }

  /** 写入划线笔记 payload（自定义 MIME）。 */
  async copyHighlight(highlight: HighlightPayload, opts?: ClipboardOptions): Promise<void> {
    if (!highlight || !highlight.text) return;
    const json = JSON.stringify(highlight);
    const board = this.ensureBoard();
    const data = pasteboard.createData(MIME_HIGHLIGHT, json);
    const plain = highlight.note ? `${highlight.text}\n— ${highlight.note}` : highlight.text;
    data.addRecord(pasteboard.createRecord(pasteboard.MIMETYPE_TEXT_PLAIN, plain));
    await board.setData(data);
    this.lastSelfWriteHash = this.hashOf('highlight', json);
    if (opts?.recordHistory !== false) {
      await this.appendHistory({
        kind: 'highlight',
        preview: highlight.text.slice(0, 60),
        raw: json,
        timestamp: highlight.timestamp,
      });
    }
    console.info(`${TAG} copyHighlight len=${highlight.text.length}`);
  }

  /** 读取本机最近 10 条历史（按时间倒序）。 */
  async getRecentCopies(): Promise<ClipboardEntry[]> {
    const arr = await PreferencesManager.getArray<ClipboardEntry>(PREF_KEY_HISTORY, []);
    return arr.slice().sort((a, b) => b.timestamp - a.timestamp).slice(0, HISTORY_LIMIT);
  }

  /** 清空历史。 */
  async clearHistory(): Promise<void> {
    await PreferencesManager.setArray<ClipboardEntry>(PREF_KEY_HISTORY, []);
  }

  /**
   * 监听远端（或本机）pasteboard 变化。
   *
   * 真机分布式 pasteboard 默认开启，HarmonyOS 系统会在收到其它设备写入时触发本地
   * pasteboard.on('update')，由本方法转发为强类型 IncomingEntry。
   *
   * 返回 unsubscribe 句柄。
   */
  subscribeIncoming(callback: IncomingHandler): () => void {
    this.subscribers.add(callback);
    this.bindPasteboardListenerIfNeeded();
    return () => {
      this.subscribers.delete(callback);
    };
  }

  // ---------- internals ----------

  private ensureBoard(): pasteboard.SystemPasteboard {
    if (!this.board) {
      this.board = pasteboard.getSystemPasteboard();
    }
    return this.board;
  }

  private bindPasteboardListenerIfNeeded(): void {
    if (this.pasteboardListenerBound) return;
    const board = this.ensureBoard();
    try {
      // pasteboard 变化通知（HarmonyOS NEXT 5.0+ 支持的事件名）
      board.on('update', () => {
        this.handlePasteboardChange().catch((e: Error) => {
          console.warn(`${TAG} handlePasteboardChange error: ${e.message}`);
        });
      });
      this.pasteboardListenerBound = true;
      console.info(`${TAG} pasteboard listener bound`);
    } catch (e) {
      // 部分环境（模拟器 / 旧版）无该事件，降级为轮询占位
      console.warn(`${TAG} bind listener failed: ${(e as Error).message}`);
    }
  }

  private async handlePasteboardChange(): Promise<void> {
    if (this.subscribers.size === 0) return;
    const board = this.ensureBoard();
    const data = await board.getData();
    if (!data) return;

    // 优先识别自定义 MIME，避免 plain fallback 误抢 vocab/highlight 流程
    const recordCount = data.getRecordCount();
    let kind: IncomingEntry['kind'] = 'text';
    let entry: IncomingEntry = { kind: 'text', receivedAt: Date.now() };

    for (let i = 0; i < recordCount; i++) {
      const rec = data.getRecord(i);
      const mime = rec.mimeType;
      if (mime === MIME_VOCAB) {
        const json = rec.plainText ?? '';
        const v = this.tryParse<VocabPayload>(json);
        if (v) {
          kind = 'vocab';
          entry = { kind, vocab: v, receivedAt: Date.now() };
          break;
        }
      } else if (mime === MIME_HIGHLIGHT) {
        const json = rec.plainText ?? '';
        const h = this.tryParse<HighlightPayload>(json);
        if (h) {
          kind = 'highlight';
          entry = { kind, highlight: h, receivedAt: Date.now() };
          break;
        }
      } else if (mime === pasteboard.MIMETYPE_TEXT_HTML && kind === 'text') {
        kind = 'html';
        entry = { kind, html: rec.htmlText ?? '', text: rec.plainText, receivedAt: Date.now() };
      } else if (mime === pasteboard.MIMETYPE_TEXT_PLAIN && kind === 'text') {
        entry = { kind: 'text', text: rec.plainText ?? '', receivedAt: Date.now() };
      }
    }

    // 自环过滤：本机刚写的 hash == 这次拿到的 hash 则忽略
    const incomingHash = this.hashFromEntry(entry);
    if (incomingHash && incomingHash === this.lastSelfWriteHash) {
      console.info(`${TAG} skip self-originated pasteboard event`);
      return;
    }

    this.subscribers.forEach((cb) => {
      try { cb(entry); } catch (_e) { /* swallow */ }
    });
  }

  private async appendHistory(entry: ClipboardEntry): Promise<void> {
    const list = await PreferencesManager.getArray<ClipboardEntry>(PREF_KEY_HISTORY, []);
    list.unshift(entry);
    const trimmed = list.slice(0, HISTORY_LIMIT);
    await PreferencesManager.setArray<ClipboardEntry>(PREF_KEY_HISTORY, trimmed);
  }

  private tryParse<T>(json: string): T | null {
    try { return JSON.parse(json) as T; } catch (_e) { return null; }
  }

  /** 简易 hash：用于自环过滤（kind + content 前 256 字符）。 */
  private hashOf(kind: string, content: string): string {
    return `${kind}:${content.length}:${content.slice(0, 256)}`;
  }

  private hashFromEntry(e: IncomingEntry): string {
    if (e.kind === 'vocab' && e.vocab) return this.hashOf('vocab', JSON.stringify(e.vocab));
    if (e.kind === 'highlight' && e.highlight) return this.hashOf('highlight', JSON.stringify(e.highlight));
    if (e.kind === 'html' && e.html) return this.hashOf('html', e.html);
    if (e.kind === 'text' && e.text) return this.hashOf('text', e.text);
    return '';
  }
}

/** 单例 */
export const DistributedClipboard = new DistributedClipboardImpl();
