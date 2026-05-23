import { EffectiveTheme } from './Theme.types';
import { ThemeService, APP_THEME_STORAGE_KEY } from './ThemeService';

/**
 * ThemeProvider（W5-C4）：
 *
 * 在根 @Component 中包裹一次，将当前 effective theme 通过 @Provide('theme')
 * 透传给所有后代组件。后代用 @Consume('theme') theme: EffectiveTheme 接收。
 *
 * 同时通过 @StorageProp 监听 AppStorage 的 'app_theme_mode'，
 * 当 ThemeService.recompute() 写入新值时自动触发重渲染。
 *
 * 用法：
 *   ThemeProvider() {
 *     // ... your tabs / pages
 *   }
 */
@Component
export struct ThemeProvider {
  @StorageProp(APP_THEME_STORAGE_KEY) @Watch('onThemeStorageChange') storageTheme: EffectiveTheme = 'day';
  @Provide('theme') theme: EffectiveTheme = 'day';
  @BuilderParam content: () => void = ThemeProvider.defaultContent;

  @Builder
  static defaultContent() {
  }

  aboutToAppear(): void {
    // 初始同步：用 ThemeService 当前值兜底，避免 @StorageProp 默认 'day' 与
    // 实际 effective 不一致（极少数情况下 EntryAbility.onCreate 还没写入）。
    const current = ThemeService.getCurrentTheme();
    this.theme = current;
    if (this.storageTheme !== current) {
      this.storageTheme = current;
    }
  }

  onThemeStorageChange(): void {
    if (this.storageTheme && this.storageTheme !== this.theme) {
      this.theme = this.storageTheme;
    }
  }

  build() {
    Column() {
      this.content();
    }
    .width('100%')
    .height('100%')
  }
}
