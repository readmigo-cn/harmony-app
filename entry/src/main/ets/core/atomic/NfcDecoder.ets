/**
 * NfcDecoder — NFC NDEF text record 解析（W11-C1）
 *
 * 用于「碰一碰」场景：用户把贴有 NDEF 标签的卡片（如词汇卡）贴到手机背面，
 * 系统通过 ohos.nfc.tag.action.TAG_FOUND 派发 want 给 LookupAbility，
 * 我们从 want.parameters 里提取 NDEF Message → 解出 text record → 取出 word。
 *
 * NDEF Text Record 格式（NFC Forum RTD-Text，简化）：
 *   payload[0] = status byte
 *     bit 7 = encoding (0=UTF-8, 1=UTF-16)
 *     bit 5..0 = language code 长度 (n)
 *   payload[1..n] = ISO/IANA language code（如 "en", "zh"）
 *   payload[n+1..] = 实际文本
 *
 * 模拟器无 NFC，TODO 真机验证。
 */

import Want from '@ohos.app.ability.Want';

/**
 * 从 want 里拿 NDEF Message 并解出第一个 text record 的文本内容。
 * 解析失败统一返回 null（让上层 fallback 到「请输入要查询的单词」空态）。
 */
export function decodeTextRecord(want: Want | undefined): string | null {
  if (!want || !want.parameters) return null;
  try {
    // HarmonyOS NFC 派发 want 时，通常将 NDEF Message 放在 parameters.ndefMessage
    // 也可能放在 tag.ndef.NdefMessage（不同版本字段名不同），都 try 一下
    const params = want.parameters as Record<string, Object>;
    const raw =
      (params.ndefMessage as ArrayBuffer | Uint8Array | string | undefined) ??
      (params['tag.ndef.NdefMessage'] as ArrayBuffer | Uint8Array | string | undefined) ??
      undefined;
    if (raw === undefined) return null;

    const bytes = toUint8Array(raw);
    if (!bytes || bytes.length < 4) return null;
    return parseNdefTextPayload(bytes);
  } catch (e) {
    console.warn(`NfcDecoder decode failed: ${(e as Error).message}`);
    return null;
  }
}

// ─── 内部辅助 ────────────────────────────────────────────────────

/** 把不确定来源的 raw 转 Uint8Array（兼容 base64 string / ArrayBuffer / Uint8Array） */
function toUint8Array(raw: ArrayBuffer | Uint8Array | string): Uint8Array | null {
  if (raw instanceof Uint8Array) return raw;
  if (raw instanceof ArrayBuffer) return new Uint8Array(raw);
  if (typeof raw === 'string') {
    // 兼容 hex string（"DA0102656E..."）和 base64
    if (/^[0-9A-Fa-f]+$/.test(raw) && raw.length % 2 === 0) {
      const out = new Uint8Array(raw.length / 2);
      for (let i = 0; i < out.length; i++) {
        out[i] = parseInt(raw.slice(i * 2, i * 2 + 2), 16);
      }
      return out;
    }
    // base64 fallback：HarmonyOS 没自带 atob，我们简化解：
    return base64Decode(raw);
  }
  return null;
}

/** 极简 base64 decoder（仅 NDEF 短载荷场景用，可以接受 O(n^2)） */
function base64Decode(b64: string): Uint8Array | null {
  const ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const trimmed = b64.replace(/=+$/, '').replace(/\s+/g, '');
  if (trimmed.length === 0) return null;
  const out: number[] = [];
  let buffer = 0;
  let bits = 0;
  for (let i = 0; i < trimmed.length; i++) {
    const idx = ALPHA.indexOf(trimmed[i]);
    if (idx < 0) return null;
    buffer = (buffer << 6) | idx;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push((buffer >> bits) & 0xff);
    }
  }
  return new Uint8Array(out);
}

/**
 * 解析 NDEF Text Record 的 payload bytes，返回纯文本。
 * 支持 UTF-8（最常见）/ UTF-16；解析失败返回 null。
 *
 * 输入 bytes 可能是：
 *   - 完整的 NDEF Message（含 record header）
 *   - 仅 text record 的 payload（由 0x91/0xD1 等 header 之后的部分）
 * 我们尝试两种：先按完整 message 解，失败再按 payload 解。
 */
function parseNdefTextPayload(bytes: Uint8Array): string | null {
  // 1) 当作完整 NDEF Message 解：定位到第一个 type='T' 的 record
  const tIdx = findTextRecordPayloadStart(bytes);
  if (tIdx >= 0 && tIdx < bytes.length) {
    const text = decodeTextPayload(bytes.subarray(tIdx));
    if (text !== null) return text;
  }
  // 2) 整段当作 payload 解
  return decodeTextPayload(bytes);
}

/**
 * 在完整 NDEF Message 字节流中找到第一个 RTD-Text record 的 payload 起点。
 * 简化扫描：遇到 type byte == 0x54 ('T') 时认为接下来就是 payload。
 * 失败返回 -1。
 */
function findTextRecordPayloadStart(bytes: Uint8Array): number {
  for (let i = 0; i < bytes.length - 1; i++) {
    if (bytes[i] === 0x54 /* 'T' */) {
      // 'T' 是 type field；payload 在 type+typeLength 之后；
      // 这里粗略假定 typeLength=1（RTD-Text 始终如此）
      return i + 1;
    }
  }
  return -1;
}

/** 解 NDEF Text Record 的 payload 部分（status byte + lang + text）。 */
function decodeTextPayload(payload: Uint8Array): string | null {
  if (payload.length < 1) return null;
  const status = payload[0];
  const isUtf16 = (status & 0x80) !== 0;
  const langLen = status & 0x3f;
  const textStart = 1 + langLen;
  if (textStart >= payload.length) return null;
  const textBytes = payload.subarray(textStart);

  try {
    if (isUtf16) return decodeUtf16(textBytes);
    return decodeUtf8(textBytes);
  } catch (_e) {
    return null;
  }
}

/** 极简 UTF-8 decoder（HarmonyOS NEXT 也有 util.TextDecoder，这里避免依赖）。 */
function decodeUtf8(bytes: Uint8Array): string {
  let s = '';
  let i = 0;
  while (i < bytes.length) {
    const b = bytes[i++];
    if (b < 0x80) {
      s += String.fromCharCode(b);
    } else if (b < 0xc0) {
      // 非法 continuation byte，跳过
      continue;
    } else if (b < 0xe0) {
      if (i >= bytes.length) break;
      const b2 = bytes[i++] & 0x3f;
      s += String.fromCharCode(((b & 0x1f) << 6) | b2);
    } else if (b < 0xf0) {
      if (i + 1 >= bytes.length) break;
      const b2 = bytes[i++] & 0x3f;
      const b3 = bytes[i++] & 0x3f;
      s += String.fromCharCode(((b & 0x0f) << 12) | (b2 << 6) | b3);
    } else {
      // surrogate pair（不常见于 word 卡片，仅占位）
      if (i + 2 >= bytes.length) break;
      const b2 = bytes[i++] & 0x3f;
      const b3 = bytes[i++] & 0x3f;
      const b4 = bytes[i++] & 0x3f;
      const cp = ((b & 0x07) << 18) | (b2 << 12) | (b3 << 6) | b4;
      const offset = cp - 0x10000;
      s += String.fromCharCode(0xd800 + (offset >> 10), 0xdc00 + (offset & 0x3ff));
    }
  }
  return s.trim();
}

/** UTF-16 BE 解码（NDEF 默认 BE）。 */
function decodeUtf16(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i + 1 < bytes.length; i += 2) {
    s += String.fromCharCode((bytes[i] << 8) | bytes[i + 1]);
  }
  return s.trim();
}
