/**
 * Faq.ets — W19-C3 常见问题（FAQ）页
 *
 * 功能：
 *   - 6 大分类 tab：账号 / 阅读 / 订阅 / AI 功能 / 数据 / 其它
 *   - Accordion 展开（点击 title 切换 expanded 状态显示 detail）
 *   - 顶部搜索框过滤（命中 question 或 answer 子串）
 *   - 内置 30 条中文常见问题
 *   - 「联系客服」CTA → 跳 FeedbackPage
 *
 * 数据驱动：FAQ_ITEMS 静态数组，category + question + answer。
 */

import router from '@ohos.router';
import {
  useColor,
  TextColors,
  BgColors,
  BorderColors,
  SurfaceColors,
  AccentColors,
  BrandPalette,
} from '../../../core/theme/AppColors';
import {
  FontFamily,
  FontSizeToken,
  FontWeightToken,
  LineHeightToken,
} from '../../../core/theme/AppTypography';
import { Spacing, Radius, MotionDuration, MotionEasing } from '../../../core/theme/AppSpacing';
import { RoutePath } from '../../../core/router/RouteConstants';

// ─────────────────────────────────────────────
// 数据
// ─────────────────────────────────────────────

/** FAQ 类目枚举（key 与 FAQ_ITEMS.category 对齐） */
const FAQ_CATEGORIES: { key: string; label: string }[] = [
  { key: 'all',      label: '全部' },
  { key: 'account',  label: '账号' },
  { key: 'reading',  label: '阅读' },
  { key: 'sub',      label: '订阅' },
  { key: 'ai',       label: 'AI 功能' },
  { key: 'data',     label: '数据' },
  { key: 'other',    label: '其它' },
];

interface FaqItem {
  id: string;
  category: string;
  question: string;
  answer: string;
}

/** 内置 30 条常见问题。后续可改为远端拉取。 */
const FAQ_ITEMS: FaqItem[] = [
  // ── 账号（5）
  { id: 'a1', category: 'account', question: '如何注册账号？', answer: '在登录页选择手机号、华为账号或微信账号即可一键注册。手机号需收到验证码后完成绑定。' },
  { id: 'a2', category: 'account', question: '忘记密码怎么办？', answer: '在登录页点击「忘记密码」，使用绑定的手机号或邮箱接收验证码即可重置。' },
  { id: 'a3', category: 'account', question: '能否更换绑定的手机号？', answer: '可以。进入「我」→「账号设置」→「更换手机号」，需通过原手机号验证后绑定新号。' },
  { id: 'a4', category: 'account', question: '一个账号能在几台设备登录？', answer: '同一账号可在最多 5 台设备同时登录，超出后最早登录的设备会自动下线。' },
  { id: 'a5', category: 'account', question: '如何注销账号？', answer: '进入「我」→「账号设置」→「注销账号」，提交后 30 天内您的所有数据将被永久删除。' },

  // ── 阅读（6）
  { id: 'r1', category: 'reading', question: '为什么有些书需要订阅才能阅读？', answer: '免费用户可阅读公版书全部内容；版权书与精选编辑版仅向 Pro / Premium 订阅用户开放。' },
  { id: 'r2', category: 'reading', question: '如何调节字号和行距？', answer: '阅读页右上角点击「Aa」按钮，可调节字号、行距、字体、背景主题（白天/夜间/纸质）。' },
  { id: 'r3', category: 'reading', question: '阅读进度会自动同步吗？', answer: '会。登录账号后，阅读进度、笔记、生词本会自动多端同步，断网时本地缓存，联网后自动上传。' },
  { id: 'r4', category: 'reading', question: '能否离线阅读？', answer: '可以。下载到本地的书在飞行模式下可正常阅读，已读章节会缓存，回到在线后自动同步进度。' },
  { id: 'r5', category: 'reading', question: '如何添加书签？', answer: '阅读页长按章节段落或点击右上角「书签」图标即可添加；在「我」→「我的书签」中查看全部书签。' },
  { id: 'r6', category: 'reading', question: '为什么 TTS 语音播放有延迟？', answer: '首次加载需下载语音模型（约 50MB），完成后即可秒开；可在设置中预下载常用音色。' },

  // ── 订阅（5）
  { id: 's1', category: 'sub', question: 'Pro 和 Premium 有什么区别？', answer: 'Pro：解锁全部图书 + AI 翻译 + TTS 朗读。Premium：包含 Pro 全部功能 + 高级 AI 学习计划 + 优先客服。' },
  { id: 's2', category: 'sub', question: '订阅可以退款吗？', answer: '订阅服务一经开通不支持主动退款。如有特殊情况（重复扣费、误操作），可在 7 天内联系客服申请。' },
  { id: 's3', category: 'sub', question: '如何取消自动续费？', answer: 'iOS：系统设置 → Apple ID → 订阅。Android / HarmonyOS：应用市场 → 我 → 订阅管理。' },
  { id: 's4', category: 'sub', question: '订阅会跨设备共享吗？', answer: '会。同一账号在所有设备上都可享受订阅权益，无需重复购买。' },
  { id: 's5', category: 'sub', question: '订阅支持发票吗？', answer: '支持。在「我」→「订阅管理」→「发票申请」中提交开票信息，3 个工作日内寄出。' },

  // ── AI 功能（5）
  { id: 'i1', category: 'ai', question: '划词翻译为什么有时不准确？', answer: 'AI 翻译基于上下文推断，复杂句式可能存在偏差。如发现明显错误，请使用「举报」功能反馈。' },
  { id: 'i2', category: 'ai', question: '能否离线使用 AI 翻译？', answer: '基础查词支持离线（CC-CEDICT 词典）；AI 上下文翻译、文章摘要需联网调用云端模型。' },
  { id: 'i3', category: 'ai', question: 'AI 学习计划如何生成？', answer: '基于您的阅读历史、词汇水平、学习时长偏好自动生成。可在「我」→「我的学习计划」查看与调整。' },
  { id: 'i4', category: 'ai', question: '阅读理解题准确率如何？', answer: '由 GPT-4 级别模型生成，正确率 > 95%。如发现错题可点击「反馈」提交，我们会人工复核。' },
  { id: 'i5', category: 'ai', question: 'AI 朗读支持哪些音色？', answer: '内置 8 种英文音色（4 男 4 女）、4 种中文音色，Pro 用户额外解锁 12 种名人模仿音色。' },

  // ── 数据（5）
  { id: 'd1', category: 'data', question: '我的笔记会被他人看到吗？', answer: '不会。所有笔记默认私密，只有您本人可见。如需分享需主动开启「公开分享」。' },
  { id: 'd2', category: 'data', question: '阅读数据存储在哪里？', answer: '存储在中国境内的华为云、阿里云服务器，使用 AES 加密存储，符合等保三级要求。' },
  { id: 'd3', category: 'data', question: '如何导出我的笔记？', answer: '进入「我的笔记」→ 右上角「导出」→ 选择 Markdown / PDF / TXT 格式发送到邮箱。' },
  { id: 'd4', category: 'data', question: '生词本能导入到 Anki 吗？', answer: '可以。「我的生词本」→「导出」→ 选择「Anki APKG 格式」即可下载导入。' },
  { id: 'd5', category: 'data', question: '清除应用缓存会丢失数据吗？', answer: '不会。笔记、生词、订阅都已云同步，仅会清除离线书籍缓存（再次打开会重新下载）。' },

  // ── 其它（4）
  { id: 'o1', category: 'other', question: '应用支持哪些设备？', answer: '当前支持 HarmonyOS NEXT 5.0+ 手机、平板、折叠屏。智慧屏 / 手表版正在适配中。' },
  { id: 'o2', category: 'other', question: '为什么应用要请求通知权限？', answer: '用于学习提醒、新书上架、订阅过期通知。可在「我」→「通知设置」中分类关闭。' },
  { id: 'o3', category: 'other', question: '能否申请添加新书？', answer: '可以。在「发现」页右上角「图书申请」中提交书名 + ISBN，编辑团队会在 2 周内回复。' },
  { id: 'o4', category: 'other', question: '如何举报不当内容？', answer: '点击不当内容右上角「⋯」→「举报」，选择类别提交。我们会在 24 小时内处理。' },
];

// ─────────────────────────────────────────────
// 页面
// ─────────────────────────────────────────────

@Entry
@Component
struct Faq {
  @State private currentCategory: string = 'all';
  @State private searchText: string = '';
  /** 已展开的 item id 集合 */
  @State private expandedIds: Set<string> = new Set<string>();
  @State private isDark: boolean = false;

  /** 过滤后的列表 */
  private get filteredItems(): FaqItem[] {
    const kw = this.searchText.trim().toLowerCase();
    return FAQ_ITEMS.filter((it) => {
      if (this.currentCategory !== 'all' && it.category !== this.currentCategory) return false;
      if (kw.length === 0) return true;
      return it.question.toLowerCase().includes(kw) || it.answer.toLowerCase().includes(kw);
    });
  }

  private toggleExpand(id: string): void {
    const next = new Set<string>(this.expandedIds);
    if (next.has(id)) next.delete(id); else next.add(id);
    this.expandedIds = next;
  }

  private goFeedback(): void {
    router.pushUrl({ url: 'features/support/pages/Feedback' }).catch((_e: Error) => {});
  }

  @Builder
  topBar() {
    Row() {
      Text('< 返回')
        .fontSize(FontSizeToken.callout)
        .fontColor(useColor(AccentColors.primary, this.isDark))
        .onClick(() => router.back())
      Blank()
      Text('常见问题')
        .fontSize(FontSizeToken.headline)
        .fontWeight(FontWeightToken.bold)
        .fontColor(useColor(TextColors.primary, this.isDark))
      Blank()
      Text('客服')
        .fontSize(FontSizeToken.callout)
        .fontColor(useColor(AccentColors.primary, this.isDark))
        .onClick(() => this.goFeedback())
    }
    .width('100%')
    .height(48)
    .padding({ left: Spacing.s4, right: Spacing.s4 })
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
  }

  @Builder
  searchBar() {
    Row({ space: Spacing.s2 }) {
      Text('🔍')
        .fontSize(FontSizeToken.callout)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
      TextInput({ placeholder: '搜索常见问题', text: this.searchText })
        .fontSize(FontSizeToken.callout)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .placeholderColor(useColor(TextColors.tertiary, this.isDark))
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .layoutWeight(1)
        .height(36)
        .onChange((value: string) => { this.searchText = value; })
    }
    .width('92%')
    .height(40)
    .padding({ left: Spacing.s3, right: Spacing.s3 })
    .backgroundColor(useColor(SurfaceColors.input, this.isDark))
    .borderRadius(Radius.lg)
    .margin({ top: Spacing.s3, bottom: Spacing.s3 })
  }

  @Builder
  categoryTabs() {
    Scroll() {
      Row({ space: Spacing.s2 }) {
        ForEach(FAQ_CATEGORIES, (cat: { key: string; label: string }) => {
          Text(cat.label)
            .fontSize(FontSizeToken.subheadline)
            .fontWeight(this.currentCategory === cat.key ? FontWeightToken.bold : FontWeightToken.regular)
            .fontColor(this.currentCategory === cat.key
              ? useColor(TextColors.inverse, this.isDark)
              : useColor(TextColors.secondary, this.isDark))
            .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s2, bottom: Spacing.s2 })
            .backgroundColor(this.currentCategory === cat.key
              ? useColor(AccentColors.primary, this.isDark)
              : useColor(BgColors.secondary, this.isDark))
            .borderRadius(Radius.full)
            .onClick(() => { this.currentCategory = cat.key; })
        }, (cat: { key: string; label: string }) => cat.key)
      }
      .padding({ left: Spacing.s4, right: Spacing.s4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(48)
  }

  @Builder
  faqRow(item: FaqItem) {
    Column({ space: Spacing.s2 }) {
      Row() {
        Text(item.question)
          .fontSize(FontSizeToken.body)
          .fontWeight(FontWeightToken.medium)
          .fontColor(useColor(TextColors.primary, this.isDark))
          .layoutWeight(1)
        Text(this.expandedIds.has(item.id) ? '▴' : '▾')
          .fontSize(FontSizeToken.headline)
          .fontColor(useColor(TextColors.tertiary, this.isDark))
      }
      .width('100%')

      if (this.expandedIds.has(item.id)) {
        Text(item.answer)
          .fontSize(FontSizeToken.subheadline)
          .lineHeight(LineHeightToken.body)
          .fontColor(useColor(TextColors.secondary, this.isDark))
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(Spacing.s4)
    .width('92%')
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
    .borderRadius(Radius.def)
    .margin({ bottom: Spacing.s2 })
    .onClick(() => {
      animateTo({ duration: MotionDuration.fast, curve: MotionEasing.decelerate }, () => {
        this.toggleExpand(item.id);
      });
    })
  }

  @Builder
  emptyHint() {
    Column() {
      Text('未找到相关问题')
        .fontSize(FontSizeToken.callout)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
        .margin({ top: Spacing.s12, bottom: Spacing.s4 })
      Text('点击下方「联系客服」获取人工帮助')
        .fontSize(FontSizeToken.footnote)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  contactCta() {
    Row({ space: Spacing.s2 }) {
      Text('💬')
        .fontSize(FontSizeToken.headline)
      Text('没找到答案？联系客服')
        .fontSize(FontSizeToken.callout)
        .fontWeight(FontWeightToken.medium)
        .fontColor(useColor(TextColors.inverse, this.isDark))
    }
    .width('92%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(useColor(AccentColors.primary, this.isDark))
    .borderRadius(Radius.lg)
    .margin({ top: Spacing.s4, bottom: Spacing.s8 })
    .onClick(() => this.goFeedback())
  }

  build() {
    Column() {
      this.topBar()
      this.searchBar()
      this.categoryTabs()

      Scroll() {
        Column() {
          if (this.filteredItems.length === 0) {
            this.emptyHint()
          } else {
            ForEach(this.filteredItems, (item: FaqItem) => {
              this.faqRow(item)
            }, (item: FaqItem) => item.id)
          }
          this.contactCta()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(useColor(BgColors.primary, this.isDark))
  }
}
