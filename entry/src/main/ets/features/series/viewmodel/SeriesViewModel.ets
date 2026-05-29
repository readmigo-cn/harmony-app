// L3 Feature - Series - ViewModel
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { ViewModelState } from '../../../core/intent/ViewModel';
import type { AnyIntent } from '../../../core/intent/Intent';
import { SERIES_INTENT_KINDS } from '../intent/SeriesIntents';
import type { OpenSeriesDetailIntent, LoadSeriesReadingProgressIntent } from '../intent/SeriesIntents';
import { SeriesService } from '../service/SeriesService';
import type { Series } from '../service/SeriesService';

export interface SeriesReadingProgress {
  bookId: string;
  percent: number;
}

export interface SeriesData {
  list?: Series[];
  selected?: Series;
  readingProgress?: SeriesReadingProgress[];
}

export type SeriesState = ViewModelState<SeriesData>;

export class SeriesViewModel extends FeatureViewModel<SeriesData> {
  readonly kind = 'series';

  constructor() {
    super(SERIES_INTENT_KINDS as never);
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    switch (intent.kind) {
      case 'series.loadList':
        await this.handleLoadList();
        break;
      case 'series.openDetail':
        await this.handleOpenDetail(intent as unknown as OpenSeriesDetailIntent);
        break;
      case 'series.loadReadingProgress':
        await this.handleLoadReadingProgress(intent as unknown as LoadSeriesReadingProgressIntent);
        break;
      default:
        break;
    }
  }

  private async handleLoadList(): Promise<void> {
    this.state = { status: 'loading' };
    try {
      const list = await SeriesService.list();
      this.state = { status: 'data', data: { list } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_list_failed', message: (e as Error).message } };
    }
  }

  private async handleOpenDetail(intent: OpenSeriesDetailIntent): Promise<void> {
    const { seriesId } = intent.payload;
    this.state = { status: 'loading' };
    try {
      const selected = await SeriesService.getById(seriesId);
      const current = this.state.status === 'data' ? this.state.data : {};
      this.state = { status: 'data', data: { ...current, selected } };
    } catch (e) {
      this.state = { status: 'error', error: { code: 'load_detail_failed', message: (e as Error).message } };
    }
  }

  private async handleLoadReadingProgress(_intent: LoadSeriesReadingProgressIntent): Promise<void> {
    // Reading progress for series is computed from individual book progress.
    // Stub returns empty until reading-progress API is extended to series scope.
    const current = this.state.status === 'data' ? this.state.data : {};
    this.state = { status: 'data', data: { ...current, readingProgress: [] } };
  }
}
