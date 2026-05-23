/**
 * XComponentDemo —— W2-C5 原生组件 demo 页。
 *
 * 演示两件事：
 *   A. typesetting 引擎 → 渲染到 ArkUI Canvas
 *   B. badge-engine 引擎 → 通过 XComponent 直接拿 native surface 渲染 3D 勋章
 *
 * 路由 URL：pages/native/XComponentDemo（需在 main_pages.json 注册一次）
 * 或者由上层 NavPathStack 通过 RoutePath.XCOMPONENT_DEMO 路由进来。
 */

import router from '@ohos.router';
import { AppColors } from '../../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../../core/theme/AppSpacing';
import {
  TypesettingEngine,
  RenderedPage,
} from '../../../../core/native/typesetting';
import {
  BadgeEngine,
  BadgeFace,
  BadgeTouchPhase,
  CeremonyType,
  BadgeEvent,
  BadgeEventKind,
} from '../../../../core/native/badge-engine';

const SAMPLE_HTML = `
<h2>XComponent Demo Chapter</h2>
<p>It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.</p>
<p>However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families.</p>
<p>"My dear Mr. Bennet," said his lady to him one day, "have you heard that Netherfield Park is let at last?"</p>
`.trim();

@Entry
@Component
struct XComponentDemo {
  // -- 通用 / Tab 状态 -----------------------------------------------------
  @State currentTab: number = 0;
  @State statusText: string = '';

  // -- Section A: Typesetting 状态 -----------------------------------------
  @State pageIndex: number = 0;
  @State pageCount: number = 0;
  @State fontSize: number = 17;
  @State theme: 'day' | 'night' | 'sepia' = 'day';
  @State currentPage: RenderedPage | null = null;

  private typeset: TypesettingEngine | null = null;
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private readonly canvasW: number = 340;
  private readonly canvasH: number = 480;

  // -- Section B: Badge 状态 -----------------------------------------------
  private badge: BadgeEngine | null = null;
  private xcController: XComponentController = new XComponentController();
  private rafTimerId: number = -1;
  @State badgeEventLog: string = '(awaiting events)';
  @State snapshotPreview: string = '';

  // ----------------------------------------------------------------------
  // 生命周期
  // ----------------------------------------------------------------------

  aboutToAppear(): void {
    // 初始化 typesetting；badge 等 XComponent.onLoad 再初始化
    this.typeset = new TypesettingEngine({ defaultLocale: 'en', fontScale: 1.0 });
    this.typeset.setLayoutProfile({ pageWidth: this.canvasW, pageHeight: this.canvasH, fontSize: this.fontSize });
    this.typeset.loadDocument(SAMPLE_HTML).then(async (meta) => {
      this.statusText = `loaded ${meta.totalBlocks} blocks`;
      const count = await this.typeset!.layout();
      this.pageCount = count;
      await this.refreshPage(0);
    }).catch((e: Error) => {
      this.statusText = `load failed: ${e.message}`;
    });

    this.badge = new BadgeEngine({ renderMode: 'embedded', width: 320, height: 320 });
    this.badge.setEventCallback((event: BadgeEvent) => this.onBadgeEvent(event));
  }

  aboutToDisappear(): void {
    if (this.rafTimerId >= 0) {
      clearInterval(this.rafTimerId);
      this.rafTimerId = -1;
    }
    this.typeset?.destroy();
    this.typeset = null;
    this.badge?.destroy();
    this.badge = null;
  }

  // ----------------------------------------------------------------------
  // Section A 逻辑
  // ----------------------------------------------------------------------

  private async refreshPage(index: number): Promise<void> {
    if (!this.typeset) return;
    if (index < 0 || index >= this.pageCount) return;
    try {
      const page = await this.typeset.renderPage(index);
      this.pageIndex = index;
      this.currentPage = page;
      this.drawPage();
    } catch (e) {
      this.statusText = `render failed: ${(e as Error).message}`;
    }
  }

  private drawPage(): void {
    const ctx = this.canvasCtx;
    const page = this.currentPage;
    const bg = this.theme === 'night' ? '#1A1A1A' : (this.theme === 'sepia' ? '#FBF7EE' : '#FFFFFF');
    const fg = this.theme === 'night' ? '#EEEEEE' : '#1A1A1A';
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, this.canvasW, this.canvasH);
    if (!page) return;
    ctx.fillStyle = fg;
    for (const line of page.lines) {
      for (const run of line.runs) {
        ctx.font = `${run.fontSize}px HarmonyOS Sans`;
        ctx.fillText(run.text, run.x, run.y);
      }
    }
  }

  private cycleTheme(): void {
    if (this.theme === 'day') this.theme = 'night';
    else if (this.theme === 'night') this.theme = 'sepia';
    else this.theme = 'day';
    this.typeset?.setTheme(this.theme);
    this.drawPage();
  }

  private async adjustFontSize(delta: number): Promise<void> {
    if (!this.typeset) return;
    const next = Math.max(12, Math.min(28, this.fontSize + delta));
    if (next === this.fontSize) return;
    this.fontSize = next;
    this.typeset.setFontSize(next);
    this.typeset.setLayoutProfile({ pageWidth: this.canvasW, pageHeight: this.canvasH, fontSize: next });
    await this.typeset.loadDocument(SAMPLE_HTML);
    this.pageCount = await this.typeset.layout();
    await this.refreshPage(Math.min(this.pageIndex, this.pageCount - 1));
  }

  // ----------------------------------------------------------------------
  // Section B 逻辑
  // ----------------------------------------------------------------------

  private onXComponentLoad(): void {
    if (!this.badge) return;
    try {
      const surfaceId: string = this.xcController.getXComponentSurfaceId();
      this.badge.setSurface(surfaceId, 320, 320);
      // TODO: 实装时从 rawfile/badges/sample.glb 读 ArrayBuffer 后调 loadBadgeModel
      // 这里先用 setOrientation 让占位渲染有动效。
      this.badge.setOrientation(0, 0, 0, 1.0);
      this.startRenderLoop();
      this.badgeEventLog = 'surface bound, render loop started';
    } catch (e) {
      this.badgeEventLog = `surface bind failed: ${(e as Error).message}`;
    }
  }

  private startRenderLoop(): void {
    if (this.rafTimerId >= 0) return;
    // 30 FPS 占位 timer；真正项目里可换为 displaySync 或 vsync hook
    this.rafTimerId = setInterval(() => {
      this.badge?.renderFrame();
    }, 1000 / 30);
  }

  private onBadgeTouch(event: TouchEvent, phase: BadgeTouchPhase): void {
    if (!this.badge || event.touches.length === 0) return;
    const t0 = event.touches[0];
    const t1 = event.touches.length > 1 ? event.touches[1] : null;
    this.badge.onTouch({
      phase,
      x: t0.x,
      y: t0.y,
      pointerCount: event.touches.length,
      x2: t1?.x,
      y2: t1?.y,
    });
  }

  private async takeSnapshot(): Promise<void> {
    if (!this.badge) return;
    try {
      const buf = await this.badge.snapshot(320, 320);
      this.snapshotPreview = `RGBA bytes: ${buf.byteLength}`;
    } catch (e) {
      this.snapshotPreview = `snapshot failed: ${(e as Error).message}`;
    }
  }

  private resetBadge(): void {
    this.badge?.setOrientation(0, 0, 0, 1.0);
  }

  private onBadgeEvent(event: BadgeEvent): void {
    const kindName = XComponentDemo.kindLabel(event.type);
    this.badgeEventLog = `event=${kindName} data=${event.data}${event.dataStr ? ' str=' + event.dataStr : ''}`;
  }

  private static kindLabel(type: BadgeEventKind): string {
    switch (type) {
      case BadgeEventKind.CeremonyPhase: return 'CeremonyPhase';
      case BadgeEventKind.CeremonyDone: return 'CeremonyDone';
      case BadgeEventKind.FlipToBack: return 'FlipToBack';
      case BadgeEventKind.FlipToFront: return 'FlipToFront';
      case BadgeEventKind.Haptic: return 'Haptic';
      case BadgeEventKind.Sound: return 'Sound';
      case BadgeEventKind.Ready: return 'Ready';
      default: return `unknown(${type as number})`;
    }
  }

  // ----------------------------------------------------------------------
  // UI
  // ----------------------------------------------------------------------

  build() {
    Column() {
      // header
      Row({ space: AppSpacing.sm }) {
        Text('< 返回')
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.brand)
          .onClick(() => router.back())
        Blank()
        Text('原生组件 Demo')
          .fontSize(AppFontSize.md)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
        Blank()
      }
      .width('100%')
      .padding(AppSpacing.base)
      .backgroundColor(AppColors.bgPrimary)

      // tab bar
      Row() {
        this.TabPill('A · 排版', 0)
        this.TabPill('B · 勋章', 1)
      }
      .width('100%')
      .padding({ left: AppSpacing.base, right: AppSpacing.base, bottom: AppSpacing.sm })
      .backgroundColor(AppColors.bgPrimary)

      if (this.currentTab === 0) {
        this.SectionA()
      } else {
        this.SectionB()
      }

      // status
      Text(this.statusText)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textSecondary)
        .padding(AppSpacing.sm)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }

  @Builder
  TabPill(label: string, index: number) {
    Text(label)
      .fontSize(AppFontSize.sm)
      .fontColor(this.currentTab === index ? AppColors.bgPrimary : AppColors.textPrimary)
      .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.xs, bottom: AppSpacing.xs })
      .borderRadius(AppRadius.base)
      .backgroundColor(this.currentTab === index ? AppColors.brand : AppColors.bgSecondary)
      .margin({ right: AppSpacing.sm })
      .onClick(() => {
        this.currentTab = index;
      })
  }

  @Builder
  SectionA() {
    Column({ space: AppSpacing.sm }) {
      Canvas(this.canvasCtx)
        .width(this.canvasW)
        .height(this.canvasH)
        .backgroundColor(AppColors.bgReader)
        .borderRadius(AppRadius.md)
        .onReady(() => this.drawPage())

      Row({ space: AppSpacing.sm }) {
        Button('A-')
          .fontSize(AppFontSize.sm)
          .onClick(() => this.adjustFontSize(-1))
        Button('A+')
          .fontSize(AppFontSize.sm)
          .onClick(() => this.adjustFontSize(1))
        Button(`Theme: ${this.theme}`)
          .fontSize(AppFontSize.sm)
          .onClick(() => this.cycleTheme())
      }

      Row({ space: AppSpacing.sm }) {
        Button('Prev')
          .fontSize(AppFontSize.sm)
          .enabled(this.pageIndex > 0)
          .onClick(() => this.refreshPage(this.pageIndex - 1))
        Text(`${this.pageIndex + 1} / ${this.pageCount}`)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.textSecondary)
        Button('Next')
          .fontSize(AppFontSize.sm)
          .enabled(this.pageIndex + 1 < this.pageCount)
          .onClick(() => this.refreshPage(this.pageIndex + 1))
      }
    }
    .padding(AppSpacing.base)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  SectionB() {
    Column({ space: AppSpacing.sm }) {
      // XComponent 提供 native surface，给 badge-engine 渲染
      XComponent({
        id: 'badgeSurface',
        type: XComponentType.SURFACE,
        controller: this.xcController,
      })
        .width(320)
        .height(320)
        .borderRadius(AppRadius.md)
        .backgroundColor(AppColors.bgSecondary)
        .onLoad(() => this.onXComponentLoad())
        .onTouch((e: TouchEvent) => {
          const phase = e.type === TouchType.Down
            ? BadgeTouchPhase.Down
            : (e.type === TouchType.Move
              ? BadgeTouchPhase.Move
              : (e.type === TouchType.Up ? BadgeTouchPhase.Up : BadgeTouchPhase.Cancel));
          this.onBadgeTouch(e, phase);
        })

      Row({ space: AppSpacing.sm }) {
        Button('Play Ceremony')
          .fontSize(AppFontSize.sm)
          .onClick(() => this.badge?.playCeremony(CeremonyType.UnboxOpening))
        Button('Reset')
          .fontSize(AppFontSize.sm)
          .onClick(() => this.resetBadge())
        Button('Snapshot')
          .fontSize(AppFontSize.sm)
          .onClick(() => this.takeSnapshot())
      }

      Text(this.badgeEventLog)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textSecondary)
        .padding(AppSpacing.xs)
        .width('90%')

      if (this.snapshotPreview) {
        Text(this.snapshotPreview)
          .fontSize(AppFontSize.sm)
          .fontColor(AppColors.brand)
          .padding(AppSpacing.xs)
      }
    }
    .padding(AppSpacing.base)
    .alignItems(HorizontalAlign.Center)
  }
}
