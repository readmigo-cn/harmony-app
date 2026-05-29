// L3 Feature - Reader - Lookup sub-ViewModel
// Owns: lookup state, LookupWordIntent, TranslateSelectionIntent
import { FeatureViewModel } from '../../../core/intent/ViewModel';
import type { AnyIntent, LookupWordIntent } from '../../../core/intent/Intent';
import type { TranslateSelectionIntent } from '../intent/ReaderIntents';
import { TranslateService } from '../../ai-tools/service/TranslateService';
import type { WordExplanation } from '../../ai-tools/service/TranslateService';
import type { LookupState } from './ReaderViewModel';

const LOOKUP_KINDS: ReadonlyArray<string> = [
  'reader.lookupWord',
  'reader.translateSelection',
];

export class ReaderLookupViewModel extends FeatureViewModel<LookupState> {
  readonly kind = 'reader.lookup';

  constructor() {
    super(LOOKUP_KINDS, { status: 'idle' });
  }

  protected async handle(intent: AnyIntent): Promise<void> {
    if (intent.kind === 'reader.lookupWord') {
      await this.handleLookupWord(intent as LookupWordIntent);
    } else if (intent.kind === 'reader.translateSelection') {
      this.handleTranslateSelection(intent as TranslateSelectionIntent);
    }
  }

  private async handleLookupWord(intent: LookupWordIntent): Promise<void> {
    const { word, ctxSentence } = intent.payload;

    this.state = { status: 'loading', data: { status: 'loading', word, contextSentence: ctxSentence ?? '' } };

    try {
      const explanation: WordExplanation = await TranslateService.shared.lookupWord(
        word,
        ctxSentence ?? '',
        'zh',
      );
      this.state = {
        status: 'data',
        data: { status: 'data', word, contextSentence: ctxSentence ?? '', explanation },
      };
    } catch (e) {
      this.state = {
        status: 'error',
        error: {
          code: (e as Error).name ?? 'error',
          message: (e as Error).message,
        },
      };
    }
  }

  private handleTranslateSelection(intent: TranslateSelectionIntent): void {
    const { text, sourceLang, targetLang } = intent.payload;

    this.state = {
      status: 'data',
      data: { status: 'streaming', word: text, streamingText: '', contextSentence: text },
    };

    const stream = TranslateService.shared.translateSentenceStream(text, { sourceLang, targetLang });
    let accumulated = '';

    const advance = async (): Promise<void> => {
      try {
        for await (const chunk of stream) {
          accumulated += chunk;
          if (this.state.status === 'error') return;
          this.state = {
            status: 'data',
            data: { status: 'streaming', word: text, contextSentence: text, streamingText: accumulated },
          };
        }
        this.state = {
          status: 'data',
          data: {
            status: 'data',
            word: text,
            contextSentence: text,
            explanation: {
              word: text,
              definition: accumulated,
              partOfSpeech: '',
              examples: [],
              wordFamily: [],
            },
          },
        };
      } catch (e) {
        this.state = {
          status: 'error',
          error: { code: (e as Error).name ?? 'error', message: (e as Error).message },
        };
      }
    };

    advance().catch(() => {});
  }

  getLookupState(): LookupState {
    if (this.state.status === 'data') return this.state.data;
    if (this.state.status === 'error') {
      return { status: 'error', error: this.state.error };
    }
    if (this.state.status === 'loading') {
      const data = (this.state as { status: 'loading'; data?: LookupState }).data;
      return data ?? { status: 'loading' };
    }
    return { status: 'idle' };
  }
}
