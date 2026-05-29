import dataPreferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import cryptoFramework from '@ohos.security.cryptoFramework';
import buffer from '@ohos.buffer';
import { SecureKeystore } from './SecureKeystore';

const STORE_NAME = 'readmigo_prefs';
const SECURE_PREFIX = '__sec__:';
const NS_SEP = ':';

/** Watch 回调签名：旧值与新值都以 unknown 方式回传，调用方按需 cast。 */
export type PrefsWatcher = (key: string, value: unknown) => void;

/** Bulk set 接受的值类型。 */
export type PrefValue = string | number | boolean | object | unknown[];

/**
 * 通用 typed Preferences 封装。
 * - 单一底层 dataPreferences 文件 (readmigo_prefs)
 * - 命名空间隔离：所有 key 自动加 prefix
 * - flush 100ms debounce，避免高频写入
 * - Watch / unwatch 监听
 * - 加密存储：基于 AES-128-CBC（key 来自 PIN/设备指纹哈希，存内存）
 *
 * 用法：
 *   await PreferencesManager.init(context);
 *   await PreferencesManager.setObject('user', { id: 1 });
 *   const ns = PreferencesManager.createNamespace('reader');
 *   await ns.setNumber('font_size', 18);
 */
export class PreferencesManager {
  private static prefs: dataPreferences.Preferences | null = null;
  private static watchers: Map<string, Set<PrefsWatcher>> = new Map<string, Set<PrefsWatcher>>();
  private static flushTimer: number | null = null;
  private static cryptoKey: cryptoFramework.SymKey | null = null;
  // 默认占位密钥，调用方应在 init 之后通过 setSecureKey 覆盖
  private static readonly DEFAULT_KEY_HEX = '00112233445566778899aabbccddeeff';

  // ---------- lifecycle ----------

  static async init(context: common.UIAbilityContext): Promise<void> {
    PreferencesManager.prefs = await dataPreferences.getPreferences(context, STORE_NAME);
    // 优先用 SecureKeystore 取 HUKS-derived / CSPRNG-generated 设备私有密钥；
    // 失败时退回硬编码默认值（兼容老设备）。
    let masterKey: string = PreferencesManager.DEFAULT_KEY_HEX;
    try {
      await SecureKeystore.init(context);
      masterKey = await SecureKeystore.getOrCreateMasterKey();
    } catch (e) {
      console.warn(`PreferencesManager: SecureKeystore init failed, using DEFAULT_KEY_HEX: ${e}`);
    }
    await PreferencesManager.initCryptoKey(masterKey);
  }

  /** 业务侧若有更安全的 key（如来自 keystore / 用户 PIN），可主动注入。 */
  static async setSecureKey(hexKey32: string): Promise<void> {
    await PreferencesManager.initCryptoKey(hexKey32);
  }

  // ---------- typed get/set ----------

  static async getString(key: string, def: string = ''): Promise<string> {
    const v = await PreferencesManager.rawGet(key, def);
    return typeof v === 'string' ? v : def;
  }

  static async setString(key: string, value: string): Promise<void> {
    await PreferencesManager.rawPut(key, value);
  }

  static async getNumber(key: string, def: number = 0): Promise<number> {
    const v = await PreferencesManager.rawGet(key, def);
    return typeof v === 'number' ? v : def;
  }

  static async setNumber(key: string, value: number): Promise<void> {
    await PreferencesManager.rawPut(key, value);
  }

  static async getBoolean(key: string, def: boolean = false): Promise<boolean> {
    const v = await PreferencesManager.rawGet(key, def);
    return typeof v === 'boolean' ? v : def;
  }

  static async setBoolean(key: string, value: boolean): Promise<void> {
    await PreferencesManager.rawPut(key, value);
  }

  /** 兼容旧调用：保留 setBool / getBool。 */
  static getBool(key: string, def: boolean = false): Promise<boolean> {
    return PreferencesManager.getBoolean(key, def);
  }
  static setBool(key: string, value: boolean): Promise<void> {
    return PreferencesManager.setBoolean(key, value);
  }

  /** 复杂对象使用 JSON 序列化存储。 */
  static async setObject<T>(key: string, value: T): Promise<void> {
    await PreferencesManager.rawPut(key, JSON.stringify(value));
  }

  static async getObject<T>(key: string, def: T | null = null): Promise<T | null> {
    const raw = await PreferencesManager.rawGet(key, '');
    if (typeof raw !== 'string' || raw.length === 0) return def;
    try {
      return JSON.parse(raw) as T;
    } catch (_e) {
      return def;
    }
  }

  /** 数组与 setObject 同源，独立暴露便于类型推导。 */
  static setArray<T>(key: string, value: T[]): Promise<void> {
    return PreferencesManager.setObject<T[]>(key, value);
  }

  static getArray<T>(key: string, def: T[] = []): Promise<T[]> {
    return PreferencesManager.getObject<T[]>(key, def).then((v) => v ?? def);
  }

  // ---------- bulk ----------

  /** 批量写入；只在最后一次 flush，避免逐 key flush 抖动。 */
  static async setMany(map: Record<string, PrefValue>): Promise<void> {
    const prefs = PreferencesManager.prefs;
    if (!prefs) return;
    const keys = Object.keys(map);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      const v = map[k];
      const stored: dataPreferences.ValueType = (typeof v === 'object' || Array.isArray(v))
        ? JSON.stringify(v)
        : v as dataPreferences.ValueType;
      await prefs.put(k, stored);
      PreferencesManager.notifyWatchers(k, v);
    }
    PreferencesManager.scheduleFlush();
  }

  static async deleteMany(keys: string[]): Promise<void> {
    const prefs = PreferencesManager.prefs;
    if (!prefs) return;
    for (let i = 0; i < keys.length; i++) {
      await prefs.delete(keys[i]);
      PreferencesManager.notifyWatchers(keys[i], undefined);
    }
    PreferencesManager.scheduleFlush();
  }

  static async clear(): Promise<void> {
    const prefs = PreferencesManager.prefs;
    if (!prefs) return;
    await prefs.clear();
    PreferencesManager.scheduleFlush();
    PreferencesManager.watchers.forEach((set, k) => PreferencesManager.notifyWatchers(k, undefined));
  }

  static async remove(key: string): Promise<void> {
    const prefs = PreferencesManager.prefs;
    if (!prefs) return;
    await prefs.delete(key);
    PreferencesManager.notifyWatchers(key, undefined);
    PreferencesManager.scheduleFlush();
  }

  // ---------- watch ----------

  static watch(key: string, cb: PrefsWatcher): () => void {
    let set = PreferencesManager.watchers.get(key);
    if (!set) {
      set = new Set<PrefsWatcher>();
      PreferencesManager.watchers.set(key, set);
    }
    set.add(cb);
    return () => PreferencesManager.unwatch(key, cb);
  }

  static unwatch(key: string, cb: PrefsWatcher): void {
    const set = PreferencesManager.watchers.get(key);
    if (set) {
      set.delete(cb);
      if (set.size === 0) PreferencesManager.watchers.delete(key);
    }
  }

  // ---------- secure (encrypted) ----------

  /** 敏感数据存储：透明 AES-128-CBC 加解密；落盘 base64 字符串。 */
  static async setSecure(key: string, value: string): Promise<void> {
    const cipherText = await PreferencesManager.encrypt(value);
    await PreferencesManager.rawPut(SECURE_PREFIX + key, cipherText);
  }

  static async getSecure(key: string, def: string = ''): Promise<string> {
    const raw = await PreferencesManager.rawGet(SECURE_PREFIX + key, '');
    if (typeof raw !== 'string' || raw.length === 0) return def;
    try {
      return await PreferencesManager.decrypt(raw);
    } catch (_e) {
      return def;
    }
  }

  // ---------- namespace ----------

  static createNamespace(name: string): NamespacedPreferences {
    return new NamespacedPreferences(name);
  }

  // ---------- internals ----------

  private static async rawGet(key: string, def: dataPreferences.ValueType): Promise<dataPreferences.ValueType> {
    const prefs = PreferencesManager.prefs;
    if (!prefs) return def;
    return await prefs.get(key, def);
  }

  private static async rawPut(key: string, value: dataPreferences.ValueType): Promise<void> {
    const prefs = PreferencesManager.prefs;
    if (!prefs) return;
    await prefs.put(key, value);
    PreferencesManager.notifyWatchers(key, value);
    PreferencesManager.scheduleFlush();
  }

  /** 100ms debounce flush，连续写入只触发一次磁盘 IO。 */
  private static scheduleFlush(): void {
    if (PreferencesManager.flushTimer !== null) return;
    PreferencesManager.flushTimer = setTimeout(async () => {
      PreferencesManager.flushTimer = null;
      const prefs = PreferencesManager.prefs;
      if (prefs) await prefs.flush();
    }, 100);
  }

  private static notifyWatchers(key: string, value: unknown): void {
    const set = PreferencesManager.watchers.get(key);
    if (!set) return;
    set.forEach((cb) => {
      try { cb(key, value); } catch (_e) { /* swallow */ }
    });
  }

  private static async initCryptoKey(hexKey32: string): Promise<void> {
    // 16 字节 = 32 hex 字符；AES128
    const keyBytes = PreferencesManager.hexToBytes(hexKey32.padEnd(32, '0').slice(0, 32));
    const symKeyGen = cryptoFramework.createSymKeyGenerator('AES128');
    const data: cryptoFramework.DataBlob = { data: keyBytes };
    PreferencesManager.cryptoKey = await symKeyGen.convertKey(data);
  }

  private static async encrypt(plain: string): Promise<string> {
    const key = PreferencesManager.cryptoKey;
    if (!key) throw new Error('Crypto key not initialized');
    const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
    const ivBytes = PreferencesManager.randomBytes(16);
    const iv: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: { data: ivBytes } };
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, iv);
    const input: cryptoFramework.DataBlob = { data: new Uint8Array(buffer.from(plain, 'utf-8').buffer) };
    const out = await cipher.doFinal(input);
    // 拼接 iv + ciphertext，统一 base64 落盘
    const merged = new Uint8Array(ivBytes.length + out.data.length);
    merged.set(ivBytes, 0);
    merged.set(out.data, ivBytes.length);
    return buffer.from(merged.buffer).toString('base64');
  }

  private static async decrypt(b64: string): Promise<string> {
    const key = PreferencesManager.cryptoKey;
    if (!key) throw new Error('Crypto key not initialized');
    const all = new Uint8Array(buffer.from(b64, 'base64').buffer);
    const ivBytes = all.slice(0, 16);
    const cipherBytes = all.slice(16);
    const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
    const iv: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: { data: ivBytes } };
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, iv);
    const input: cryptoFramework.DataBlob = { data: cipherBytes };
    const out = await cipher.doFinal(input);
    return buffer.from(out.data.buffer).toString('utf-8');
  }

  private static hexToBytes(hex: string): Uint8Array {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
    }
    return bytes;
  }

  private static randomBytes(n: number): Uint8Array {
    // 密码学安全 RNG：用 cryptoFramework CSPRNG 生成 IV / nonce。
    // 旧实现 Math.random 不是 CSPRNG，IV 可预测，违反 AES-CBC 安全前提，已修复。
    try {
      const rand = cryptoFramework.createRandom();
      const blob = rand.generateRandomSync(n);
      const offset = blob.data.byteOffset ?? 0;
      const len = blob.data.byteLength ?? n;
      return new Uint8Array(blob.data.buffer, offset, len);
    } catch (e) {
      console.warn(`PreferencesManager.randomBytes: CSPRNG unavailable, falling back to Math.random: ${e}`);
      const bytes = new Uint8Array(n);
      for (let i = 0; i < n; i++) bytes[i] = Math.floor(Math.random() * 256);
      return bytes;
    }
  }
}

/** 子命名空间：所有 key 自动加 prefix，避免不同模块互相覆盖。 */
export class NamespacedPreferences {
  constructor(private readonly ns: string) {}

  private k(key: string): string { return this.ns + NS_SEP + key; }

  getString(key: string, def: string = ''): Promise<string> {
    return PreferencesManager.getString(this.k(key), def);
  }
  setString(key: string, value: string): Promise<void> {
    return PreferencesManager.setString(this.k(key), value);
  }
  getNumber(key: string, def: number = 0): Promise<number> {
    return PreferencesManager.getNumber(this.k(key), def);
  }
  setNumber(key: string, value: number): Promise<void> {
    return PreferencesManager.setNumber(this.k(key), value);
  }
  getBoolean(key: string, def: boolean = false): Promise<boolean> {
    return PreferencesManager.getBoolean(this.k(key), def);
  }
  setBoolean(key: string, value: boolean): Promise<void> {
    return PreferencesManager.setBoolean(this.k(key), value);
  }
  getObject<T>(key: string, def: T | null = null): Promise<T | null> {
    return PreferencesManager.getObject<T>(this.k(key), def);
  }
  setObject<T>(key: string, value: T): Promise<void> {
    return PreferencesManager.setObject<T>(this.k(key), value);
  }
  getArray<T>(key: string, def: T[] = []): Promise<T[]> {
    return PreferencesManager.getArray<T>(this.k(key), def);
  }
  setArray<T>(key: string, value: T[]): Promise<void> {
    return PreferencesManager.setArray<T>(this.k(key), value);
  }
  remove(key: string): Promise<void> { return PreferencesManager.remove(this.k(key)); }
  watch(key: string, cb: PrefsWatcher): () => void {
    return PreferencesManager.watch(this.k(key), cb);
  }
}
