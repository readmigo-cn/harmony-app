/**
 * 米果 AI 助手卡片（W12-C3）。
 * 支持 2×2 / 2×4 两个尺寸，颜色支持 colorMode=auto（深色模式自适配）。
 *
 * 数据由 AiTipExtensionAbility 通过 formBindingData 注入。
 * 长文截断逻辑：2×2 maxLines=3, 2×4 maxLines=6。Form 运行时不支持复杂 expand 控件，
 * 「展开」按钮等价于 deeplink 跳到主 App 的 ContentQA 页（携带原贴士作为 prompt）。
 */

@Entry
@Component
struct AiTipCard {
  @LocalStorageProp('tip') tip: string = '正在加载今日学习贴士…';
  @LocalStorageProp('day') day: number = 0;

  /** 尺寸标识：'2*2' / '2*4' */
  @LocalStorageProp('formDimension') formDimension: string = '2*2';

  private readonly weekLabels: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

  private dayLabel(): string {
    const d = Math.max(0, Math.min(6, this.day));
    return this.weekLabels[d];
  }

  private onAskAi(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        route: 'ContentQA',
        prompt: this.tip,
        from: 'widget_ai_tip',
      },
    });
  }

  private onRefresh(): void {
    // 触发 onFormEvent('refresh')，Ability 端会换条贴士并 updateForm
    postCardAction(this, {
      action: 'message',
      params: { action: 'refresh' },
    });
  }

  private onPrev(): void {
    postCardAction(this, {
      action: 'message',
      params: { action: 'next' },
    });
  }

  // ---------- 2×2 ----------
  @Builder
  build2x2() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        // AI 头像（占位用圆形 + 文字）
        Stack() {
          Circle({ width: 24, height: 24 }).fill('#7E57C2')
          Text('AI').fontSize(10).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        }
        Text('米果 AI 助手')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1a1a1a')
          .layoutWeight(1)
        Text(this.dayLabel())
          .fontSize(10)
          .fontColor('#999')
      }
      .width('100%')

      Text(this.tip)
        .fontSize(12)
        .fontColor('#333')
        .lineHeight(18)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Blank()

      Row({ space: 8 }) {
        Text('换一条')
          .fontSize(10).fontColor('#7E57C2')
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .border({ width: 1, color: '#D1C4E9', radius: 10 })
          .onClick(() => this.onRefresh())
        Blank()
        Text('问 AI →')
          .fontSize(10).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#7E57C2')
          .borderRadius(10)
          .onClick(() => this.onAskAi())
      }
      .width('100%')
    }
    .width('100%').height('100%')
    .padding(12)
    .backgroundColor('#F8F5FF')
    .borderRadius(16)
  }

  // ---------- 2×4 ----------
  @Builder
  build2x4() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Stack() {
          Circle({ width: 32, height: 32 }).fill('#7E57C2')
          Text('AI').fontSize(12).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        }
        Column({ space: 2 }) {
          Text('米果 AI 助手')
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor('#1a1a1a')
          Text('每日学习贴士').fontSize(10).fontColor('#999')
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(this.dayLabel())
          .fontSize(10).fontColor('#999')
      }
      .width('100%')

      Divider().color('#EDE7F6').strokeWidth(1)

      Text(this.tip)
        .fontSize(13)
        .fontColor('#333')
        .lineHeight(20)
        .maxLines(6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Blank()

      Row({ space: 8 }) {
        Text('< 上一条')
          .fontSize(11).fontColor('#7E57C2')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .border({ width: 1, color: '#D1C4E9', radius: 12 })
          .onClick(() => this.onPrev())
        Text('换一条')
          .fontSize(11).fontColor('#7E57C2')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .border({ width: 1, color: '#D1C4E9', radius: 12 })
          .onClick(() => this.onRefresh())
        Blank()
        Text('问 AI →')
          .fontSize(12).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
          .padding({ left: 14, right: 14, top: 5, bottom: 5 })
          .backgroundColor('#7E57C2')
          .borderRadius(12)
          .onClick(() => this.onAskAi())
      }
      .width('100%')
    }
    .width('100%').height('100%')
    .padding(14)
    .backgroundColor('#F8F5FF')
    .borderRadius(16)
  }

  build() {
    Column() {
      if (this.formDimension === '2*4') {
        this.build2x4()
      } else {
        this.build2x2()
      }
    }
    .width('100%').height('100%')
  }
}
