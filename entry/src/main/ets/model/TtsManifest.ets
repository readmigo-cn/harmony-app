/**
 * TtsManifest — 对齐 iOS readmigo `/v3/tts/audiobook` 响应结构。
 *
 * server 端预生成 MP3 + 句级时间戳：
 *   - audioUrl: 完整 MP3 文件（CDN URL，支持 Range 请求）
 *   - sentences: 顺序数组，每句对应原文 char 范围 + 音频时间窗口
 *
 * 客户端 CloudTtsPlayer 播放策略：
 *   1. AVPlayer 流式拉 audioUrl
 *   2. 200ms 轮询 player.currentTime
 *   3. 二分查找当前时间落在哪个 sentence.startMs ~ endMs 区间
 *   4. emit onSentenceChange(idx) → UI 高亮对应 char 范围
 *
 * 当 server-cn `/v3/tts/audiobook` 端点未就绪时，TtsV3Api 返回 null，
 * 调用方降级到 mock 或 LibriVox（audioUrl 直拉）。
 */
export interface TtsSentence {
  /** 句子文本（原文片段，与 char 范围对应） */
  readonly text: string;
  /** 在该 chapter 全文中的字符起始偏移（含） */
  readonly charStart: number;
  /** 字符终止偏移（不含） */
  readonly charEnd: number;
  /** 音频起始毫秒 */
  readonly startMs: number;
  /** 音频终止毫秒 */
  readonly endMs: number;
}

export interface TtsManifest {
  /** 整章 MP3 URL；支持 Range 请求 + 持久缓存。 */
  readonly audioUrl: string;
  /** 整章音频总时长（毫秒）；UI 进度条用。 */
  readonly durationMs: number;
  /** 句子级时间戳数组；已按 startMs 升序保证。 */
  readonly sentences: TtsSentence[];
  /** server 生成 manifest 的时间戳（ISO 8601），用于缓存 TTL 判断。 */
  readonly generatedAt: string;
  /** voice / speed 反向回填，便于客户端校验 manifest 与请求匹配。 */
  readonly voiceId: string;
  readonly speed: number;
}

/** TtsV3 voice DTO，对齐 iOS `/v3/tts/voices` 响应。 */
export interface TtsV3Voice {
  readonly id: string;
  readonly name: string;
  readonly lang: string;
  readonly gender: 'male' | 'female' | 'neutral';
  /** 试听样本 MP3 URL，可选 */
  readonly sampleUrl?: string;
  /** 是否需要付费订阅 */
  readonly premium: boolean;
}

/**
 * 二分查找：返回 sentences 中包含 currentMs 的句子下标；找不到返 -1。
 * 假设 sentences 已按 startMs 升序排列且区间不重叠。
 */
export function findSentenceAt(sentences: TtsSentence[], currentMs: number): number {
  if (sentences.length === 0) return -1;
  let lo = 0;
  let hi = sentences.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const s = sentences[mid];
    if (currentMs < s.startMs) {
      hi = mid - 1;
    } else if (currentMs >= s.endMs) {
      lo = mid + 1;
    } else {
      return mid;
    }
  }
  return -1;
}
