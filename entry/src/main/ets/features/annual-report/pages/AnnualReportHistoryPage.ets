// L4 Feature - AnnualReport - History list page
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing, AppRadius } from '../../../core/theme/AppSpacing';
import { IntentBus } from '../../../core/intent/IntentBus';
import { AnnualReportViewModel } from '../viewmodel/AnnualReportViewModel';
import {
  makeAnnualReportLoadHistoryIntent,
  makeAnnualReportLoadIntent,
} from '../intent/AnnualReportIntents';
import type { AnnualReportHistoryEntry } from '../../../api/annual-report/AnnualReportApi';

@Entry
@Component
export struct AnnualReportHistoryPage {
  @State vmState: { status: string; data?: { history?: AnnualReportHistoryEntry[] } } = { status: 'idle' };

  private vm: AnnualReportViewModel = new AnnualReportViewModel();

  aboutToAppear(): void {
    IntentBus.getInstance().publish(makeAnnualReportLoadHistoryIntent());
  }

  aboutToDisappear(): void {
    this.vm.onDestroy();
  }

  private get historyEntries(): AnnualReportHistoryEntry[] {
    if (this.vmState.status === 'data' && this.vmState.data?.history) {
      return this.vmState.data.history;
    }
    return [];
  }

  private onSelectYear(year: number): void {
    IntentBus.getInstance().publish(makeAnnualReportLoadIntent(year));
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('年度报告')
            .fontSize(AppFontSize.xl)
            .fontWeight(AppFontWeight.bold)
            .fontColor(AppColors.textPrimary)
        }
        .width('100%')
        .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.lg, bottom: AppSpacing.base })

        if (this.vmState.status === 'loading' || this.vmState.status === 'idle') {
          Column() {
            LoadingProgress().width(40).height(40).color(AppColors.brand)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.vmState.status === 'error') {
          Column({ space: AppSpacing.base }) {
            Text('加载失败').fontSize(AppFontSize.md).fontColor(AppColors.danger)
            Button('重试')
              .onClick(() => IntentBus.getInstance().publish(makeAnnualReportLoadHistoryIntent()))
              .backgroundColor(AppColors.brand)
              .fontColor(AppColors.textInverse)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.historyEntries.length === 0) {
          Column({ space: AppSpacing.base }) {
            Text('暂无年度报告').fontSize(AppFontSize.md).fontColor(AppColors.textTertiary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List({ space: AppSpacing.sm }) {
            ForEach(this.historyEntries, (entry: AnnualReportHistoryEntry) => {
              ListItem() {
                Row() {
                  Column({ space: AppSpacing.xs }) {
                    Text(`${entry.year} 年`)
                      .fontSize(AppFontSize.md)
                      .fontWeight(AppFontWeight.medium)
                      .fontColor(entry.available ? AppColors.textPrimary : AppColors.textTertiary)
                    Text(entry.available ? '点击查看' : '暂未生成')
                      .fontSize(AppFontSize.sm)
                      .fontColor(AppColors.textTertiary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (entry.available) {
                    Text('>')
                      .fontSize(AppFontSize.md)
                      .fontColor(AppColors.textTertiary)
                  }
                }
                .width('100%')
                .padding(AppSpacing.base)
                .backgroundColor(AppColors.bgPrimary)
                .borderRadius(AppRadius.base)
                .onClick(() => {
                  if (entry.available) {
                    this.onSelectYear(entry.year);
                  }
                })
              }
            })
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: AppSpacing.base, right: AppSpacing.base })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bgSecondary)
    }
    .hideTitleBar(true)
  }
}
