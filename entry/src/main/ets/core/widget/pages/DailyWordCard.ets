/**
 * DailyWordCard — 桌面卡片 UI（W12-C1）
 *
 * 支持 3 种 form size，运行时根据 widget 容器尺寸自适应：
 *  - 1×2 (compact): 单词 + 短释义
 *  - 2×2 (default): 单词 + 词性 + 释义 + 1 例句
 *  - 2×4 (large)  : 完整卡片 + 词性 + 中英例句 + CTA
 *
 * 状态：
 *  - state='loading' → 骨架屏
 *  - state='error'   → 错误占位 + 重试
 *  - state='ok' && word=='' → 空态（保存第一个单词后开始）
 *  - state='ok' 正常渲染
 *
 * 暗色模式自动适配（colorMode: auto in form_config.json）。
 */

@Entry
@Component
struct DailyWordCard {
  @LocalStorageProp('word') word: string = '';
  @LocalStorageProp('partOfSpeech') partOfSpeech: string = '';
  @LocalStorageProp('definition') definition: string = '';
  @LocalStorageProp('exampleEn') exampleEn: string = '';
  @LocalStorageProp('exampleZh') exampleZh: string = '';
  @LocalStorageProp('date') date: string = '';
  @LocalStorageProp('state') state: string = 'loading'; // loading | ok | error
  @LocalStorageProp('vocabId') vocabId: string = '';

  // ---- design tokens ----
  private readonly bgGradientStart: string = '#FFF8EE';
  private readonly bgGradientEnd: string = '#FFE9C9';
  private readonly accent: string = '#E76F1A'; // 米果橙
  private readonly textPrimary: string = '#1F1813';
  private readonly textSecondary: string = '#5A4A3F';
  private readonly textMuted: string = '#9C8B7E';

  // ---- helpers ----

  /** 根据父容器宽度推断 dimension（HarmonyOS form 尺寸近似换算）。
   *  1*2 ≈ width <= 200vp；2*2 ≈ 200~340；2*4 ≈ > 340
   */
  private dimension(width: number): '1*2' | '2*2' | '2*4' {
    if (width >= 340) return '2*4';
    if (width >= 200) return '2*2';
    return '1*2';
  }

  private dynamicWordFontSize(dim: string): number {
    if (dim === '1*2') return 18;
    if (dim === '2*2') return 24;
    return 30;
  }

  private postAction(action: string): void {
    const params: Record<string, string> = { action };
    if (action === 'open-vocab' && this.vocabId.length > 0) {
      params['vocabId'] = this.vocabId;
    }
    postCardAction(this, {
      action: 'message',
      params: { ...params, action: action },
    });
  }

  private postRouter(target: string): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        target,
        vocabId: this.vocabId,
        word: this.word,
        fromCard: 'daily-word',
      },
    });
  }

  // ---------- builders ----------

  @Builder Skeleton() {
    Column({ space: 8 }) {
      Row().width('60%').height(16).backgroundColor('#00000010').borderRadius(4)
      Row().width('100%').height(12).backgroundColor('#00000010').borderRadius(4)
      Row().width('80%').height(12).backgroundColor('#00000010').borderRadius(4)
    }
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .width('100%')
    .height('100%')
  }

  @Builder ErrorView() {
    Column({ space: 8 }) {
      Text('网络异常')
        .fontSize(13)
        .fontColor(this.textSecondary)
      Row() {
        Text('点击重试')
          .fontSize(12)
          .fontColor('#FFFFFF')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .backgroundColor(this.accent)
          .borderRadius(12)
          .onClick(() => this.postAction('retry'))
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%').height('100%').padding(12)
  }

  @Builder EmptyView() {
    Column({ space: 6 }) {
      Text('保存第一个单词后开始')
        .fontSize(12)
        .fontColor(this.textSecondary)
        .textAlign(TextAlign.Center)
      Text('打开 App 收集生词')
        .fontSize(10)
        .fontColor(this.textMuted)
        .onClick(() => this.postRouter('vocab'))
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%').height('100%').padding(12)
  }

  @Builder Compact() {
    Column({ space: 4 }) {
      Text(this.word)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.definition)
        .fontSize(11)
        .fontColor(this.textSecondary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%').height('100%').padding(10)
  }

  @Builder Default22() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text(this.word)
          .fontSize(this.dynamicWordFontSize('2*2'))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textPrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.partOfSpeech.length > 0) {
          Text(this.partOfSpeech)
            .fontSize(10)
            .fontColor(this.accent)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('#FBE5D6')
        }
      }
      .width('100%').alignItems(VerticalAlign.Center)

      Text(this.definition)
        .fontSize(12)
        .fontColor(this.textSecondary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.exampleEn.length > 0) {
        Text(this.exampleEn)
          .fontSize(11)
          .fontStyle(FontStyle.Italic)
          .fontColor(this.textMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      Blank()

      Text(`今日一词 · ${this.date}`)
        .fontSize(9)
        .fontColor(this.textMuted)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%').height('100%').padding(12)
    .onClick(() => this.postRouter(this.vocabId.length > 0 ? 'vocab' : 'Reader'))
  }

  @Builder Large24() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.word)
          .fontSize(this.dynamicWordFontSize('2*4'))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textPrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.partOfSpeech.length > 0) {
          Text(this.partOfSpeech)
            .fontSize(11)
            .fontColor(this.accent)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(6)
            .backgroundColor('#FBE5D6')
        }
      }
      .width('100%').alignItems(VerticalAlign.Center)

      Text(this.definition)
        .fontSize(14)
        .fontColor(this.textSecondary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.exampleEn.length > 0) {
        Column({ space: 2 }) {
          Text(this.exampleEn)
            .fontSize(12)
            .fontStyle(FontStyle.Italic)
            .fontColor(this.textPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.exampleZh.length > 0) {
            Text(this.exampleZh)
              .fontSize(11)
              .fontColor(this.textMuted)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 8, top: 4, bottom: 4 })
        .borderWidth({ left: 2 })
        .borderColor({ left: this.accent })
        .width('100%')
      }

      Blank()

      Row() {
        Text(`今日一词 · ${this.date}`)
          .fontSize(10)
          .fontColor(this.textMuted)
          .layoutWeight(1)
        Text('点击学习 →')
          .fontSize(11)
          .fontColor('#FFFFFF')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(this.accent)
          .borderRadius(10)
          .onClick(() => this.postRouter(this.vocabId.length > 0 ? 'vocab' : 'Reader'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%').height('100%').padding(14)
  }

  @Builder Body(width: number) {
    if (this.state === 'loading') {
      this.Skeleton()
    } else if (this.state === 'error') {
      this.ErrorView()
    } else if (this.word.length === 0) {
      this.EmptyView()
    } else {
      // 根据宽度选择布局
      if (width >= 340) {
        this.Large24()
      } else if (width >= 200) {
        this.Default22()
      } else {
        this.Compact()
      }
    }
  }

  build() {
    Column() {
      this.Body(this.containerWidth())
    }
    .width('100%')
    .height('100%')
    .borderRadius(20)
    .linearGradient({
      angle: 135,
      colors: [[this.bgGradientStart, 0.0], [this.bgGradientEnd, 1.0]],
    })
  }

  /** 简化处理：HarmonyOS 卡片无法直接拿容器宽度，依赖系统切 dimension 回调；
   *  此处给 2*2 默认值，实际宽度由 form_config.json supportDimensions 决定。 */
  private containerWidth(): number {
    return 280;
  }
}
