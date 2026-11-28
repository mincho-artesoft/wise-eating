import { priceFor } from '../config';

/** OpenAI usage as Realtime `response.done` and the Responses API report it. */
export interface OpenAIUsage {
  input_tokens?: number;
  output_tokens?: number;
  total_tokens?: number;
  input_token_details?: {
    text_tokens?: number;
    audio_tokens?: number;
    image_tokens?: number;
    cached_tokens?: number;
    cached_tokens_details?: { text_tokens?: number; audio_tokens?: number; image_tokens?: number };
  };
  output_token_details?: { text_tokens?: number; audio_tokens?: number };
  /** Responses API naming. */
  input_tokens_details?: { cached_tokens?: number };
  output_tokens_details?: { reasoning_tokens?: number };
}

export interface TokenBreakdown {
  textIn: number;
  audioIn: number;
  imageIn: number;
  cachedText: number;
  cachedAudio: number;
  textOut: number;
  audioOut: number;
}

const n = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v > 0 ? Math.min(Math.trunc(v), 50_000_000) : 0);

export function breakdown(usage: OpenAIUsage): TokenBreakdown {
  const inD = usage.input_token_details ?? {};
  const outD = usage.output_token_details ?? {};
  const cachedD = inD.cached_tokens_details ?? {};
  const detailedIn = n(inD.text_tokens) + n(inD.audio_tokens) + n(inD.image_tokens);
  const textIn = detailedIn > 0 ? n(inD.text_tokens) : n(usage.input_tokens);
  const cachedText =
    n(cachedD.text_tokens) || (detailedIn > 0 ? 0 : n(usage.input_tokens_details?.cached_tokens) || n(inD.cached_tokens));
  const detailedOut = n(outD.text_tokens) + n(outD.audio_tokens);
  return {
    textIn,
    audioIn: n(inD.audio_tokens),
    imageIn: n(inD.image_tokens),
    cachedText: Math.min(cachedText, textIn),
    cachedAudio: Math.min(n(cachedD.audio_tokens), n(inD.audio_tokens)),
    textOut: detailedOut > 0 ? n(outD.text_tokens) : n(usage.output_tokens),
    audioOut: n(outD.audio_tokens),
  };
}

/** Cost in micro-USD, rounded up. */
export function costMicros(model: string, usage: OpenAIUsage): bigint {
  const p = priceFor(model);
  const t = breakdown(usage);
  const usd =
    ((t.textIn - t.cachedText) * p.textIn +
      t.cachedText * p.textCachedIn +
      (t.audioIn - t.cachedAudio) * p.audioIn +
      t.cachedAudio * p.audioCachedIn +
      t.imageIn * p.imageIn +
      t.textOut * p.textOut +
      t.audioOut * p.audioOut) /
    1_000_000;
  return BigInt(Math.ceil(usd * 1_000_000));
}
