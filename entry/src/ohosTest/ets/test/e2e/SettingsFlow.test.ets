// SettingsFlow.test.ets
// Phase 2 e2e — Reader 设置 sheet 完整流程：字号 / 行距 / 主题 / 翻页模式。
//
// 与 SettingsStore + ThemeService 联动；不依赖 UI driver，直接驱动 store API
// 模拟用户「点击档位 → 触发 setReaderXxxLevel」的副作用。

import { describe, beforeAll, beforeEach, afterAll, it, expect } from '@ohos/hypium';
import { MockSetup } from '../utils/MockSetup';
import {
  SettingsStore,
  FONT_SIZE_LEVEL_MAP,
  LINE_HEIGHT_LEVEL_MAP,
  FontSizeLevel,
  LineHeightLevel,
  PageTurnMode,
  ReaderTheme,
} from '../../../../main/ets/store/SettingsStore';
import { StoreKeys } from '../../../../main/ets/store/StoreKeys';

export default function settingsFlowE2ETest() {
  describe('E2E_SettingsFlow', () => {
    beforeAll(() => {
      MockSetup.installAll();
    });

    afterAll(() => {
      MockSetup.restoreAll();
    });

    beforeEach(() => {
      MockSetup.resetAll();
      // 把 store 重置到默认档位
      SettingsStore.setReaderFontSizeLevel(3);
      SettingsStore.setReaderLineHeightLevel(2);
      SettingsStore.setReaderTheme('day');
      SettingsStore.setReaderPageTurnMode('paged');
    });

    // ── 字号 5 档 ───────────────────────────────────────────────
    it('font_size_should_relayout_through_5_levels', 0, () => {
      const expectedSizes: Record<FontSizeLevel, number> = FONT_SIZE_LEVEL_MAP;
      const levels: FontSizeLevel[] = [1, 2, 3, 4, 5];

      for (const lvl of levels) {
        SettingsStore.setReaderFontSizeLevel(lvl);
        // 档位写入
        expect(SettingsStore.getReaderFontSizeLevel()).assertEqual(lvl);
        // 实际字号同步
        expect(SettingsStore.getReaderFontSize()).assertEqual(expectedSizes[lvl]);
        // AppStorage 也应同步（响应式 relayout 触发条件）
        const stored = AppStorage.Get<number>(StoreKeys.SETTINGS_READER_FONT_SIZE);
        expect(stored).assertEqual(expectedSizes[lvl]);
      }
    });

    // ── 行距 3 档 ───────────────────────────────────────────────
    it('line_height_should_switch_through_3_levels', 0, () => {
      const map = LINE_HEIGHT_LEVEL_MAP;
      const levels: LineHeightLevel[] = [1, 2, 3];

      for (const lvl of levels) {
        SettingsStore.setReaderLineHeightLevel(lvl);
        expect(SettingsStore.getReaderLineHeightLevel()).assertEqual(lvl);
        expect(SettingsStore.getReaderLineHeight()).assertEqual(map[lvl]);
      }
    });

    // ── 主题 4 档（day / night / paper / sepia）─────────────────
    it('reader_theme_should_persist_for_each_of_4_modes', 0, () => {
      const themes: ReaderTheme[] = ['day', 'night', 'paper', 'sepia'];

      for (const t of themes) {
        SettingsStore.setReaderTheme(t);
        expect(SettingsStore.getReaderTheme()).assertEqual(t);
        // AppStorage 同步
        const got = AppStorage.Get<ReaderTheme>(StoreKeys.SETTINGS_READER_THEME);
        expect(got).assertEqual(t);
      }
    });

    // ── 翻页模式 ──────────────────────────────────────────────
    it('page_turn_mode_should_switch_between_paged_scroll_horizontal', 0, () => {
      const modes: PageTurnMode[] = ['paged', 'scroll', 'horizontal'];

      for (const m of modes) {
        SettingsStore.setReaderPageTurnMode(m);
        expect(SettingsStore.getReaderPageTurnMode()).assertEqual(m);
      }
    });

    // ── 边界：非法档位归一 ────────────────────────────────────
    it('font_size_level_should_clamp_invalid_input', 0, () => {
      // 通过 setReaderFontSize 越界 → clamp 到 14..24
      SettingsStore.setReaderFontSize(2);
      expect(SettingsStore.getReaderFontSize()).assertEqual(14);
      SettingsStore.setReaderFontSize(99);
      expect(SettingsStore.getReaderFontSize()).assertEqual(24);
    });

    // ── 切回默认主题验证 listener 不被遗留 ─────────────────────
    it('switching_back_to_day_should_resync_appstorage', 0, () => {
      SettingsStore.setReaderTheme('night');
      expect(AppStorage.Get<ReaderTheme>(StoreKeys.SETTINGS_READER_THEME)).assertEqual('night');
      SettingsStore.setReaderTheme('day');
      expect(AppStorage.Get<ReaderTheme>(StoreKeys.SETTINGS_READER_THEME)).assertEqual('day');
    });
  });
}
