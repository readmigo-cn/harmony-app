// L0 Model - Voice (shared TTS voice DTO)
// Hoisted from features/audiobook/service/TtsService to satisfy the L2-cannot-import-L3 rule.
// L2 stores/services and L3 viewmodels both consume this. The concrete provider enums stay
// in TtsService where they belong (provider implementation detail).

export type VoiceProvider = 'huawei-system' | 'xunfei' | 'aliyun' | 'mock' | 'tts-v3';

export interface Voice {
  readonly id: string;
  readonly name: string;
  readonly lang: string;
  readonly gender: 'male' | 'female' | 'neutral';
  readonly provider: VoiceProvider;
}
