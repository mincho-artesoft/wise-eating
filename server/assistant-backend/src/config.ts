/**
 * Everything the service reads from the environment, in one place. No secret
 * has a default; the OpenAI key is only ever read from OPENAI_API_KEY.
 */

function num(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw.trim() === '') return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value)) throw new Error(`${name} must be a number`);
  return value;
}

function flag(name: string, fallback: boolean): boolean {
  const raw = process.env[name]?.trim().toLowerCase();
  if (!raw) return fallback;
  return ['1', 'true', 'yes', 'on'].includes(raw);
}

export const config = {
  get isProduction() {
    return process.env.NODE_ENV === 'production';
  },
  get jwtSecret() {
    const secret = process.env.JWT_SECRET;
    if (!secret || secret.length < 32) throw new Error('JWT_SECRET must be set (32+ characters)');
    return secret;
  },
  get openAIKey() {
    return process.env.OPENAI_API_KEY?.trim() || undefined;
  },
  get openAIBaseURL() {
    return process.env.OPENAI_BASE_URL?.trim() || 'https://api.openai.com/v1';
  },
  /** The owner's "GPT Realtime 2.1". */
  get realtimeModel() {
    return process.env.OPENAI_REALTIME_MODEL?.trim() || 'gpt-realtime-2.1';
  },
  get realtimeVoice() {
    return process.env.OPENAI_REALTIME_VOICE?.trim() || 'marin';
  },
  get transcriptionModel() {
    return process.env.OPENAI_TRANSCRIPTION_MODEL?.trim() || 'gpt-4o-mini-transcribe';
  },
  /** The owner's "GPT 6.2 Sol". */
  get reasoningModel() {
    return process.env.OPENAI_REASONING_MODEL?.trim() || 'gpt-6.2-sol';
  },
  get clientSecretSeconds() {
    return Math.min(Math.max(num('OPENAI_CLIENT_SECRET_SECONDS', 120), 10), 7200);
  },
  get openAITimeoutMs() {
    return num('OPENAI_TIMEOUT_MS', 60_000);
  },

  // Credits ------------------------------------------------------------------
  /** Credits charged per US dollar of OpenAI cost (the margin lives here). */
  get creditsPerUSD() {
    return num('CREDITS_PER_USD', 100);
  },
  get onboardingGrantCredits() {
    return num('ONBOARDING_GRANT_CREDITS', 60);
  },
  get onboardingGrantEnabled() {
    return flag('ONBOARDING_GRANT_ENABLED', true);
  },
  /** Minimum balance to start a voice session or a reasoning call. */
  get minCreditsToStart() {
    return num('MIN_CREDITS_TO_START', 2);
  },
  /** Charged per started minute of voice when reported usage is lower. */
  get voiceFloorCreditsPerMinute() {
    return num('VOICE_FLOOR_CREDITS_PER_MINUTE', 3);
  },
  get voiceSessionMaxMinutes() {
    return num('VOICE_SESSION_MAX_MINUTES', 20);
  },

  // Apple --------------------------------------------------------------------
  get appleTeamId() {
    return process.env.APPLE_TEAM_ID?.trim() || '';
  },
  get appleBundleId() {
    return process.env.APPLE_BUNDLE_ID?.trim() || '';
  },
  get appleAppAppleId() {
    const raw = process.env.APPLE_APP_APPLE_ID?.trim();
    return raw ? Number(raw) : undefined;
  },
  /** "Production" or "Sandbox" for StoreKit; "development" uses Apple's DeviceCheck development server. */
  get appleEnvironment() {
    return process.env.APPLE_ENVIRONMENT?.trim() || 'Sandbox';
  },
  get appAttestRequired() {
    return flag('APP_ATTEST_REQUIRED', config.isProduction);
  },
  get appAttestAllowDevelopment() {
    return flag('APP_ATTEST_ALLOW_DEVELOPMENT', !config.isProduction);
  },
  get deviceCheckRequired() {
    return flag('DEVICECHECK_REQUIRED', config.isProduction);
  },
  get deviceCheckKeyId() {
    return process.env.APPLE_DEVICECHECK_KEY_ID?.trim() || '';
  },
  get deviceCheckPrivateKey() {
    return process.env.APPLE_DEVICECHECK_PRIVATE_KEY?.replace(/\\n/g, '\n') || '';
  },
  get deviceCheckBaseURL() {
    return (
      process.env.APPLE_DEVICECHECK_BASE_URL?.trim() ||
      (config.appleEnvironment === 'Production'
        ? 'https://api.devicecheck.apple.com/v1'
        : 'https://api.development.devicecheck.apple.com/v1')
    );
  },
  get allowUnverifiedStoreKit() {
    return flag('ALLOW_UNVERIFIED_STOREKIT_JWS', false) && !config.isProduction;
  },
  get appleRootCertificatePaths() {
    return (process.env.APPLE_ROOT_CERTIFICATE_PATHS ?? 'certs/AppleRootCA-G3.cer,certs/AppleRootCA-G2.cer,certs/AppleComputerRootCertificate.cer')
      .split(',')
      .map((p) => p.trim())
      .filter(Boolean);
  },
  get appAttestRootPath() {
    return process.env.APP_ATTEST_ROOT_PATH?.trim() || 'certs/Apple_App_Attestation_Root_CA.pem';
  },
};

/** USD per 1M tokens (developers.openai.com/api/docs/pricing, read 2026-11-28). */
export interface ModelPrice {
  textIn: number;
  textCachedIn: number;
  audioIn: number;
  audioCachedIn: number;
  imageIn: number;
  textOut: number;
  audioOut: number;
}

export const PRICES: Readonly<Record<string, ModelPrice>> = {
  'gpt-realtime-2.1': { textIn: 4, textCachedIn: 0.4, audioIn: 32, audioCachedIn: 0.4, imageIn: 5, textOut: 24, audioOut: 64 },
  'gpt-realtime-2.1-mini': { textIn: 0.6, textCachedIn: 0.06, audioIn: 10, audioCachedIn: 0.3, imageIn: 0.6, textOut: 2.4, audioOut: 20 },
  'gpt-6.2-sol': { textIn: 2, textCachedIn: 0.1, audioIn: 2, audioCachedIn: 0.1, imageIn: 2, textOut: 10, audioOut: 10 },
  'gpt-4o-mini-transcribe': { textIn: 1.25, textCachedIn: 1.25, audioIn: 3, audioCachedIn: 3, imageIn: 0, textOut: 5, audioOut: 5 },
  'gpt-4o-transcribe': { textIn: 2.5, textCachedIn: 2.5, audioIn: 6, audioCachedIn: 6, imageIn: 0, textOut: 10, audioOut: 10 },
};

export function priceFor(model: string): ModelPrice {
  const price = PRICES[model];
  // An unknown model is priced as the most expensive one, never as free.
  return price ?? PRICES['gpt-realtime-2.1'];
}

/**
 * Credit products, prepared for App Store Connect (not created there).
 * Credits per pack and per subscription period are owner decisions.
 */
export const PRODUCTS: Readonly<Record<string, { kind: 'pack' | 'subscription'; credits: number }>> = {
  // Consumable credit packs (to be created in App Store Connect).
  'ayurveda.asana.yoga.credits.small': { kind: 'pack', credits: Number(process.env.CREDITS_PACK_SMALL ?? 300) },
  'ayurveda.asana.yoga.credits.large': { kind: 'pack', credits: Number(process.env.CREDITS_PACK_LARGE ?? 1500) },
  // The existing Premium plans, which would include credits each period.
  'ayurveda.asana.yoga.premium': { kind: 'subscription', credits: Number(process.env.CREDITS_SUB_MONTHLY ?? 500) },
  'ayurveda.asana.yoga.premium.yearly': { kind: 'subscription', credits: Number(process.env.CREDITS_SUB_YEARLY ?? 6000) },
};

export const MILLI = 1000n;

/** Thousandths of a credit for a cost in micro-USD, rounded up. */
export function chargeMilliForCost(costMicrosUSD: bigint): bigint {
  const perUSD = BigInt(Math.round(config.creditsPerUSD * 1000)); // milli-credits per USD
  return (costMicrosUSD * perUSD + 999_999n) / 1_000_000n;
}
