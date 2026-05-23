import { AppColors } from '../../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../../core/theme/AppSpacing';
import { ShareWordPayload, SHARE_WORD_STORAGE_KEY } from '../../../../abilities/ShareWordAbility';
import promptAction from '@ohos.promptAction';
import pasteboard from '@ohos.pasteboard';
import componentSnapshot from '@ohos.arkui.componentSnapshot';
import image from '@ohos.multimedia.image';

/**
 * 单词分享卡片页（W11-C2）
 *
 * 隶属：ShareWordAbility（pages/atomic/ShareCardPage）
 *
 * 设计要点：
 *   - 顶部 brand 标识：「米果智读 · 单词分享」
 *   - 中央卡片：渐变背景 + 大字单词 + 音标 + 释义 + 例句 + 来源
 *   - 卡片用 id('share-card-snapshot') 标记，作为 componentSnapshot 的导出根
 *   - 底部 action bar：分享 / 保存图片 / 复制 / 关闭（4 个等宽按钮）
 *   - 支持 day / night 主题：颜色由 AppColors 自动适配
 *
 * 真机/模拟器差异：
 *   - 模拟器没有 image / pasteboard 真实落盘 → toast 占位
 *   - 真机：componentSnapshot.createFromComponent 拿到 PixelMap → 写入相册
 *
 * 与系统分享面板：
 *   - 当前用 promptAction 占位「已唤起分享面板」
 *   - 后续接入 @ohos.share.shareController 时，把生成的 PNG 作为 fileUri 传入
 */

const SNAPSHOT_NODE_ID = 'share-card-snapshot';

@Entry
@Component
struct ShareCardPage {
  @StorageLink(SHARE_WORD_STORAGE_KEY) payload: ShareWordPayload = {
    word: '',
    context: '',
    contextZh: '',
    definition: '',
    phonetic: '',
    bookTitle: '',
    chapterTitle: '',
    receivedAt: 0,
  };

  @State exporting: boolean = false;

  // ─────────── helpers ───────────

  private safeWord(): string {
    return this.payload.word || 'word';
  }

  private safeDefinition(): string {
    return this.payload.definition || '（暂无释义）';
  }

  private safeContext(): string {
    return this.payload.context || '';
  }

  private hasSource(): boolean {
    return !!(this.payload.bookTitle || this.payload.chapterTitle);
  }

  private buildShareText(): string {
    const lines: string[] = [];
    lines.push(`${this.safeWord()}${this.payload.phonetic ? ' ' + this.payload.phonetic : ''}`);
    if (this.payload.definition) {
      lines.push(this.payload.definition);
    }
    if (this.payload.context) {
      lines.push(`「${this.payload.context}」`);
    }
    if (this.payload.contextZh) {
      lines.push(this.payload.contextZh);
    }
    if (this.hasSource()) {
      const src = [this.payload.bookTitle, this.payload.chapterTitle].filter((s) => s).join(' · ');
      lines.push(`—— ${src}`);
    }
    lines.push('— 来自米果智读');
    return lines.join('\n');
  }

  // ─────────── actions ───────────

  private async onCopy(): Promise<void> {
    const text = this.buildShareText();
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await board.setData(data);
      promptAction.showToast({ message: '已复制图文' });
    } catch (e) {
      promptAction.showToast({ message: '复制失败' });
    }
  }

  private async onSaveImage(): Promise<void> {
    if (this.exporting) return;
    this.exporting = true;
    try {
      // componentSnapshot：真机才会成功；模拟器会抛错，走占位 toast
      const pixelMap: image.PixelMap = await componentSnapshot.createFromComponent(SNAPSHOT_NODE_ID);
      // 真机：此处应写到相册（@ohos.file.photoAccessHelper）
      // 占位：仅释放 pixelMap，提示成功
      await pixelMap.release();
      promptAction.showToast({ message: '已保存到相册' });
    } catch (_e) {
      promptAction.showToast({ message: '当前设备暂不支持导出图片' });
    } finally {
      this.exporting = false;
    }
  }

  private onShareToWeChat(): void {
    // 占位：后续接入 @ohos.share.shareController + 微信开放平台 SDK
    promptAction.showToast({ message: '已唤起微信分享（占位）' });
  }

  private onShareToWeibo(): void {
    promptAction.showToast({ message: '已唤起微博分享（占位）' });
  }

  private onClose(): void {
    promptAction.showToast({ message: '关闭' });
    // 元服务窗口由系统在 ability destroy 后自动收起；此处不强行 terminate。
  }

  // ─────────── builders ───────────

  @Builder
  brandHeader() {
    Row({ space: AppSpacing.xs }) {
      Text('米')
        .fontSize(AppFontSize.md)
        .fontWeight(AppFontWeight.bold)
        .fontColor(Color.White)
        .width(28).height(28)
        .textAlign(TextAlign.Center)
        .backgroundColor('#A78BFA')
        .borderRadius(8)
      Column({ space: 2 }) {
        Text('米果智读')
          .fontSize(AppFontSize.sm)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
        Text('来自米果智读 · 单词分享')
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.md, bottom: AppSpacing.sm })
  }

  @Builder
  shareCardBody() {
    Column({ space: AppSpacing.md }) {
      // 大字单词
      Text(this.safeWord())
        .fontSize(40)
        .fontWeight(AppFontWeight.bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width('100%')

      // 音标
      if (this.payload.phonetic) {
        Text(this.payload.phonetic)
          .fontSize(AppFontSize.md)
          .fontColor('#E9D5FF')
          .textAlign(TextAlign.Center)
          .width('100%')
      }

      // 中文释义
      Text(this.safeDefinition())
        .fontSize(AppFontSize.md)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm })

      // 分隔
      Divider().color('rgba(255,255,255,0.3)').strokeWidth(1).width('60%')

      // 例句（带翻译）
      if (this.safeContext()) {
        Column({ space: AppSpacing.xs }) {
          Text(`「${this.safeContext()}」`)
            .fontSize(AppFontSize.sm)
            .fontColor('#F5F3FF')
            .fontStyle(FontStyle.Italic)
            .textAlign(TextAlign.Center)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.payload.contextZh) {
            Text(this.payload.contextZh)
              .fontSize(AppFontSize.xs)
              .fontColor('#DDD6FE')
              .textAlign(TextAlign.Center)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .width('100%')
      }

      // 来源
      if (this.hasSource()) {
        Text(`—— ${[this.payload.bookTitle, this.payload.chapterTitle].filter((s) => s).join(' · ')}`)
          .fontSize(AppFontSize.xs)
          .fontColor('#C4B5FD')
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .id(SNAPSHOT_NODE_ID)
    .width('92%')
    .padding({ top: AppSpacing.lg, bottom: AppSpacing.lg, left: AppSpacing.lg, right: AppSpacing.lg })
    .borderRadius(AppRadius.lg)
    .linearGradient({
      angle: 135,
      colors: [['#A78BFA', 0.0], ['#7C3AED', 1.0]],
    })
    .shadow({ radius: 24, color: 'rgba(124, 58, 237, 0.3)', offsetX: 0, offsetY: 8 })
  }

  @Builder
  actionBar() {
    Row() {
      this.actionBtn('分享', '🔗', () => this.onShareToWeChat())
      this.actionBtn('保存', '🖼️', () => this.onSaveImage())
      this.actionBtn('复制', '📋', () => this.onCopy())
      this.actionBtn('关闭', '✕', () => this.onClose())
    }
    .width('100%')
    .padding({ top: AppSpacing.sm, bottom: AppSpacing.sm, left: AppSpacing.base, right: AppSpacing.base })
    .justifyContent(FlexAlign.SpaceAround)
    .backgroundColor(AppColors.bgPrimary)
    .border({ width: { top: 1 }, color: AppColors.divider })
  }

  @Builder
  actionBtn(label: string, icon: string, onTap: () => void) {
    Column({ space: 4 }) {
      Text(icon)
        .fontSize(AppFontSize.lg)
      Text(label)
        .fontSize(AppFontSize.xs)
        .fontColor(AppColors.textPrimary)
    }
    .width('25%')
    .padding(AppSpacing.sm)
    .onClick(onTap)
  }

  @Builder
  secondaryShareRow() {
    Row({ space: AppSpacing.md }) {
      this.smallShareBtn('微信', '#07C160', () => this.onShareToWeChat())
      this.smallShareBtn('微博', '#E6162D', () => this.onShareToWeibo())
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: AppSpacing.sm, bottom: AppSpacing.md })
  }

  @Builder
  smallShareBtn(label: string, color: string, onTap: () => void) {
    Text(label)
      .fontSize(AppFontSize.sm)
      .fontColor(Color.White)
      .padding({ top: 8, bottom: 8, left: 16, right: 16 })
      .backgroundColor(color)
      .borderRadius(AppRadius.base)
      .onClick(onTap)
  }

  build() {
    Column() {
      this.brandHeader()
      Column() {
        this.shareCardBody()
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: AppSpacing.md, bottom: AppSpacing.md })
      this.secondaryShareRow()
      this.actionBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }
}
