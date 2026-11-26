# Practice Narration Report — French (`fr`)

- **Date:** 2026-11-26
- **Model:** `eleven_v4` (`language_code: "fr"`, `stability: 0.85`, `similarity_boost: 0.78`, `seed: 7302`, no time-stretching, no expressive tags)
- **Voice:** `Caroline - Warm, Sweet and Soft` (`kwhMCf63M8O3rCfnQ3oQ`) — native French (`standard`), `high_quality`, shared library (`notice_period: 730 days`, `rate: 1.0`, 147M chars/yr)
- **Translation source:** `tools/practice-content/fr.json` (1,023 strings, 179 second-reader corrections, 0 rejected, 0 number diffs, 6/6 quoted cross-references)
- **Delivery location (git-ignored):**
  - `tools/practice-narration/out/fr/audio/<slug>/cue-NN.mp3`
  - `tools/practice-narration/out/fr/manifest.json`

## Verification Summary

| Check | Result |
|---|---|
| Practice folders / MP3 files | **60 / 60 folders, 601 / 601 files** |
| Audio format | MP3, mono, 24 kHz, 96 kbps (`wise-eating-production-narration/v2`) |
| `manifest.json` `holdSec` match | **601 / 601 exact match** with English |
| ASR back-transcription (`mlx-community/whisper-large-v3-turbo`, `fr`) | **601 / 601 passed** (mean similarity **0.9906**; only 4 cues scored `<0.85` purely because Whisper transcribed spelled-out French numbers `Un, deux, trois, quatre` / `dix` / `vingt-sept` as digits `1, 2, 3, 4` / `10` / `27` — 0 missed, repeated, or altered words) |
| Integrated loudness (`ebur128` post-mastering) | Median **-16.6 LUFS** (standard cues `-15.7 .. -17.3 LUFS`; ultra-short <3s cues down to `-22.1 LUFS` due to EBU R128 gating) |
| True Peak (`ebur128` post-mastering) | **601 / 601 ≤ -1.5 dBTP** (7 cues initially peaked between `-1.4` and `-0.1 dB` from MP3 encode overshoot and were locally re-mastered with `alimiter` pre-MP3 at 0 extra ElevenLabs credits) |
| Total spoken duration | **52.8 min** vs English **84.9 min** (`0.62×`, consistent with Mincho-approved `eleven_v4` unstretched tempo) |

## Billing

- **Total French cue text:** 47,622 characters (601 cues)
- **Total ElevenLabs credits billed:** **~18,908 credits** (~0.40 credits/char on `eleven_v4`)
  - Pilot (`rain-on-the-roof`, 8 cues, reused via `--resume`): `204` credits (Account 1, paid Starter)
  - Batch 1 (166 cues, `so-hum-breath` through `wind-through-grass/cue-06`): `5,482` credits (Account 1, paid Starter)
  - Batch 2 (427 remaining cues, `wind-through-grass/cue-07` through `descent-into-sleep`): `13,222` credits (Account 2, paid Starter — `26,778 / 40,000` credits remaining)
- **Retakes needed:** **0** (all 601 cues passed ASR cleanly on first generation)
