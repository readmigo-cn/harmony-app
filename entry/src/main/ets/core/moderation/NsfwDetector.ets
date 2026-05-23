/**
 * NsfwDetector.ets — W16-C2 头像 / 用户上传图片 NSFW 检测
 *
 * 职责：
 *   - 在用户上传头像、笔记配图等场景被调用
 *   - 输入：原始字节（ArrayBuffer / Uint8Array）+ 可选 mime type
 *   - 输出：NsfwResult { safe, confidence, categories[], suggestion }
 *
 * 检测层次（按成本递增）：
 *   1) 客户端尺寸 / 文件大小异常 — 极端大或 0 字节直接拒（可能是绕过攻击）
 *   2) 客户端 EXIF 异常 — 部分 NSFW 工具会留下特征（仅占位，真实需 ExifReader）
 *   3) 服务端 NSFW API — 占位调用，TODO 接入百度/腾讯 NSFW 内容审核 API
 *
 * 真实接口建议：
 *   - 百度 AI 开放平台「图像审核」 https://ai.baidu.com/tech/imagecensoring
 *   - 阿里云「内容安全 — 图片审核」 imageaudit.aliyuncs.com
 *
 * 现阶段实现：
 *   - Mock 始终返回 safe: true（避免误拦截阻塞开发联调）
 *   - 仅在「明显异常输入」时返回 reject，便于前端流程联调
 *
 * 与 UgcModerator 关系：
 *   - UgcModerator.moderateImage 内部调本类，统一封装为 ModerationResult
 */

const TAG = 'NsfwDetector';

/** NSFW 风险类别（与百度/腾讯 API 对齐的简化版） */
export type NsfwCategory = 'porn' | 'sexy' | 'violence' | 'gore' | 'qrcode' | 'ad';

/** 检测结果 */
export interface NsfwResult {
  /** 是否安全（false 必须 reject 上传） */
  safe: boolean;
  /** 置信度 0~1，1 表示模型非常确信 */
  confidence: number;
  /** 命中的风险类别（safe 时为空） */
  categories: NsfwCategory[];
  /** UI 建议提示语（中文） */
  suggestion: string;
  /** 错误信息（仅在调用失败时填） */
  error?: string;
}

export class NsfwDetector {
  /** 单帧最大字节数（4MB），超出直接拒。 */
  private static readonly MAX_BYTES: number = 4 * 1024 * 1024;
  /** 最小字节数（512B），过小不可能是真实图。 */
  private static readonly MIN_BYTES: number = 512;

  /**
   * 检测头像 / 单张图片。
   * @param imageData 原始字节（ArrayBuffer / Uint8Array）
   * @param mime 可选 MIME，便于后端选模型
   */
  static async detectAvatar(imageData: ArrayBuffer | Uint8Array, mime?: string): Promise<NsfwResult> {
    // ── Step 1: 尺寸异常 ─────────────────────────────
    const bytes = NsfwDetector.byteLength(imageData);
    if (bytes < NsfwDetector.MIN_BYTES) {
      return {
        safe: false,
        confidence: 1,
        categories: [],
        suggestion: '图片太小或损坏，请重新选择',
        error: 'image_too_small',
      };
    }
    if (bytes > NsfwDetector.MAX_BYTES) {
      return {
        safe: false,
        confidence: 1,
        categories: [],
        suggestion: '图片大小超过 4MB，请压缩后重试',
        error: 'image_too_large',
      };
    }

    // ── Step 2: MIME 白名单 ─────────────────────────
    if (mime && !NsfwDetector.isAllowedMime(mime)) {
      return {
        safe: false,
        confidence: 1,
        categories: [],
        suggestion: '只支持 JPG / PNG / WEBP 格式',
        error: 'invalid_mime',
      };
    }

    // ── Step 3: EXIF 异常占位（真实需 ExifReader 解析） ─
    if (NsfwDetector.hasSuspiciousExif(imageData)) {
      return {
        safe: false,
        confidence: 0.85,
        categories: ['ad'],
        suggestion: '检测到异常元数据，请重新选择图片',
        error: 'suspicious_exif',
      };
    }

    // ── Step 4: 服务端 NSFW API（mock 始终通过） ─────
    // TODO: 接入百度 NSFW API
    //   const resp = await HttpClient.post('https://aip.baidubce.com/.../imgaudit', {
    //     image: base64(imageData),
    //   });
    //   return NsfwDetector.fromBaiduResp(resp);
    return NsfwDetector.mockServerCall(bytes);
  }

  /** 字节长度兼容 ArrayBuffer / Uint8Array。 */
  private static byteLength(data: ArrayBuffer | Uint8Array): number {
    if (data instanceof ArrayBuffer) return data.byteLength;
    return data.byteLength;
  }

  private static isAllowedMime(mime: string): boolean {
    const m = mime.toLowerCase();
    return m === 'image/jpeg' || m === 'image/jpg' || m === 'image/png' || m === 'image/webp';
  }

  /**
   * 占位 EXIF 异常检测：
   *   真实实现需 ExifReader 解析 GPS / Software 字段。
   *   这里以「字节流前 16B 含全 0」作为最弱占位规则（避免误杀）。
   */
  private static hasSuspiciousExif(data: ArrayBuffer | Uint8Array): boolean {
    const view = data instanceof ArrayBuffer ? new Uint8Array(data) : data;
    const head = Math.min(16, view.byteLength);
    if (head === 0) return true;
    let zeros = 0;
    for (let i = 0; i < head; i++) {
      if (view[i] === 0) zeros += 1;
    }
    return zeros === head; // 全 0 头通常不是合法图
  }

  /** Mock 服务端调用，始终判定 safe。 */
  private static async mockServerCall(bytes: number): Promise<NsfwResult> {
    // 模拟一次轻量异步
    await new Promise<void>((resolve) => setTimeout(() => resolve(), 0));
    return {
      safe: true,
      confidence: 0.99,
      categories: [],
      suggestion: '',
    };
  }
}
