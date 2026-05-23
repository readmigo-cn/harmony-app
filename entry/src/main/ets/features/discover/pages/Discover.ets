import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { RouterService } from '../../../core/router/RouterService';
import { RoutePath } from '../../../core/router/RouteConstants';
import { BookSummary, BooksApi } from '../../../api/books/BooksApi';
import { ApiError } from '../../../api/client/HttpClient';
// W14-C3：平板双栏布局
import {
  Breakpoint,
  FoldStatus,
  STORAGE_KEY_BREAKPOINT,
  STORAGE_KEY_FOLD_STATUS,
} from '../../../core/theme/Breakpoints';
import { DiscoverTabletLayout } from '../../multi-platform/pages/tablet/DiscoverTabletLayout';

@Component
export struct Discover {
  @State recommended: BookSummary[] = [];
  @State loading: boolean = false;
  @State errMsg: string = '';
  @StorageProp(STORAGE_KEY_BREAKPOINT) currentBp: Breakpoint = Breakpoint.MD;
  @StorageProp(STORAGE_KEY_FOLD_STATUS) foldStatus: FoldStatus = FoldStatus.UNKNOWN;

  private isTabletLayout(): boolean {
    if (this.currentBp === Breakpoint.LG || this.currentBp === Breakpoint.XL) return true;
    return this.foldStatus === FoldStatus.EXPAND;
  }

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errMsg = '';
    try {
      this.recommended = await BooksApi.list(1, 20);
    } catch (err) {
      const e = err as ApiError;
      this.errMsg = e.message ?? 'common_error_unknown';
    } finally {
      this.loading = false;
    }
  }

  @Builder
  bookCard(b: BookSummary) {
    Column({ space: AppSpacing.xs }) {
      Image(b.coverUrl ?? $r('app.media.app_icon'))
        .width(120)
        .height(170)
        .borderRadius(AppRadius.base)
      Text(b.title)
        .fontSize(AppFontSize.sm)
        .fontColor(AppColors.textPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(120)
      if (b.cefrLevel) {
        Text(b.cefrLevel)
          .fontSize(AppFontSize.xs)
          .fontColor(AppColors.brand)
      }
    }
    .onClick(() => {
      const params: Record<string, string> = { bookId: b.id };
      RouterService.push(RoutePath.READER, params);
    })
  }

  @Builder
  mobileBuilder() {
    Scroll() {
      Column({ space: AppSpacing.lg }) {
        Text($r('app.string.discover_title'))
          .fontSize(AppFontSize.xl)
          .fontWeight(AppFontWeight.bold)
          .fontColor(AppColors.textPrimary)
          .padding(AppSpacing.base)
          .width('100%')
          .textAlign(TextAlign.Start)

        if (this.loading) {
          Column() {
            LoadingProgress().width(40).height(40).color(AppColors.brand)
          }.width('100%').padding(AppSpacing.lg)
        } else if (this.errMsg) {
          Text(this.errMsg)
            .fontSize(AppFontSize.sm)
            .fontColor(AppColors.danger)
            .padding(AppSpacing.base)
        } else {
          Text($r('app.string.discover_recommend'))
            .fontSize(AppFontSize.md)
            .fontWeight(AppFontWeight.medium)
            .fontColor(AppColors.textSecondary)
            .padding({ left: AppSpacing.base })
            .width('100%')
            .textAlign(TextAlign.Start)

          List({ space: AppSpacing.base }) {
            ForEach(this.recommended, (b: BookSummary) => {
              ListItem() {
                this.bookCard(b)
              }
            })
          }
          .listDirection(Axis.Horizontal)
          .height(220)
          .padding({ left: AppSpacing.base, right: AppSpacing.base })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgPrimary)
  }

  build() {
    if (this.isTabletLayout()) {
      DiscoverTabletLayout()
    } else {
      this.mobileBuilder()
    }
  }
}
