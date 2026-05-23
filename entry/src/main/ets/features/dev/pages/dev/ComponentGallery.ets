/**
 * ComponentGallery —— 组件演示页（W6-C10）
 *
 * 集中展示 W6 全部通用组件的变体与状态，方便：
 *   - 设计师 / PM review 视觉规范
 *   - 工程在引入新组件前快速 preview
 *   - QA 巡检无障碍 / 暗色 / 主题切换覆盖
 *
 * 路由：pages/dev/ComponentGallery（必须在 main_pages.json 中注册）。
 */

import router from '@ohos.router';
import { EffectiveTheme, ThemeMode } from '../../../../core/theme/Theme.types';
import { ThemeService, APP_THEME_STORAGE_KEY } from '../../../../core/theme/ThemeService';
import {
  useColor,
  TextColors,
  BgColors,
  BorderColors,
  AccentColors,
  StateColors,
  BrandPalette,
} from '../../../../core/theme/AppColors';
import {
  TitleStyles,
  HeadlineStyles,
  BodyStyles,
  LabelStyles,
  CaptionStyle,
} from '../../../../core/theme/AppTypography';
import { Spacing, Radius, Elevation, MotionDuration, MotionEasing } from '../../../../core/theme/AppSpacing';

// W6-C1 按钮（来自并行 agent 的产出）
import { AppButton } from '../../../../ui/primitives/Button';
import { AppInput, AppTextArea } from '../../../../ui/primitives/Input';
import { AppCard } from '../../../../ui/primitives/Card';
import { AppList, AppListItem, AppListDataSource, ListItemData, ListGroupData } from '../../../../ui/primitives/List';
import { AppModal, AppSheet, AppDialog, ModalManager } from '../../../../ui/primitives/Modal';
import { AppTabs, AppTabBar, TabBarItem } from '../../../../ui/primitives/Tab';

// W6-C6 / C8 / C9 反馈、加载、空状态
import {
  ToastManager,
  AppSnackbar,
  AppToastLayer,
} from '../../../../ui/primitives/Toast';
import {
  LoadingIndicator,
  AppSkeleton,
} from '../../../../ui/primitives/Loading';
import { AppEmptyState, EmptyStateVariant } from '../../../../ui/primitives/EmptyState';

// ─────────────────────────────────────────────
// Section 类型
// ─────────────────────────────────────────────

type SectionKey =
  | 'buttons'
  | 'inputs'
  | 'cards'
  | 'lists'
  | 'modals'
  | 'tabs'
  | 'feedback'
  | 'theme';

interface SectionDef {
  key: SectionKey;
  label: string;
  available: boolean;
}

const SECTIONS: SectionDef[] = [
  { key: 'buttons',  label: '按钮',     available: true },
  { key: 'inputs',   label: '输入',     available: true },
  { key: 'cards',    label: '卡片',     available: true },
  { key: 'lists',    label: '列表',     available: true },
  { key: 'modals',   label: '弹窗',     available: true },
  { key: 'tabs',     label: 'Tab',      available: true },
  { key: 'feedback', label: '反馈',     available: true },
  { key: 'theme',    label: '主题切换', available: true },
];

// ─────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────

@Entry
@Component
struct ComponentGallery {
  @StorageProp(APP_THEME_STORAGE_KEY) storageTheme: EffectiveTheme = 'day';
  @Provide('theme') theme: EffectiveTheme = 'day';

  @State activeIndex: number = 0;
  @State emptyVariant: EmptyStateVariant = 'no-data';
  @State progress: number = 0.4;

  // Inputs
  @State inputText: string = '';
  @State inputError: string = '';
  @State inputPwd: string = '';
  @State inputSearch: string = '';
  @State textAreaValue: string = '';

  // Modals
  @State showModal: boolean = false;
  @State showSheet: boolean = false;
  @State showDialog: boolean = false;

  // Tabs
  @State innerTabIndex: number = 0;
  @State segmentedIndex: number = 0;
  @State bottomTabIndex: number = 0;

  // Lists
  private listDS: AppListDataSource = new AppListDataSource([
    { id: '1', title: '简爱', subtitle: '夏洛蒂·勃朗特', showChevron: true },
    { id: '2', title: '傲慢与偏见', subtitle: '简·奥斯汀', showChevron: true },
    { id: '3', title: '远大前程', subtitle: '查尔斯·狄更斯', showChevron: true },
    { id: '4', title: '小妇人', subtitle: '路易莎·梅·奥尔科特', showChevron: true },
  ]);
  private listGroups: ListGroupData[] = [
    {
      groupLabel: 'A',
      items: [
        { id: 'a1', title: 'Alice in Wonderland', showChevron: true },
        { id: 'a2', title: 'Anna Karenina', showChevron: true },
      ],
    },
    {
      groupLabel: 'B',
      items: [
        { id: 'b1', title: 'Beowulf', showChevron: true },
        { id: 'b2', title: 'Brave New World', showChevron: true },
      ],
    },
  ];
  private innerTabLabels: string[] = ['全部', '在读', '已读', '收藏'];
  private bottomTabItems: TabBarItem[] = [
    { label: '发现', icon: $r('app.media.app_icon') },
    { label: '书架', icon: $r('app.media.app_icon'), badge: 3 },
    { label: '听书', icon: $r('app.media.app_icon') },
    { label: '我', icon: $r('app.media.app_icon'), showDot: true },
  ];

  aboutToAppear(): void {
    this.theme = ThemeService.getCurrentTheme();
  }

  private get isDark(): boolean {
    return this.theme === 'night';
  }

  private syncThemeFromStorage(): void {
    if (this.storageTheme && this.storageTheme !== this.theme) {
      this.theme = this.storageTheme;
    }
  }

  // ─── Helpers ───
  @Builder
  sectionHeader(name: string, desc: string) {
    Column({ space: Spacing.s1 }) {
      Text(name)
        .fontFamily(TitleStyles.large.fontFamily)
        .fontSize(TitleStyles.large.fontSize)
        .fontWeight(TitleStyles.large.fontWeight)
        .fontColor(useColor(TextColors.primary, this.isDark))
      Text(desc)
        .fontFamily(BodyStyles.small.fontFamily)
        .fontSize(BodyStyles.small.fontSize)
        .fontColor(useColor(TextColors.secondary, this.isDark))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  card(content: () => void) {
    Column() {
      content()
    }
    .width('100%')
    .padding(Spacing.s4)
    .borderRadius(Radius.lg)
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
    .border({
      width: 1,
      color: useColor(BorderColors.secondary, this.isDark),
    })
    .shadow(Elevation.e1 ?? undefined)
    .margin({ bottom: Spacing.s3 })
  }

  @Builder
  rowOf(content: () => void) {
    Row({ space: Spacing.s3 }) {
      content()
    }
    .width('100%')
    .margin({ top: Spacing.s2, bottom: Spacing.s2 })
  }

  // ─── Section: Buttons ───
  @Builder
  buttonsSection() {
    this.card(() => {
      this.sectionHeader('AppButton', '6 变体 × 3 尺寸 × 状态网格')
    })

    // Variants
    this.card(() => {
      Column({ space: Spacing.s3 }) {
        Text('变体（variant）')
          .fontSize(LabelStyles.large.fontSize)
          .fontWeight(LabelStyles.large.fontWeight)
          .fontColor(useColor(TextColors.primary, this.isDark))
        this.rowOf(() => {
          AppButton({ label: '主要',    variant: 'primary',     size: 'md' })
          AppButton({ label: '次要',    variant: 'secondary',   size: 'md' })
          AppButton({ label: '三级',    variant: 'tertiary',    size: 'md' })
        })
        this.rowOf(() => {
          AppButton({ label: '幽灵',    variant: 'ghost',       size: 'md' })
          AppButton({ label: '链接',    variant: 'link',        size: 'md' })
          AppButton({ label: '危险',    variant: 'destructive', size: 'md' })
        })
      }
      .alignItems(HorizontalAlign.Start)
    })

    // Sizes
    this.card(() => {
      Column({ space: Spacing.s3 }) {
        Text('尺寸（size）')
          .fontSize(LabelStyles.large.fontSize)
          .fontWeight(LabelStyles.large.fontWeight)
          .fontColor(useColor(TextColors.primary, this.isDark))
        this.rowOf(() => {
          AppButton({ label: '小', variant: 'primary', size: 'sm' })
          AppButton({ label: '中', variant: 'primary', size: 'md' })
          AppButton({ label: '大', variant: 'primary', size: 'lg' })
        })
      }
      .alignItems(HorizontalAlign.Start)
    })

    // Shapes
    this.card(() => {
      Column({ space: Spacing.s3 }) {
        Text('形状（shape）')
          .fontSize(LabelStyles.large.fontSize)
          .fontWeight(LabelStyles.large.fontWeight)
          .fontColor(useColor(TextColors.primary, this.isDark))
        this.rowOf(() => {
          AppButton({ label: '默认', variant: 'primary', shape: 'default' })
          AppButton({ label: '胶囊', variant: 'primary', shape: 'pill' })
          AppButton({ label: '方', variant: 'primary', shape: 'square' })
        })
      }
      .alignItems(HorizontalAlign.Start)
    })

    // States
    this.card(() => {
      Column({ space: Spacing.s3 }) {
        Text('状态（state）')
          .fontSize(LabelStyles.large.fontSize)
          .fontWeight(LabelStyles.large.fontWeight)
          .fontColor(useColor(TextColors.primary, this.isDark))
        this.rowOf(() => {
          AppButton({ label: '加载中', variant: 'primary', loading: true })
          AppButton({ label: '禁用',  variant: 'primary', disabled: true })
        })
        AppButton({
          label: '全宽订阅按钮',
          variant: 'primary',
          shape: 'pill',
          fullWidth: true,
          onClick: () => ToastManager.success('订阅按钮被点击'),
        })
      }
      .alignItems(HorizontalAlign.Start)
    })
  }

  // ─── Section: Inputs ───
  @Builder
  inputsSection() {
    this.card(() => {
      this.sectionHeader('AppInput / AppTextArea', '单行 / 多行 / 密码 / 搜索 / 错误态')
    })

    this.card(() => {
      Column({ space: Spacing.s4 }) {
        AppInput({
          value: $inputText,
          label: '昵称',
          placeholder: '请输入昵称',
          helperText: '2-20 个字符',
        })
        AppInput({
          value: $inputError,
          label: '邮箱',
          type: 'email',
          placeholder: 'name@example.com',
          errorMessage: this.inputError.length > 0 && !this.inputError.includes('@')
            ? '邮箱格式不正确'
            : '',
        })
        AppInput({
          value: $inputPwd,
          label: '密码',
          type: 'password',
          placeholder: '至少 8 位',
        })
        AppInput({
          value: $inputSearch,
          type: 'search',
          placeholder: '搜索图书 / 作者',
        })
        AppInput({
          value: $inputText,
          label: '已禁用',
          placeholder: '不可编辑',
          disabled: true,
        })
        AppTextArea({
          value: $textAreaValue,
          label: '阅读笔记',
          placeholder: '记录此刻的感受...',
          minRows: 3,
          maxRows: 6,
          maxLength: 200,
        })
      }
      .alignItems(HorizontalAlign.Start)
    })
  }

  // ─── Section: Cards ───
  @Builder
  cardsSection() {
    this.card(() => {
      this.sectionHeader('AppCard', 'elevated / outlined / filled')
    })

    this.card(() => {
      Column({ space: Spacing.s3 }) {
        AppCard({ variant: 'elevated', padding: 'md' }) {
          Text('Elevated 卡片')
            .fontFamily(TitleStyles.medium.fontFamily)
            .fontSize(TitleStyles.medium.fontSize)
            .fontWeight(TitleStyles.medium.fontWeight)
            .fontColor(useColor(TextColors.primary, this.isDark))
          Text('带阴影，从背景中浮起，适合书架卡片、推荐位')
            .fontFamily(BodyStyles.small.fontFamily)
            .fontSize(BodyStyles.small.fontSize)
            .fontColor(useColor(TextColors.secondary, this.isDark))
            .margin({ top: Spacing.s1 })
        }
        AppCard({ variant: 'outlined', padding: 'md' }) {
          Text('Outlined 卡片')
            .fontFamily(TitleStyles.medium.fontFamily)
            .fontSize(TitleStyles.medium.fontSize)
            .fontWeight(TitleStyles.medium.fontWeight)
            .fontColor(useColor(TextColors.primary, this.isDark))
          Text('细边框，无阴影，适合表单容器')
            .fontFamily(BodyStyles.small.fontFamily)
            .fontSize(BodyStyles.small.fontSize)
            .fontColor(useColor(TextColors.secondary, this.isDark))
            .margin({ top: Spacing.s1 })
        }
        AppCard({ variant: 'filled', padding: 'md' }) {
          Text('Filled 卡片')
            .fontFamily(TitleStyles.medium.fontFamily)
            .fontSize(TitleStyles.medium.fontSize)
            .fontWeight(TitleStyles.medium.fontWeight)
            .fontColor(useColor(TextColors.primary, this.isDark))
          Text('实色背景，适合次要信息分组')
            .fontFamily(BodyStyles.small.fontFamily)
            .fontSize(BodyStyles.small.fontSize)
            .fontColor(useColor(TextColors.secondary, this.isDark))
            .margin({ top: Spacing.s1 })
        }
        AppCard({
          variant: 'elevated',
          padding: 'md',
          clickable: true,
          onClick: () => ToastManager.info('卡片被点击'),
        }) {
          Row({ space: Spacing.s3 }) {
            Text('📖')
              .fontSize(28)
            Column({ space: Spacing.s1 }) {
              Text('可点击卡片')
                .fontFamily(TitleStyles.medium.fontFamily)
                .fontSize(TitleStyles.medium.fontSize)
                .fontColor(useColor(TextColors.primary, this.isDark))
              Text('按下有 0.985 缩放反馈')
                .fontFamily(BodyStyles.small.fontFamily)
                .fontSize(BodyStyles.small.fontSize)
                .fontColor(useColor(TextColors.secondary, this.isDark))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      }
      .alignItems(HorizontalAlign.Start)
    })
  }

  // ─── Section: Lists ───
  @Builder
  listsSection() {
    this.card(() => {
      this.sectionHeader('AppList / AppListItem', '扁平 / 分组 / 粘性 header')
    })

    this.card(() => {
      Column({ space: Spacing.s3 }) {
        Text('单行 ListItem 示例（detailed 变体）')
          .fontFamily(LabelStyles.medium.fontFamily)
          .fontSize(LabelStyles.medium.fontSize)
          .fontColor(useColor(TextColors.secondary, this.isDark))

        AppListItem({
          item: {
            id: 'demo-1',
            title: '简爱',
            subtitle: '夏洛蒂·勃朗特',
            trailingText: '32%',
            showChevron: true,
          },
          variant: 'detailed',
          divider: 'bottom',
          isDark: this.isDark,
          onTap: (item: ListItemData) => ToastManager.info(`打开 ${item.title}`),
        })
        AppListItem({
          item: {
            id: 'demo-2',
            title: '傲慢与偏见',
            subtitle: '简·奥斯汀',
            showChevron: true,
          },
          variant: 'compact',
          divider: 'bottom',
          isDark: this.isDark,
          onTap: (item: ListItemData) => ToastManager.info(`打开 ${item.title}`),
        })
        AppListItem({
          item: {
            id: 'demo-3',
            title: '已禁用项',
            disabled: true,
          },
          variant: 'default',
          divider: 'none',
          isDark: this.isDark,
        })
      }
      .alignItems(HorizontalAlign.Start)
    })

    // 分组列表
    this.card(() => {
      Column({ space: Spacing.s2 }) {
        Text('AppList 分组模式（粘性 header）')
          .fontFamily(LabelStyles.medium.fontFamily)
          .fontSize(LabelStyles.medium.fontSize)
          .fontColor(useColor(TextColors.secondary, this.isDark))

        Column() {
          AppList({
            groups: this.listGroups,
            variant: 'compact',
            isDark: this.isDark,
            onItemTap: (item: ListItemData) => ToastManager.info(`点击: ${item.title}`),
          })
        }
        .height(280)
        .width('100%')
        .borderRadius(Radius.def)
        .backgroundColor(useColor(BgColors.elevated, this.isDark))
      }
      .alignItems(HorizontalAlign.Start)
    })
  }

  // ─── Section: Modals ───
  @Builder
  modalsSection() {
    this.card(() => {
      this.sectionHeader('AppModal / AppSheet / AppDialog', '阻塞式 / 半屏 / 警示弹窗')
    })

    this.card(() => {
      Column({ space: Spacing.s3 }) {
        AppButton({
          label: '打开 AppModal',
          variant: 'primary',
          fullWidth: true,
          onClick: () => { this.showModal = true; },
        })
        AppButton({
          label: '打开底部 AppSheet',
          variant: 'secondary',
          fullWidth: true,
          onClick: () => { this.showSheet = true; },
        })
        AppButton({
          label: '打开警示 AppDialog',
          variant: 'destructive',
          fullWidth: true,
          onClick: () => { this.showDialog = true; },
        })
        AppButton({
          label: '系统 confirm（ModalManager）',
          variant: 'tertiary',
          fullWidth: true,
          onClick: () => {
            ModalManager.confirm('删除确认', '确定要删除这条笔记吗？').then((ok: boolean) => {
              if (ok) ToastManager.success('已删除');
              else ToastManager.info('已取消');
            });
          },
        })
      }
      .alignItems(HorizontalAlign.Start)
    })

    // Modal 实例（visible 双向绑定）
    AppModal({
      visible: $showModal,
      title: '示例 Modal',
      size: 'md',
      isDark: this.isDark,
      onClose: () => { this.showModal = false; },
      bodyBuilder: () => {
        Column({ space: Spacing.s3 }) {
          Text('这是一个居中模态弹窗，可承载表单 / 详情。')
            .fontFamily(BodyStyles.medium.fontFamily)
            .fontSize(BodyStyles.medium.fontSize)
            .fontColor(useColor(TextColors.primary, this.isDark))
          AppButton({
            label: '关闭',
            variant: 'primary',
            fullWidth: true,
            onClick: () => { this.showModal = false; },
          })
        }
        .alignItems(HorizontalAlign.Start)
        .padding(Spacing.s4)
      },
    })

    AppSheet({
      visible: $showSheet,
      title: '半屏面板',
      isDark: this.isDark,
      onClose: () => { this.showSheet = false; },
      sheetBody: () => {
        Column({ space: Spacing.s3 }) {
          Text('Sheet 适合可拖拽的次级内容，比如选择章节、调整阅读设置。')
            .fontFamily(BodyStyles.medium.fontFamily)
            .fontSize(BodyStyles.medium.fontSize)
            .fontColor(useColor(TextColors.primary, this.isDark))
          AppButton({
            label: '关闭',
            variant: 'secondary',
            fullWidth: true,
            onClick: () => { this.showSheet = false; },
          })
        }
        .padding(Spacing.s4)
      },
    })

    AppDialog({
      visible: $showDialog,
      variant: 'warning',
      title: '操作提醒',
      message: '此操作不可撤销，确认继续？',
      isDark: this.isDark,
      onConfirm: () => {
        this.showDialog = false;
        ToastManager.warning('已确认');
      },
      onCancel: () => {
        this.showDialog = false;
      },
    })
  }

  // ─── Section: Tabs ───
  @Builder
  tabsSection() {
    this.card(() => {
      this.sectionHeader('AppTabs / AppTabBar', '顶部 / 底部 / 分段控制')
    })

    // 顶部 Tabs（underline）
    this.card(() => {
      Column({ space: Spacing.s2 }) {
        Text('顶部 Tabs（underline）')
          .fontFamily(LabelStyles.medium.fontFamily)
          .fontSize(LabelStyles.medium.fontSize)
          .fontColor(useColor(TextColors.secondary, this.isDark))

        Column() {
          AppTabs({
            labels: this.innerTabLabels,
            currentIndex: $innerTabIndex,
            variant: 'top',
            indicator: 'underline',
            isDark: this.isDark,
            onChange: (i: number) => ToastManager.info(`切换到「${this.innerTabLabels[i]}」`),
            tabContentBuilder: (idx: number) => {
              Column() {
                Text(`Tab ${idx} 内容：${this.innerTabLabels[idx]}`)
                  .fontFamily(BodyStyles.medium.fontFamily)
                  .fontSize(BodyStyles.medium.fontSize)
                  .fontColor(useColor(TextColors.primary, this.isDark))
              }
              .padding(Spacing.s4)
            },
          })
        }
        .height(160)
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
    })

    // Segmented
    this.card(() => {
      Column({ space: Spacing.s2 }) {
        Text('Segmented 分段控制')
          .fontFamily(LabelStyles.medium.fontFamily)
          .fontSize(LabelStyles.medium.fontSize)
          .fontColor(useColor(TextColors.secondary, this.isDark))

        AppTabs({
          labels: ['日间', '夜间', '羊皮纸'],
          currentIndex: $segmentedIndex,
          variant: 'segmented',
          indicator: 'pill',
          isDark: this.isDark,
        })
      }
      .alignItems(HorizontalAlign.Start)
    })

    // 底部 TabBar
    this.card(() => {
      Column({ space: Spacing.s2 }) {
        Text('底部 AppTabBar')
          .fontFamily(LabelStyles.medium.fontFamily)
          .fontSize(LabelStyles.medium.fontSize)
          .fontColor(useColor(TextColors.secondary, this.isDark))

        AppTabBar({
          items: this.bottomTabItems,
          selectedIndex: $bottomTabIndex,
          isDark: this.isDark,
          onSelect: (i: number, item: TabBarItem) => ToastManager.info(`选中：${item.label}`),
        })
      }
      .alignItems(HorizontalAlign.Start)
    })
  }

  // ─── Section: Feedback ───
  @Builder
  feedbackSection() {
    // Toast 触发器
    this.card(() => {
      Column({ space: Spacing.s3 }) {
        this.sectionHeader('Toast / Snackbar', '4 类型 × 3 位置 × 可选 action')
        this.rowOf(() => {
          AppButton({
            label: 'Info',
            variant: 'tertiary',
            size: 'sm',
            onClick: () => ToastManager.info('这是一条提示信息'),
          })
          AppButton({
            label: 'Success',
            variant: 'primary',
            size: 'sm',
            onClick: () => ToastManager.success('保存成功'),
          })
          AppButton({
            label: 'Warning',
            variant: 'secondary',
            size: 'sm',
            onClick: () => ToastManager.warning('剩余空间不足'),
          })
          AppButton({
            label: 'Error',
            variant: 'destructive',
            size: 'sm',
            onClick: () => ToastManager.error('网络请求失败，请稍后重试'),
          })
        })
        this.rowOf(() => {
          AppButton({
            label: '顶部',
            variant: 'ghost',
            size: 'sm',
            onClick: () => ToastManager.show({ message: '从顶部出现', position: 'top', type: 'info' }),
          })
          AppButton({
            label: '居中',
            variant: 'ghost',
            size: 'sm',
            onClick: () => ToastManager.show({ message: '居中显示', position: 'center', type: 'info' }),
          })
          AppButton({
            label: '底部',
            variant: 'ghost',
            size: 'sm',
            onClick: () => ToastManager.show({ message: '从底部出现', position: 'bottom', type: 'info' }),
          })
        })
        AppButton({
          label: '带 撤销 的 Snackbar',
          variant: 'secondary',
          size: 'md',
          fullWidth: true,
          onClick: () => AppSnackbar.show({
            message: '已删除 1 条笔记',
            action: {
              label: '撤销',
              onPress: () => ToastManager.success('已恢复'),
            },
            type: 'info',
          }),
        })
        AppButton({
          label: '清除全部 Toast',
          variant: 'link',
          size: 'sm',
          onClick: () => ToastManager.dismissAll(),
        })
      }
      .alignItems(HorizontalAlign.Start)
    })

    // Loading
    this.card(() => {
      Column({ space: Spacing.s4 }) {
        this.sectionHeader('LoadingIndicator', '3 变体 × 3 尺寸')
        this.rowOf(() => {
          Column({ space: Spacing.s2 }) {
            LoadingIndicator({ variant: 'spinner', size: 'sm', label: 'sm' })
          }
          Column({ space: Spacing.s2 }) {
            LoadingIndicator({ variant: 'spinner', size: 'md', label: 'md' })
          }
          Column({ space: Spacing.s2 }) {
            LoadingIndicator({ variant: 'spinner', size: 'lg', label: 'lg' })
          }
        })
        this.rowOf(() => {
          LoadingIndicator({ variant: 'dots', size: 'md', label: 'dots' })
        })
        Column({ space: Spacing.s2 }) {
          LoadingIndicator({ variant: 'progress', size: 'md', progress: this.progress, label: `progress ${Math.round(this.progress * 100)}%` })
          this.rowOf(() => {
            AppButton({
              label: '−10%',
              variant: 'tertiary',
              size: 'sm',
              onClick: () => { this.progress = Math.max(0, this.progress - 0.1); },
            })
            AppButton({
              label: '+10%',
              variant: 'tertiary',
              size: 'sm',
              onClick: () => { this.progress = Math.min(1, this.progress + 0.1); },
            })
          })
        }
        .alignItems(HorizontalAlign.Start)
      }
      .alignItems(HorizontalAlign.Start)
    })

    // Skeleton
    this.card(() => {
      Column({ space: Spacing.s4 }) {
        this.sectionHeader('AppSkeleton', '6 变体（text / paragraph / avatar / image / card / list-item）')
        AppSkeleton({ variant: 'text', heightVp: 18 })
        AppSkeleton({ variant: 'paragraph', rows: 3, heightVp: 14 })
        Row({ space: Spacing.s3 }) {
          AppSkeleton({ variant: 'avatar', heightVp: 48 })
          Column({ space: Spacing.s2 }) {
            AppSkeleton({ variant: 'text', widthPercent: '70%', heightVp: 14 })
            AppSkeleton({ variant: 'text', widthPercent: '40%', heightVp: 12 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        AppSkeleton({ variant: 'image', heightVp: 120 })
        AppSkeleton({ variant: 'card', widthPercent: '100%' })
        AppSkeleton({ variant: 'list-item' })
      }
      .alignItems(HorizontalAlign.Start)
    })

    // Empty State
    this.card(() => {
      Column({ space: Spacing.s4 }) {
        this.sectionHeader('AppEmptyState', '5 变体（no-data / no-results / error / offline / permission-denied）')
        this.rowOf(() => {
          AppButton({
            label: 'no-data',
            variant: 'tertiary',
            size: 'sm',
            onClick: () => { this.emptyVariant = 'no-data'; },
          })
          AppButton({
            label: 'no-results',
            variant: 'tertiary',
            size: 'sm',
            onClick: () => { this.emptyVariant = 'no-results'; },
          })
          AppButton({
            label: 'error',
            variant: 'tertiary',
            size: 'sm',
            onClick: () => { this.emptyVariant = 'error'; },
          })
        })
        this.rowOf(() => {
          AppButton({
            label: 'offline',
            variant: 'tertiary',
            size: 'sm',
            onClick: () => { this.emptyVariant = 'offline'; },
          })
          AppButton({
            label: 'permission',
            variant: 'tertiary',
            size: 'sm',
            onClick: () => { this.emptyVariant = 'permission-denied'; },
          })
        })

        Column() {
          AppEmptyState({
            variant: this.emptyVariant,
            actionLabel: '重试',
            onAction: () => ToastManager.info('重试中...'),
          })
        }
        .width('100%')
        .borderRadius(Radius.lg)
        .backgroundColor(useColor(BgColors.secondary, this.isDark))
      }
      .alignItems(HorizontalAlign.Start)
    })
  }

  // ─── Section: Theme ───
  @Builder
  themeSection() {
    this.card(() => {
      Column({ space: Spacing.s3 }) {
        this.sectionHeader('主题切换', '当前生效：' + this.theme)
        this.rowOf(() => {
          AppButton({
            label: '日间',
            variant: this.theme === 'day' ? 'primary' : 'secondary',
            size: 'sm',
            onClick: () => {
              ThemeService.setUserTheme('day' as ThemeMode);
              this.syncThemeFromStorage();
            },
          })
          AppButton({
            label: '夜间',
            variant: this.theme === 'night' ? 'primary' : 'secondary',
            size: 'sm',
            onClick: () => {
              ThemeService.setUserTheme('night' as ThemeMode);
              this.syncThemeFromStorage();
            },
          })
          AppButton({
            label: '羊皮纸',
            variant: this.theme === 'sepia' ? 'primary' : 'secondary',
            size: 'sm',
            onClick: () => {
              ThemeService.setUserTheme('sepia' as ThemeMode);
              this.syncThemeFromStorage();
            },
          })
          AppButton({
            label: '跟随系统',
            variant: 'tertiary',
            size: 'sm',
            onClick: () => {
              ThemeService.setUserTheme('system' as ThemeMode);
              this.syncThemeFromStorage();
            },
          })
        })

        // 色板预览
        this.rowOf(() => {
          this.swatch('文本主', useColor(TextColors.primary, this.isDark))
          this.swatch('文本次', useColor(TextColors.secondary, this.isDark))
          this.swatch('强调', useColor(AccentColors.primary, this.isDark))
        })
        this.rowOf(() => {
          this.swatch('成功', useColor(StateColors.success, this.isDark))
          this.swatch('警告', useColor(StateColors.warning, this.isDark))
          this.swatch('错误', useColor(StateColors.error, this.isDark))
        })
      }
      .alignItems(HorizontalAlign.Start)
    })
  }

  @Builder
  swatch(name: string, color: ResourceColor) {
    Column({ space: Spacing.s1 }) {
      Row()
        .width(48)
        .height(48)
        .borderRadius(Radius.def)
        .backgroundColor(color)
        .border({ width: 1, color: useColor(BorderColors.secondary, this.isDark) })
      Text(name)
        .fontSize(CaptionStyle.fontSize)
        .fontColor(useColor(TextColors.secondary, this.isDark))
    }
    .alignItems(HorizontalAlign.Center)
  }

  // ─── Top bar ───
  @Builder
  topBar() {
    Row() {
      Text('返回')
        .fontFamily(LabelStyles.medium.fontFamily)
        .fontSize(LabelStyles.medium.fontSize)
        .fontColor(useColor(TextColors.link, this.isDark))
        .padding(Spacing.s3)
        .onClick(() => router.back())

      Text('组件演示')
        .fontFamily(HeadlineStyles.medium.fontFamily)
        .fontSize(HeadlineStyles.medium.fontSize)
        .fontWeight(HeadlineStyles.medium.fontWeight)
        .fontColor(useColor(TextColors.primary, this.isDark))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Text('W6')
        .fontSize(CaptionStyle.fontSize)
        .fontColor(useColor(TextColors.tertiary, this.isDark))
        .padding({ left: Spacing.s2, right: Spacing.s2, top: 2, bottom: 2 })
        .borderRadius(Radius.sm)
        .backgroundColor(useColor(BgColors.tertiary, this.isDark))
        .margin({ right: Spacing.s4 })
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
    .border({
      width: { bottom: 0.5 },
      color: { bottom: useColor(BorderColors.primary, this.isDark) },
    })
  }

  // ─── Tab bar ───
  @Builder
  tabBar() {
    Scroll() {
      Row({ space: Spacing.s2 }) {
        ForEach(SECTIONS, (s: SectionDef, i: number) => {
          Text(s.label + (s.available ? '' : ' ·'))
            .fontFamily(LabelStyles.medium.fontFamily)
            .fontSize(LabelStyles.medium.fontSize)
            .fontWeight(this.activeIndex === i ? LabelStyles.large.fontWeight : LabelStyles.small.fontWeight)
            .fontColor(this.activeIndex === i
              ? useColor(AccentColors.primary, this.isDark)
              : useColor(TextColors.secondary, this.isDark))
            .padding({ left: Spacing.s3, right: Spacing.s3, top: Spacing.s2, bottom: Spacing.s2 })
            .borderRadius(Radius.full)
            .backgroundColor(this.activeIndex === i
              ? (this.isDark ? '#2C2C2E' : BrandPalette.b100)
              : 'transparent')
            .animation({ duration: MotionDuration.fast, curve: MotionEasing.standard })
            .onClick(() => { this.activeIndex = i; })
        }, (s: SectionDef) => s.key)
      }
      .padding({ left: Spacing.s4, right: Spacing.s4, top: Spacing.s2, bottom: Spacing.s2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .backgroundColor(useColor(BgColors.elevated, this.isDark))
  }

  // ─── Active Section Content ───
  @Builder
  activeContent() {
    Scroll() {
      Column() {
        if (SECTIONS[this.activeIndex].key === 'buttons') {
          this.buttonsSection()
        } else if (SECTIONS[this.activeIndex].key === 'inputs') {
          this.inputsSection()
        } else if (SECTIONS[this.activeIndex].key === 'cards') {
          this.cardsSection()
        } else if (SECTIONS[this.activeIndex].key === 'lists') {
          this.listsSection()
        } else if (SECTIONS[this.activeIndex].key === 'modals') {
          this.modalsSection()
        } else if (SECTIONS[this.activeIndex].key === 'tabs') {
          this.tabsSection()
        } else if (SECTIONS[this.activeIndex].key === 'feedback') {
          this.feedbackSection()
        } else if (SECTIONS[this.activeIndex].key === 'theme') {
          this.themeSection()
        }
      }
      .width('100%')
      .padding({
        left: Spacing.s4,
        right: Spacing.s4,
        top: Spacing.s4,
        bottom: Spacing.s10,
      })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .width('100%')
    .backgroundColor(useColor(BgColors.primary, this.isDark))
  }

  build() {
    Stack() {
      Column() {
        this.topBar()
        this.tabBar()
        this.activeContent()
      }
      .width('100%')
      .height('100%')

      // Toast 全局 overlay
      AppToastLayer()
    }
    .width('100%')
    .height('100%')
  }
}
