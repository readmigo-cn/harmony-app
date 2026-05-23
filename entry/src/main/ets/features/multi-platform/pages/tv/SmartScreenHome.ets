/**
 * SmartScreenHome.ets — W15-C3 智慧屏首页（大屏 16:9）
 *
 * 布局（横屏 1920×1080+）：
 *   ┌────────────────────────────────────────────────────────────┐
 *   │ Banner Carousel (16:9, 5s autoplay, focus 时停止)          │   高 36%
 *   ├────────────────────────────────────────────────────────────┤
 *   │ 分类 Grid 4 列 × 2 行                                       │   高 40%
 *   │  [📖 阅读] [🎧 听书] [📚 书架] [🔍 发现]                     │
 *   │  [⭐ 推荐] [📊 数据] [⚙️  设置] [👤 我的]                    │
 *   ├────────────────────────────────────────────────────────────┤
 *   │ 最近阅读 Row (横向 List)                                    │   高 24%
 *   └────────────────────────────────────────────────────────────┘
 *
 * 焦点机制：
 *   - 默认焦点：第一个分类 (defaultFocus(true))
 *   - DPAD 走 ArkUI focus chain（每个 focusable 项有 onFocus/onBlur 切换 scale）
 *   - 焦点态：scale 1.05 + 4vp brand 色边框 + 阴影
 *
 * 大屏视觉要点：
 *   - 字号统一 ≥ 32vp（标题 56vp）
 *   - 行高 1.4，避免视距 3m 看不清
 *   - 4:3 安全边距：左右 80vp，上下 60vp（避免老电视过扫）
 *   - 高对比度：背景 #0F1018 / 主文字 #F5F5F7
 */

import { AppColors } from '../../../../core/theme/AppColors';
import { Spacing, Radius } from '../../../../core/theme/AppSpacing';
import { RemoteController, FocusStyle } from '../../../../features/multi-platform/service/RemoteController';
import router from '@ohos.router';

interface CategoryItem {
  key: string;
  icon: string;
  title: string;
  subtitle: string;
  target: string; // smart_screen_target value
}

interface RecentBook {
  id: string;
  title: string;
  author: string;
  cover: string;
  progress: number; // 0..1
}

interface BannerSlide {
  id: string;
  title: string;
  subtitle: string;
  bg: string;
}

const CATEGORIES: CategoryItem[] = [
  { key: 'reader',    icon: '📖', title: '继续阅读',  subtitle: '上次的书',     target: 'reader' },
  { key: 'audio',     icon: '🎧', title: '有声书',    subtitle: '专业朗读',     target: 'audiobook' },
  { key: 'library',   icon: '📚', title: '我的书架',  subtitle: '已收藏',       target: 'library' },
  { key: 'discover',  icon: '🔍', title: '发现',      subtitle: '编辑精选',     target: 'discover' },
  { key: 'recommend', icon: '⭐', title: '今日推荐',  subtitle: 'AI 个性化',    target: 'recommend' },
  { key: 'stats',     icon: '📊', title: '阅读数据',  subtitle: '本周/本月',    target: 'stats' },
  { key: 'settings',  icon: '⚙️',  title: '设置',     subtitle: '字号/主题',    target: 'settings' },
  { key: 'me',        icon: '👤', title: '我的',      subtitle: '账号管理',     target: 'me' },
];

const BANNER_SLIDES: BannerSlide[] = [
  { id: 'b1', title: '春日推荐：经典文学合集', subtitle: '《傲慢与偏见》《简·爱》《红与黑》', bg: '#3B2A6B' },
  { id: 'b2', title: '听书新上：科幻巨制',    subtitle: '《三体》全集 · 专业播音演绎',       bg: '#1F4E79' },
  { id: 'b3', title: 'AI 大屏阅读体验',      subtitle: '48-72pt 字号 · 自动滚动 · 沉浸沉浸', bg: '#5B21B6' },
];

@Entry
@Component
struct SmartScreenHome {
  @State focusedCategory: string = '';
  @State focusedBook: string = '';
  @State bannerIndex: number = 0;
  @StorageLink('smart_screen_target') target: string = 'home';
  @StorageLink('reading_current_book') lastBookId: string = '';

  // Banner 轮播 timer
  private timerId: number = -1;
  private unlistenRemote: (() => void) | null = null;

  // 演示用最近阅读
  private recentBooks: RecentBook[] = [
    { id: 'r1', title: 'Pride and Prejudice', author: 'Jane Austen',     cover: '#7C3AED', progress: 0.42 },
    { id: 'r2', title: 'Jane Eyre',           author: 'Charlotte Brontë', cover: '#0EA5E9', progress: 0.18 },
    { id: 'r3', title: 'The Three-Body',      author: '刘慈欣',           cover: '#16A34A', progress: 0.71 },
    { id: 'r4', title: '1984',                author: 'George Orwell',    cover: '#DC2626', progress: 0.05 },
    { id: 'r5', title: 'Sapiens',             author: 'Yuval Harari',     cover: '#F59E0B', progress: 0.89 },
  ];

  aboutToAppear(): void {
    // 5s 自动轮播
    this.timerId = setInterval(() => {
      this.bannerIndex = (this.bannerIndex + 1) % BANNER_SLIDES.length;
    }, 5000);

    // 监听遥控器：MENU 直接跳设置；BACK 在首页提示退出
    this.unlistenRemote = RemoteController.listen((key) => {
      if (key === 'MENU') {
        this.target = 'settings';
        return true;
      }
      return false; // 其它键交给 ArkUI focus chain
    });
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) clearInterval(this.timerId);
    if (this.unlistenRemote) this.unlistenRemote();
  }

  private openCategory(item: CategoryItem): void {
    this.target = item.target;
    if (item.target === 'reader') {
      router.pushUrl({ url: 'pages/tv/SmartScreenReader' });
    } else if (item.target === 'audiobook') {
      router.pushUrl({ url: 'pages/tv/SmartScreenAudiobook' });
    } else {
      // 其他 target 占位 toast
      console.info(`SmartScreenHome open ${item.target}`);
    }
  }

  @Builder
  BannerSlideBuilder(slide: BannerSlide) {
    Column() {
      Text(slide.title)
        .fontSize(56)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .margin({ bottom: Spacing.s4 })
      Text(slide.subtitle)
        .fontSize(28)
        .fontColor('#E5E5E7')
        .opacity(0.9)
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.End)
    .width('100%')
    .height('100%')
    .padding({ left: 96, right: 96, bottom: 64 })
    .backgroundColor(slide.bg)
    .borderRadius(Radius.xl)
  }

  @Builder
  CategoryCard(item: CategoryItem) {
    Column({ space: Spacing.s3 }) {
      Text(item.icon).fontSize(72)
      Text(item.title)
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary)
      Text(item.subtitle)
        .fontSize(22)
        .fontColor(AppColors.textSecondary)
        .opacity(0.85)
    }
    .width('100%')
    .height(220)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppColors.bgSecondary)
    .borderRadius(Radius.xl)
    .borderWidth(this.focusedCategory === item.key ? FocusStyle.borderWidth : 0)
    .borderColor(AppColors.brand)
    .scale(this.focusedCategory === item.key ? FocusStyle.scale : { x: 1, y: 1 })
    .shadow(this.focusedCategory === item.key
      ? { radius: 24, color: '#00000099', offsetY: 8 }
      : { radius: 0, color: '#00000000', offsetY: 0 })
    .animation({ duration: FocusStyle.duration, curve: Curve.EaseOut })
    .focusable(true)
    .defaultFocus(item.key === 'reader')
    .onFocus(() => { this.focusedCategory = item.key; })
    .onBlur(() => { if (this.focusedCategory === item.key) this.focusedCategory = ''; })
    .onClick(() => this.openCategory(item))
  }

  @Builder
  RecentBookCard(book: RecentBook) {
    Column({ space: Spacing.s2 }) {
      // 模拟封面（纯色 + 标题首字）
      Stack({ alignContent: Alignment.Center }) {
        Column().width('100%').height('100%').backgroundColor(book.cover).borderRadius(Radius.lg)
        Text(book.title.charAt(0))
          .fontSize(64)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .opacity(0.7)
      }
      .width(180)
      .height(260)

      Text(book.title)
        .fontSize(22)
        .fontColor(AppColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(180)
      Text(`${Math.round(book.progress * 100)}%  ·  ${book.author}`)
        .fontSize(18)
        .fontColor(AppColors.textSecondary)
        .maxLines(1)
        .width(180)
    }
    .padding(Spacing.s3)
    .borderRadius(Radius.xl)
    .borderWidth(this.focusedBook === book.id ? FocusStyle.borderWidth : 0)
    .borderColor(AppColors.brand)
    .scale(this.focusedBook === book.id ? FocusStyle.scale : { x: 1, y: 1 })
    .animation({ duration: FocusStyle.duration, curve: Curve.EaseOut })
    .focusable(true)
    .onFocus(() => { this.focusedBook = book.id; })
    .onBlur(() => { if (this.focusedBook === book.id) this.focusedBook = ''; })
    .onClick(() => {
      AppStorage.SetOrCreate<string>('reading_current_book', book.id);
      router.pushUrl({ url: 'pages/tv/SmartScreenReader' });
    })
  }

  build() {
    Column() {
      // ── Banner 区 (高 36%) ──
      Stack({ alignContent: Alignment.Center }) {
        ForEach(BANNER_SLIDES, (s: BannerSlide, idx: number) => {
          if (idx === this.bannerIndex) {
            this.BannerSlideBuilder(s)
          }
        }, (s: BannerSlide) => s.id)

        // 指示点
        Row({ space: Spacing.s2 }) {
          ForEach(BANNER_SLIDES, (_s: BannerSlide, idx: number) => {
            Circle({ width: 16, height: 16 })
              .fill(idx === this.bannerIndex ? '#FFFFFF' : '#FFFFFF66')
          }, (s: BannerSlide) => `dot-${s.id}`)
        }
        .position({ x: '50%', y: '90%' })
        .translate({ x: -40, y: 0 })
      }
      .width('100%')
      .height('36%')
      .padding({ left: 80, right: 80, top: 40 })

      // ── 分类 Grid 4 列 (高 42%) ──
      Grid() {
        ForEach(CATEGORIES, (item: CategoryItem) => {
          GridItem() { this.CategoryCard(item) }
        }, (item: CategoryItem) => item.key)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsTemplate('1fr 1fr')
      .columnsGap(Spacing.s5)
      .rowsGap(Spacing.s5)
      .width('100%')
      .height('42%')
      .padding({ left: 80, right: 80, top: 24, bottom: 16 })

      // ── 最近阅读 Row (高 22%) ──
      Column({ space: Spacing.s3 }) {
        Text('最近阅读')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .padding({ left: 80 })
        List({ space: Spacing.s5 }) {
          ForEach(this.recentBooks, (book: RecentBook) => {
            ListItem() { this.RecentBookCard(book) }
          }, (book: RecentBook) => book.id)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(330)
        .padding({ left: 80, right: 80 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .height('22%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0F1018')
  }
}
