import huks from '@ohos.security.huks';
import dataPreferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import cryptoFramework from '@ohos.security.cryptoFramework';
import buffer from '@ohos.buffer';

const KEYSTORE_PREFS = 'readmigo_keystore';
const HUKS_KEY_ALIAS = 'readmigo_master_v1';
const STORED_KEY = 'master_key_v1';
const STORED_HW_FLAG = 'hw_backed_v1';
const KEY_BYTES = 16;

const TAG = 'SecureKeystore';

/**
 * 硬件密钥库封装，等价 iOS Keychain（硬件后端）。
 *
 * 行为：
 * - init(context)：尝试在 HUKS 生成 AES-256 主密钥（alias 'readmigo_master_v1'）；
 *   设备不支持 / 失败时降级到软存储。
 * - getOrCreateMasterKey()：返回 32 hex 字符（16 字节）工作密钥，供 PreferencesManager
 *   做 AES-128-CBC 数据加密用。首次调用生成 16 字节 CSPRNG 随机数；
 *   HUKS 可用时密文化后落盘（不可导出），否则明文存（兼容旧设备）。
 *
 * 安全提升：
 * - 旧实现：硬编码 DEFAULT_KEY_HEX = '0011...eeff'，所有设备同密钥
 * - 新实现：每台设备首启时由 CSPRNG 生成独立密钥；HUKS 后端密文化
 *
 * 兼容：HUKS 不可用时仍能工作，与现有数据兼容（如本设备从未跑过新代码，会生成新密钥；
 * 旧密文用旧 DEFAULT_KEY_HEX 解密失败 → 调用方退路，例如重新登录刷 token）。
 */
export class SecureKeystore {
  private static hwBacked: boolean = false;
  private static cached: string | null = null;
  private static prefs: dataPreferences.Preferences | null = null;
  private static initialized: boolean = false;

  static async init(context: common.UIAbilityContext): Promise<void> {
    if (SecureKeystore.initialized) return;
    SecureKeystore.prefs = await dataPreferences.getPreferences(context, KEYSTORE_PREFS);
    SecureKeystore.hwBacked = await SecureKeystore.tryEnsureHuksKey();
    SecureKeystore.initialized = true;
  }

  static isHardwareBacked(): boolean {
    return SecureKeystore.hwBacked;
  }

  static async getOrCreateMasterKey(): Promise<string> {
    if (SecureKeystore.cached !== null) return SecureKeystore.cached;
    const prefs = SecureKeystore.prefs;
    if (!prefs) throw new Error('SecureKeystore.init() not called');

    const stored = await prefs.get(STORED_KEY, '') as string;
    if (typeof stored === 'string' && stored.length > 0) {
      try {
        const decoded = await SecureKeystore.decodeStoredKey(stored);
        SecureKeystore.cached = decoded;
        return decoded;
      } catch (e) {
        console.warn(`${TAG} decode failed, regenerating: ${e}`);
      }
    }

    const newKey = SecureKeystore.generateHexKey(KEY_BYTES);
    const encoded = await SecureKeystore.encodeStoredKey(newKey);
    await prefs.put(STORED_KEY, encoded);
    await prefs.put(STORED_HW_FLAG, SecureKeystore.hwBacked);
    await prefs.flush();
    SecureKeystore.cached = newKey;
    return newKey;
  }

  /** 调试/测试用：清空本地 keystore，下次 getOrCreateMasterKey 会重新生成。 */
  static async reset(): Promise<void> {
    const prefs = SecureKeystore.prefs;
    if (!prefs) return;
    await prefs.delete(STORED_KEY);
    await prefs.delete(STORED_HW_FLAG);
    await prefs.flush();
    SecureKeystore.cached = null;
    if (SecureKeystore.hwBacked) {
      try {
        await huks.deleteKeyItem(HUKS_KEY_ALIAS, SecureKeystore.huksKeyOptions());
      } catch (_e) { /* ignore */ }
    }
  }

  // ---------- HUKS ----------

  private static async tryEnsureHuksKey(): Promise<boolean> {
    try {
      const options = SecureKeystore.huksKeyOptions();
      const exists = await huks.isKeyItemExist(HUKS_KEY_ALIAS, options);
      if (!exists) {
        await huks.generateKeyItem(HUKS_KEY_ALIAS, options);
      }
      return true;
    } catch (e) {
      console.warn(`${TAG} HUKS unavailable, soft-stored mode: ${e}`);
      return false;
    }
  }

  private static huksKeyOptions(): huks.HuksOptions {
    return {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        {
          tag: huks.HuksTag.HUKS_TAG_PURPOSE,
          value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT,
        },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
      ],
    };
  }

  private static huksCryptoOptions(purpose: number, iv: Uint8Array, inData: Uint8Array): huks.HuksOptions {
    return {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
        { tag: huks.HuksTag.HUKS_TAG_IV, value: iv },
      ],
      inData,
    };
  }

  private static async encodeStoredKey(hex: string): Promise<string> {
    if (!SecureKeystore.hwBacked) return hex;
    try {
      const iv = SecureKeystore.cryptoRandomBytes(16);
      const plain = new Uint8Array(buffer.from(hex, 'utf-8').buffer);
      const opts = SecureKeystore.huksCryptoOptions(
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, iv, plain,
      );
      const session = await huks.initSession(HUKS_KEY_ALIAS, opts);
      const result = await huks.finishSession(session.handle, opts);
      const cipher = result.outData ?? new Uint8Array(0);
      const merged = new Uint8Array(iv.length + cipher.length);
      merged.set(iv, 0);
      merged.set(cipher, iv.length);
      return 'huks:' + buffer.from(merged.buffer).toString('base64');
    } catch (e) {
      console.warn(`${TAG} encode failed, soft-storing: ${e}`);
      return hex;
    }
  }

  private static async decodeStoredKey(stored: string): Promise<string> {
    if (!stored.startsWith('huks:')) return stored;
    if (!SecureKeystore.hwBacked) {
      throw new Error('Stored key is HUKS-encrypted but HUKS unavailable on this device');
    }
    const all = new Uint8Array(buffer.from(stored.slice(5), 'base64').buffer);
    const iv = all.slice(0, 16);
    const cipher = all.slice(16);
    const opts = SecureKeystore.huksCryptoOptions(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, iv, cipher,
    );
    const session = await huks.initSession(HUKS_KEY_ALIAS, opts);
    const result = await huks.finishSession(session.handle, opts);
    const plain = result.outData ?? new Uint8Array(0);
    return buffer.from(plain.buffer).toString('utf-8');
  }

  // ---------- utils ----------

  private static cryptoRandomBytes(n: number): Uint8Array {
    try {
      const rand = cryptoFramework.createRandom();
      const blob = rand.generateRandomSync(n);
      const offset = blob.data.byteOffset ?? 0;
      const len = blob.data.byteLength ?? n;
      return new Uint8Array(blob.data.buffer, offset, len);
    } catch (e) {
      console.warn(`${TAG} cryptoFramework random fallback to Math.random: ${e}`);
      const bytes = new Uint8Array(n);
      for (let i = 0; i < n; i++) bytes[i] = Math.floor(Math.random() * 256);
      return bytes;
    }
  }

  private static generateHexKey(byteLen: number): string {
    const bytes = SecureKeystore.cryptoRandomBytes(byteLen);
    let hex = '';
    for (let i = 0; i < bytes.length; i++) {
      hex += bytes[i].toString(16).padStart(2, '0');
    }
    return hex;
  }
}
