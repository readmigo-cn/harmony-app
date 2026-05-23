/**
 * UgcModerator.ets — W16-C3 用户生成内容（UGC）多层审核
 *
 * 入口场景：
 *   - 笔记保存前 / 阅读分享前 / 头像上传前 / 个人简介保存前
 *
 * 审核分层（任一层 reject 即阻止提交，review 落审核队列）：
 *   1) 长度与字符规则（pass / reject）
 *      - text: 1~2000 字
 *      - 单字符重复 > 30 倍 → reject（防灌水）
 *      - 控制字符 / 零宽字符占比 > 5% → reject
 *   2) 本地敏感词（pass / review）
 *      - 命中 politics → reject
 *      - 命中 sexual / violence → reject
 *      - 命中 advertising / other → review
 *   3) 重复内容检测（pass / review）
 *      - 与最近 5 条本地缓存重复（hash 命中）→ review
 *   4) 后端 API 占位（pass / review / reject）
 *      - TODO 接入「网信办内容安全审核」API
 *
 * UGC 类型 kind：
 *   note / share-text / nickname / bio / image
 *
 * level 含义：
 *   pass    — 直接通过，前端可保存 / 发布
 *   review  — 后端人工 / 二次审核（前端可暂存为「审核中」）
 *   reject  — 直接拒绝，前端给 suggestion 引导用户修改
 *
 * 设计权衡：
 *   - 不在客户端做最终裁决（绕过攻击成本极低）
 *   - 客户端只负责「明显违规」的快速阻断 + 良好的 UX 提示
 *   - 后端必须再做一次完整审核，且以后端结果为准
 */

import { SensitiveWordList, SensitiveCategory } from './SensitiveWordList';
import { NsfwDetector, NsfwResult } from './NsfwDetector';

const TAG = 'UgcModerator';

/** UGC 类型 */
export type UgcKind = 'note' | 'share-text' | 'nickname' | 'bio' | 'image';

/** 审核结果级别 */
export type ModerationLevel = 'pass' | 'review' | 'reject';

/** 审核结果 */
export interface ModerationResult {
  /** 是否通过（level === 'pass'） */
  passed: boolean;
  /** 详细级别 */
  level: ModerationLevel;
  /** 拒绝/审核原因（中文，可直接给用户看） */
  reason?: string;
  /** 给用户的修改建议（多条） */
  suggestions: string[];
  /** 命中明细（debug / 后台日志用） */
  details?: {
    hits?: { word: string; category: SensitiveCategory }[];
    nsfw?: NsfwResult;
    duplicateOf?: string;
  };
}

/** 长度上限（字符数）。 */
const TEXT_LIMITS: Record<UgcKind, { min: number; max: number }> = {
  'note': { min: 1, max: 2000 },
  'share-text': { min: 1, max: 500 },
  'nickname': { min: 2, max: 24 },
  'bio': { min: 0, max: 200 },
  'image': { min: 0, max: 0 }, // 图片走另一个分支
};

export class UgcModerator {
  /** 最近提交内容 hash，用于重复检测。 */
  private static recent: string[] = [];
  private static readonly RECENT_CAP: number = 5;

  /** 测试 / 重置入口。 */
  static __resetForTest(): void {
    UgcModerator.recent = [];
  }

  // ─────────────────────────────────────────
  // 文本审核
  // ─────────────────────────────────────────

  /**
   * 审核文本。
   * @param text 原文
   * @param kind UGC 场景（决定长度上限）
   */
  static async moderateText(text: string, kind: UgcKind): Promise<ModerationResult> {
    if (kind === 'image') {
      return UgcModerator.reject('文本审核不支持 image 类型', ['请使用 moderateImage']);
    }

    // ── Layer 1: 长度 / 字符 ──────────────────────────
    const lenCheck = UgcModerator.checkLength(text, kind);
    if (lenCheck) return lenCheck;
    const charCheck = UgcModerator.checkChars(text);
    if (charCheck) return charCheck;

    // ── Layer 2: 本地敏感词 ───────────────────────────
    const hits = SensitiveWordList.findAll(text);
    if (hits.length > 0) {
      const worst = UgcModerator.worstCategory(hits.map((h) => h.category));
      const hitDetails = hits.map((h) => ({ word: h.word, category: h.category }));
      if (worst === 'politics' || worst === 'sexual' || worst === 'violence') {
        return {
          passed: false,
          level: 'reject',
          reason: `内容含违规词（${UgcModerator.cnCategory(worst)}），请修改后重新提交`,
          suggestions: ['移除高亮词', '换一种表达方式'],
          details: { hits: hitDetails },
        };
      }
      // advertising / other → review
      return {
        passed: false,
        level: 'review',
        reason: '内容需进一步审核',
        suggestions: ['等待后台审核（一般 5 分钟内）'],
        details: { hits: hitDetails },
      };
    }

    // ── Layer 3: 重复检测 ────────────────────────────
    const dup = UgcModerator.checkDuplicate(text);
    if (dup) return dup;

    // ── Layer 4: 后端 API ────────────────────────────
    const remote = await UgcModerator.callRemoteText(text, kind);
    if (remote.level !== 'pass') return remote;

    UgcModerator.rememberHash(text);
    return {
      passed: true,
      level: 'pass',
      suggestions: [],
    };
  }

  // ─────────────────────────────────────────
  // 图片审核
  // ─────────────────────────────────────────

  /** 审核图片（头像 / 笔记配图）。 */
  static async moderateImage(imageData: ArrayBuffer | Uint8Array, mime?: string): Promise<ModerationResult> {
    const nsfw = await NsfwDetector.detectAvatar(imageData, mime);
    if (!nsfw.safe) {
      return {
        passed: false,
        level: 'reject',
        reason: nsfw.suggestion || '图片内容不符合规范',
        suggestions: ['更换其它图片', '裁剪后重试'],
        details: { nsfw },
      };
    }
    return {
      passed: true,
      level: 'pass',
      suggestions: [],
      details: { nsfw },
    };
  }

  // ─────────────────────────────────────────
  // 内部规则
  // ─────────────────────────────────────────

  private static checkLength(text: string, kind: UgcKind): ModerationResult | null {
    const t = text ?? '';
    const limits = TEXT_LIMITS[kind];
    const len = Array.from(t).length; // 计 emoji 为 1 字符
    if (len < limits.min) {
      return UgcModerator.reject(`内容过短（最少 ${limits.min} 字）`, ['补充更多内容']);
    }
    if (len > limits.max) {
      return UgcModerator.reject(`内容过长（最多 ${limits.max} 字，当前 ${len} 字）`, ['精简内容']);
    }
    return null;
  }

  private static checkChars(text: string): ModerationResult | null {
    if (text.length === 0) return null;
    // 单字符重复 > 30
    let prev = '';
    let run = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (ch === prev) {
        run += 1;
        if (run > 30) {
          return UgcModerator.reject('内容含连续重复字符（疑似灌水）', ['移除重复字符']);
        }
      } else {
        prev = ch;
        run = 1;
      }
    }
    // 控制字符 / 零宽字符占比
    let invalid = 0;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      if (code < 0x20 && code !== 0x09 && code !== 0x0A && code !== 0x0D) invalid += 1;
      // 零宽字符 / RTL 控制
      if (code === 0x200B || code === 0x200C || code === 0x200D || code === 0x202E) invalid += 1;
    }
    if (text.length > 0 && invalid / text.length > 0.05) {
      return UgcModerator.reject('内容含异常控制字符', ['移除特殊符号']);
    }
    return null;
  }

  private static checkDuplicate(text: string): ModerationResult | null {
    const h = UgcModerator.hashText(text);
    if (UgcModerator.recent.indexOf(h) >= 0) {
      return {
        passed: false,
        level: 'review',
        reason: '内容与近期已提交内容高度相似',
        suggestions: ['修改部分内容', '稍后再试'],
        details: { duplicateOf: h },
      };
    }
    return null;
  }

  /** 占位远端审核：始终通过。真实接入后端 /api/v1/moderation/text。 */
  private static async callRemoteText(text: string, kind: UgcKind): Promise<ModerationResult> {
    // TODO: 接入后端 API
    //   const resp = await HttpClient.post('/api/v1/moderation/text', { text, kind });
    //   return resp.level === 'reject' ? UgcModerator.reject(resp.reason, resp.suggestions ?? []) : ...
    await new Promise<void>((resolve) => setTimeout(() => resolve(), 0));
    return { passed: true, level: 'pass', suggestions: [] };
  }

  private static rememberHash(text: string): void {
    UgcModerator.recent.push(UgcModerator.hashText(text));
    if (UgcModerator.recent.length > UgcModerator.RECENT_CAP) {
      UgcModerator.recent.shift();
    }
  }

  /** 简易 djb2 hash，仅用于近重复检测，不参与安全决策。 */
  private static hashText(text: string): string {
    let h = 5381;
    for (let i = 0; i < text.length; i++) {
      h = ((h << 5) + h + text.charCodeAt(i)) | 0;
    }
    return `h_${h}`;
  }

  private static reject(reason: string, suggestions: string[]): ModerationResult {
    return { passed: false, level: 'reject', reason, suggestions };
  }

  /** 类别严重度排序：politics > sexual > violence > advertising > other。 */
  private static worstCategory(cats: SensitiveCategory[]): SensitiveCategory {
    const order: SensitiveCategory[] = ['politics', 'sexual', 'violence', 'advertising', 'other'];
    for (const c of order) {
      if (cats.indexOf(c) >= 0) return c;
    }
    return 'other';
  }

  private static cnCategory(c: SensitiveCategory): string {
    if (c === 'politics') return '政治敏感';
    if (c === 'sexual') return '色情低俗';
    if (c === 'violence') return '暴力血腥';
    if (c === 'advertising') return '广告 / 推广';
    return '其它违规';
  }
}
