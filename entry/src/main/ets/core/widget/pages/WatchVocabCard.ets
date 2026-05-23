/**
 * WatchVocabCard — W15-C2 表盘 1×1 圆形卡片
 *
 * 目标尺寸：96×96vp（约 wearable 1×1 form size）
 * 视觉规则：
 *   - 整卡黑底圆角（外层 form runtime 自动 mask 为圆形）
 *   - 中央 word 大字号 22vp（圆形屏可读阈值）
 *   - 下方 definition 短中文释义（≤6 字），10vp，单行省略
 *   - 顶部小角标 dot（米果橙）作为品牌标识
 *
 * 状态：
 *   - state='loading' → 单文字"…"占位
 *   - state='error'   → "重试" 文本（点击触发刷新）
 *   - state='ok'      → 正常单词卡
 *
 * 点击：postCardAction(router) → WatchAbility, target=vocab
 * 暗色模式：表盘默认深色，已经写死 darkScheme，不区分 day/night。
 */

@Entry
@Component
struct WatchVocabCard {
  @LocalStorageProp('word') word: string = '';
  @LocalStorageProp('definition') definition: string = '';
  @LocalStorageProp('vocabId') vocabId: string = '';
  @LocalStorageProp('state') state: string = 'loading';

  // ---- design tokens ----
  private readonly bgColor: string = '#0B0F1A';
  private readonly accent: string = '#E76F1A';
  private readonly textPrimary: string = '#FFFFFF';
  private readonly textSecondary: string = '#9AA3B2';

  private postOpenWatch(): void {
    // 把卡点击转给 WatchAbility（表盘卡 router 跳转的目标 ability）
    postCardAction(this, {
      action: 'router',
      abilityName: 'WatchAbility',
      params: {
        target: 'vocab',
        vocabId: this.vocabId,
        word: this.word,
        fromCard: 'watch-vocab',
      },
    });
  }

  private postRetry(): void {
    postCardAction(this, {
      action: 'message',
      params: { action: 'retry' },
    });
  }

  // ---------- builders ----------

  @Builder LoadingView() {
    Column() {
      Text('…')
        .fontSize(20)
        .fontColor(this.textSecondary)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder ErrorView() {
    Column({ space: 4 }) {
      Text('网络异常')
        .fontSize(10)
        .fontColor(this.textSecondary)
      Text('点击重试')
        .fontSize(10)
        .fontColor(this.accent)
        .onClick(() => this.postRetry())
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder Card() {
    Stack() {
      // 顶部 dot 角标
      Column() {
        Circle({ width: 4, height: 4 }).fill(this.accent)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 6 })

      // 中央 word + definition
      Column({ space: 2 }) {
        Text(this.word)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.definition.length > 0) {
          Text(this.definition)
            .fontSize(10)
            .fontColor(this.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 8, right: 8 })
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%')
    .onClick(() => this.postOpenWatch())
  }

  build() {
    Column() {
      if (this.state === 'loading') {
        this.LoadingView()
      } else if (this.state === 'error' || this.word.length === 0) {
        this.ErrorView()
      } else {
        this.Card()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
    .borderRadius(48) // 圆形 mask 兜底（form runtime 也会自动裁剪）
  }
}
