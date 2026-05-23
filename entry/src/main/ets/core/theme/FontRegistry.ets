import font from '@ohos.font';
import resourceManager from '@ohos.resourceManager';
import common from '@ohos.app.ability.common';

const TAG = 'FontRegistry';

/**
 * 字体常量（W5-C5）。所有页面只引用这里。
 *
 * 系统字体（HarmonyOS Sans / Mono）由系统管理，无需注册，仅做命名参考。
 * 阅读字体（衬线/中文衬线）需要 register，文件由 W7 phase 提供。
 */
export class FontFamilies {
  static readonly ui: string = 'HarmonyOS Sans';
  static readonly uiMonospace: string = 'HarmonyOS Mono';

  // 阅读字体（占位，真正字体文件 W7 加入）
  static readonly readingSerif: string = 'CrimsonPro-Regular';
  static readonly readingSerifBold: string = 'CrimsonPro-Bold';
  static readonly readingChineseSans: string = 'SourceHanSansCN';
  static readonly readingChineseSerif: string = 'SourceHanSerifCN';
}

/** 兼容老调用（保持 task spec 给的形状）。 */
export const FontFamiliesObject = {
  ui: FontFamilies.ui,
  uiMonospace: FontFamilies.uiMonospace,
  reading: {
    serif: FontFamilies.readingSerif,
    serifBold: FontFamilies.readingSerifBold,
    sansSerifChinese: FontFamilies.readingChineseSans,
    serifChinese: FontFamilies.readingChineseSerif,
  },
};

interface FontEntry {
  familyName: string;
  rawfilePath: string; // 相对 rawfile/ 的路径
}

/**
 * 注册表：family -> rawfile path
 *
 * 命名规则：rawfile/fonts/{family}.ttf
 * W7 提供文件之前，registerFonts() 不会因找不到文件抛错——
 * 我们先 probe rawfile 是否存在，缺则只打 warning。
 */
const FONT_ENTRIES: FontEntry[] = [
  { familyName: FontFamilies.readingSerif, rawfilePath: 'fonts/CrimsonPro-Regular.ttf' },
  { familyName: FontFamilies.readingSerifBold, rawfilePath: 'fonts/CrimsonPro-Bold.ttf' },
  { familyName: FontFamilies.readingChineseSans, rawfilePath: 'fonts/SourceHanSansCN-Regular.ttf' },
  { familyName: FontFamilies.readingChineseSerif, rawfilePath: 'fonts/SourceHanSerifCN-Regular.ttf' },
];

export class FontRegistry {
  private static registered: Set<string> = new Set();

  /**
   * 启动期注册。EntryAbility.onCreate 调用。
   * 不抛错，缺文件只打 warning。
   */
  static async registerFonts(context: common.UIAbilityContext): Promise<void> {
    const rm = context.resourceManager;
    for (const entry of FONT_ENTRIES) {
      if (FontRegistry.registered.has(entry.familyName)) continue;
      try {
        const exists = await FontRegistry.rawfileExists(rm, entry.rawfilePath);
        if (!exists) {
          console.warn(`${TAG} font file missing, skip: ${entry.rawfilePath} (W7 will provide)`);
          continue;
        }
        font.registerFont({
          familyName: entry.familyName,
          familySrc: $rawfile(entry.rawfilePath),
        });
        FontRegistry.registered.add(entry.familyName);
        console.info(`${TAG} registered: ${entry.familyName}`);
      } catch (err) {
        const e = err as Error;
        console.warn(`${TAG} register failed for ${entry.familyName}: ${e.message}`);
      }
    }
  }

  static isRegistered(family: string): boolean {
    return FontRegistry.registered.has(family);
  }

  /**
   * 安全 fallback：reading 字体未注册时回退到系统 UI 字体，避免 Text 渲染失败。
   */
  static resolveReadingSerif(): string {
    return FontRegistry.isRegistered(FontFamilies.readingSerif)
      ? FontFamilies.readingSerif
      : FontFamilies.ui;
  }

  static resolveReadingChineseSerif(): string {
    return FontRegistry.isRegistered(FontFamilies.readingChineseSerif)
      ? FontFamilies.readingChineseSerif
      : FontFamilies.ui;
  }

  // ---- internal ----

  private static async rawfileExists(
    rm: resourceManager.ResourceManager,
    path: string,
  ): Promise<boolean> {
    try {
      // getRawFileContent 在文件不存在时 reject
      const data = await rm.getRawFileContent(path);
      return !!data && data.length > 0;
    } catch {
      return false;
    }
  }
}
