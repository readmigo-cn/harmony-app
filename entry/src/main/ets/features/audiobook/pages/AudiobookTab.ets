// L4 Feature - Audiobook - Tab page with catalog + search + continue listening
import { AppColors } from '../../../core/theme/AppColors';
import { AppFontSize, AppFontWeight } from '../../../core/theme/AppTypography';
import { AppSpacing } from '../../../core/theme/AppSpacing';
import { IntentBus } from '../../../core/intent/IntentBus';
import { AudiobookViewModel, AudiobookCatalogState } from '../viewmodel/AudiobookViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import {
  makeLoadPopularIntent,
  makeLoadRecentlyListenedIntent,
  makeSearchIntent,
} from '../intent/AudiobookIntents';
import { ContinueListeningCard } from '../components/ContinueListeningCard';
import { AudiobookGrid } from '../components/AudiobookGrid';
import { PaywallBanner } from '../components/PaywallBanner';
import { audioPlayerStore } from '../../../store/AudioPlayerStore';
import type { AudiobookItem } from '../../../api/audiobooks/AudiobookApi';

@Component
export struct AudiobookTab {
  @State private vmState: ViewModelState<AudiobookCatalogState> = { status: 'idle' };
  @State private searchQuery: string = '';
  private vm: AudiobookViewModel = new AudiobookViewModel();
  private unsubState: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsubState = this.vm.subscribeState((s: ViewModelState<AudiobookCatalogState>) => {
      this.vmState = s;
    });
    const bus = IntentBus.getInstance();
    bus.publish(makeLoadPopularIntent()).catch((_e: Error) => {});
    bus.publish(makeLoadRecentlyListenedIntent()).catch((_e: Error) => {});
  }

  aboutToDisappear(): void {
    this.unsubState?.();
    this.vm.onDestroy();
  }

  private get data(): AudiobookCatalogState | null {
    return this.vmState.status === 'data' ? this.vmState.data : null;
  }

  private onSearch(q: string): void {
    if (q.trim().length > 0) {
      IntentBus.getInstance().publish(makeSearchIntent(q.trim())).catch((_e: Error) => {});
    }
  }

  build() {
    Column() {
      // Header
      Text($r('app.string.audiobook_title'))
        .fontSize(AppFontSize.xl)
        .fontWeight(AppFontWeight.bold)
        .fontColor(AppColors.textPrimary)
        .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.base })
        .width('100%')
        .textAlign(TextAlign.Start)

      // Search bar
      Row({ space: AppSpacing.sm }) {
        TextInput({ placeholder: $r('app.string.audiobook_search_placeholder'), text: this.searchQuery })
          .layoutWeight(1)
          .onChange((v: string) => { this.searchQuery = v; })
          .onSubmit(() => { this.onSearch(this.searchQuery); })
          .backgroundColor(AppColors.bgSecondary)
          .borderRadius(8)
          .height(40)
      }
      .padding({ left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.sm, bottom: AppSpacing.sm })
      .width('100%')

      // Paywall banner
      if (this.data?.paywallVisible) {
        PaywallBanner({
          visible: true,
          onDismiss: () => {
            // dismiss handled by subscription page navigation
          },
        })
          .padding({ left: AppSpacing.base, right: AppSpacing.base })
      }

      Scroll() {
        Column({ space: AppSpacing.lg }) {
          // Continue Listening card
          if (audioPlayerStore.audiobook) {
            Column() {
              Text($r('app.string.audiobook_continue_listening'))
                .fontSize(AppFontSize.base)
                .fontWeight(AppFontWeight.semibold)
                .fontColor(AppColors.textPrimary)
                .width('100%')
                .margin({ bottom: AppSpacing.sm })

              ContinueListeningCard({
                audiobook: {
                  id: audioPlayerStore.audiobook.id,
                  title: audioPlayerStore.audiobook.title,
                  narrator: audioPlayerStore.audiobook.narrator ?? '',
                  durationMs: (audioPlayerStore.audiobook.totalDuration ?? 0) * 1000,
                  coverUrl: audioPlayerStore.audiobook.coverUrl ?? '',
                  provider: 'librivox',
                  languages: [audioPlayerStore.audiobook.language ?? ''],
                  free: true,
                } as AudiobookItem,
                progressPercent: audioPlayerStore.getTotalProgress(),
              })
            }
            .padding({ left: AppSpacing.base, right: AppSpacing.base })
          }

          // Search results section
          if (this.data?.searchResults && this.data.searchResults.length > 0) {
            Column() {
              AudiobookGrid({
                items: this.data.searchResults,
                title: $r('app.string.audiobook_search_results') as string,
              })
            }
            .padding({ left: AppSpacing.base, right: AppSpacing.base })
          } else {
            // Recently listened section
            if (this.data?.recentlyListened && this.data.recentlyListened.length > 0) {
              Column() {
                AudiobookGrid({
                  items: this.data.recentlyListened,
                  title: $r('app.string.audiobook_recently_listened') as string,
                })
              }
              .padding({ left: AppSpacing.base, right: AppSpacing.base })
            }

            // Popular section
            if (this.data?.popular && this.data.popular.length > 0) {
              Column() {
                AudiobookGrid({
                  items: this.data.popular,
                  title: $r('app.string.audiobook_popular') as string,
                })
              }
              .padding({ left: AppSpacing.base, right: AppSpacing.base })
            }
          }

          // Loading / error states
          if (this.vmState.status === 'loading') {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(AppColors.accent)
              .margin({ top: AppSpacing.xl, bottom: AppSpacing.xl })
          }

          if (this.vmState.status === 'error') {
            Text(this.vmState.error.message)
              .fontSize(AppFontSize.sm)
              .fontColor(AppColors.textTertiary)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: AppSpacing.xl })
          }

          // Empty state when no data and not loading
          if (this.vmState.status === 'idle' || (this.vmState.status === 'data'
            && !this.data?.popular?.length && !this.data?.recentlyListened?.length)) {
            Text($r('app.string.common_empty'))
              .fontSize(AppFontSize.sm)
              .fontColor(AppColors.textTertiary)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: AppSpacing.xl })
          }
        }
        .width('100%')
        .padding({ bottom: AppSpacing.xl })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(AppColors.bgPrimary)
  }
}
