/**
 * 我的阅读卡片（W12-C2）。
 * 支持 3 尺寸：1×2 / 2×2 / 2×4。Form 运行时仅可使用基础 ArkUI 组件。
 *
 * 数据由 ReadingProgressExtensionAbility 通过 formBindingData 注入。
 * 点击区域通过 postCardAction 触发 router 事件，由主 App 处理 deeplink → Reader。
 */

@Entry
@Component
struct ReadingProgressCard {
  @LocalStorageProp('bookId') bookId: string = '';
  @LocalStorageProp('bookTitle') bookTitle: string = '';
  @LocalStorageProp('coverUrl') coverUrl: string = '';
  @LocalStorageProp('chapterTitle') chapterTitle: string = '';
  @LocalStorageProp('percentComplete') percentComplete: number = 0;
  @LocalStorageProp('currentChapterIndex') currentChapterIndex: number = 0;
  @LocalStorageProp('totalReadMinutes') totalReadMinutes: number = 0;
  @LocalStorageProp('todayMinutes') todayMinutes: number = 0;
  @LocalStorageProp('streakDays') streakDays: number = 0;
  @LocalStorageProp('recommendBookId') recommendBookId: string = '';
  @LocalStorageProp('recommendBookTitle') recommendBookTitle: string = '';
  @LocalStorageProp('lastReadAt') lastReadAt: string = '';

  /** 由 form runtime 注入的尺寸：'1*2' / '2*2' / '2*4' */
  @LocalStorageProp('formDimension') formDimension: string = '2*2';

  private hasBook(): boolean {
    return this.bookId !== null && this.bookId.length > 0;
  }

  private percentText(): string {
    const p = Math.max(0, Math.min(100, Math.round(this.percentComplete)));
    return `${p}%`;
  }

  private onContinueRead(): void {
    // postCardAction 把点击事件转给主 App，由 EntryAbility 处理 router push
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        route: 'Reader',
        bookId: this.bookId || '',
        from: 'widget_reading_progress',
      },
    });
  }

  private onOpenLibrary(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: { route: 'Library', from: 'widget_reading_progress' },
    });
  }

  private onOpenRecommend(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        route: 'Reader',
        bookId: this.recommendBookId || '',
        from: 'widget_recommend',
      },
    });
  }

  // ---------- 1×2：紧凑横排（书名 + 进度） ----------
  @Builder
  build1x2() {
    Row({ space: 8 }) {
      if (this.coverUrl !== null && this.coverUrl.length > 0) {
        Image(this.coverUrl)
          .width(28)
          .height(40)
          .borderRadius(4)
          .objectFit(ImageFit.Cover)
      }
      Column({ space: 2 }) {
        Text(this.hasBook() ? this.bookTitle : '开始阅读')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1a1a1a')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.hasBook() ? this.percentText() : '从书库挑一本书')
          .fontSize(11)
          .fontColor('#666')
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor('#FFFDF9')
    .borderRadius(12)
    .onClick(() => this.hasBook() ? this.onContinueRead() : this.onOpenLibrary())
  }

  // ---------- 2×2：标准卡片 ----------
  @Builder
  build2x2() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        if (this.coverUrl !== null && this.coverUrl.length > 0) {
          Image(this.coverUrl)
            .width(36)
            .height(52)
            .borderRadius(4)
            .objectFit(ImageFit.Cover)
        }
        Column({ space: 2 }) {
          Text(this.hasBook() ? this.bookTitle : '我的阅读')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a1a1a')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.hasBook() && this.chapterTitle.length > 0) {
            Text(this.chapterTitle)
              .fontSize(11)
              .fontColor('#666')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      if (this.hasBook()) {
        // 进度条
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(6).backgroundColor('#F0EBE0').borderRadius(3)
          Row().width(`${Math.max(2, Math.min(100, this.percentComplete))}%`).height(6)
            .backgroundColor('#2E7D32').borderRadius(3)
        }
        .width('100%')

        Row() {
          Text(this.percentText())
            .fontSize(11)
            .fontColor('#2E7D32')
            .fontWeight(FontWeight.Medium)
          Blank()
          Text(`今日 ${this.todayMinutes ?? 0} 分钟`)
            .fontSize(10)
            .fontColor('#999')
        }
        .width('100%')

        Blank()

        Row() {
          Text('继续阅读')
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('#2E7D32')
            .borderRadius(10)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Blank()
        Text('打开书库挑一本开始阅读')
          .fontSize(12)
          .fontColor('#999')
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#FFFDF9')
    .borderRadius(16)
    .onClick(() => this.hasBook() ? this.onContinueRead() : this.onOpenLibrary())
  }

  // ---------- 2×4：详细卡片（含周数据 + 推荐） ----------
  @Builder
  build2x4() {
    Column({ space: 8 }) {
      // 顶部：书 + 进度
      Row({ space: 10 }) {
        if (this.coverUrl !== null && this.coverUrl.length > 0) {
          Image(this.coverUrl)
            .width(44)
            .height(64)
            .borderRadius(4)
            .objectFit(ImageFit.Cover)
        }
        Column({ space: 4 }) {
          Text(this.hasBook() ? this.bookTitle : '我的阅读')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a1a1a')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.hasBook() && this.chapterTitle.length > 0) {
            Text(this.chapterTitle)
              .fontSize(11)
              .fontColor('#666')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          if (this.hasBook()) {
            Stack({ alignContent: Alignment.Start }) {
              Row().width('100%').height(6).backgroundColor('#F0EBE0').borderRadius(3)
              Row().width(`${Math.max(2, Math.min(100, this.percentComplete))}%`).height(6)
                .backgroundColor('#2E7D32').borderRadius(3)
            }
            .width('100%')
            Text(this.percentText())
              .fontSize(10)
              .fontColor('#2E7D32')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      if (this.hasBook()) {
        // 中部：今日 / 累计 / 连续打卡
        Row({ space: 0 }) {
          Column({ space: 2 }) {
            Text(`${this.todayMinutes ?? 0}`)
              .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#1a1a1a')
            Text('今日 (分)').fontSize(9).fontColor('#999')
          }.layoutWeight(1)
          Column({ space: 2 }) {
            Text(`${this.totalReadMinutes ?? 0}`)
              .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#1a1a1a')
            Text('累计 (分)').fontSize(9).fontColor('#999')
          }.layoutWeight(1)
          Column({ space: 2 }) {
            Text(`${this.streakDays ?? 0}`)
              .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#E65100')
            Text('连续 (天)').fontSize(9).fontColor('#999')
          }.layoutWeight(1)
        }
        .width('100%')

        // 推荐
        if (this.recommendBookTitle.length > 0) {
          Row({ space: 6 }) {
            Text('推荐').fontSize(10).fontColor('#FFFFFF')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#2E7D32').borderRadius(4)
            Text(this.recommendBookTitle)
              .fontSize(11).fontColor('#333')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .onClick(() => this.onOpenRecommend())
        }

        Blank()

        Row() {
          Text('继续阅读')
            .fontSize(12).fontColor('#FFFFFF')
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .backgroundColor('#2E7D32').borderRadius(12)
        }
        .width('100%').justifyContent(FlexAlign.Center)
      } else {
        Blank()
        Text('打开书库挑一本开始阅读')
          .fontSize(12).fontColor('#999')
          .width('100%').textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor('#FFFDF9')
    .borderRadius(16)
    .onClick(() => this.hasBook() ? this.onContinueRead() : this.onOpenLibrary())
  }

  build() {
    Column() {
      if (this.formDimension === '1*2') {
        this.build1x2()
      } else if (this.formDimension === '2*4') {
        this.build2x4()
      } else {
        this.build2x2()
      }
    }
    .width('100%')
    .height('100%')
  }
}
