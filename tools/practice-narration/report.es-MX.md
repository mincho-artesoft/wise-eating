# Practice Narration Report — Spanish, Mexico / LatAm (`es-MX`)

- **Date:** 2026-11-26
- **Model:** `eleven_v4` (`language_code: "es"`, `stability: 0.85`, `similarity_boost: 0.78`, `seed: 7101`, no time-stretching, no expressive tags)
- **Voice:** `Lili - Soothing, Too-polished` (`ZIxEPysv7w52OU1uxmur`) — native Latin American Spanish, `professional`, shared library (`notice_period: 730 days`, `rate: 1.0`, 1.62M chars/yr)
- **Translation source:** `tools/practice-content/es-MX.json` (1,023 strings, 172 second-reader corrections, 0 rejected, 0 number diffs, 6/6 quoted cross-references)
- **Delivery location (git-ignored):**
  - `tools/practice-narration/out/es-MX/audio/<slug>/cue-NN.mp3`
  - `tools/practice-narration/out/es-MX/manifest.json`

## Verification Summary

| Check | Result |
|---|---|
| Practice folders / MP3 files | **60 / 60 folders, 601 / 601 files** |
| Audio format | MP3, mono, 24 kHz, 96 kbps (`wise-eating-production-narration/v2`) |
| `manifest.json` `holdSec` match | **601 / 601 exact match** with English |
| ASR back-transcription (`mlx-community/whisper-large-v3-turbo`, `es`) | **601 / 601 passed** (mean similarity **0.9927**; all 7 cues scoring `<0.85` were number-word vs digit transcriptions (`Uno, dos, tres, cuatro` → `1, 2, 3, 4`, `Diez` → `10`, `Ciento ocho` → `108`) plus one homophone (`de esas` → `dehesas`, verified clean by ear) — 0 missed, repeated, or altered words) |
| Integrated loudness (`ebur128` post-mastering) | **-17.1 .. -15.5 LUFS** (median **-16.4 LUFS**) |
| True Peak (`ebur128` post-mastering) | **601 / 601 ≤ -1.5 dBTP** (`-5.5 .. -2.2 dB`, **0** cues over `-1.5 dB` on first pass) |
| Total spoken duration | **68.8 min** vs English **84.9 min** (**0.81×**, 519/601 cues inside `0.6×–1.8×` with no time-stretching) |

## Billing

- **Total `es-MX` cue text:** 45,514 characters (601 cues)
- **Total ElevenLabs credits billed:** **~23,853 credits**
  - Pilot (`rain-on-the-roof`, 8 cues, reused via `--resume`): `200` credits (Account 1, paid Starter)
  - Remaining 593 cues: `23,653` credits (Account 2, paid Starter — `3,125 / 40,000` credits remaining)
- **Retakes needed:** **0** (all 601 cues passed ASR, loudness, and true peak cleanly on first generation)
