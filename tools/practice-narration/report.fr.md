# Practice Narration Report — French (`fr`)

- **Date:** 2026-11-26 (tempo processing applied 2026-11-27)
- **Model:** `eleven_v4` (`language_code: "fr"`, `stability: 0.85`, `similarity_boost: 0.78`, `seed: 7302`, no expressive tags)
- **Voice:** `Caroline - Warm, Sweet and Soft` (`kwhMCf63M8O3rCfnQ3oQ`) — native French (`standard`), `high_quality`, shared library (`notice_period: 730 days`, `rate: 1.0`, 147M chars/yr)
- **Translation source:** `tools/practice-content/fr.json` (1,023 strings, 179 second-reader corrections, 0 rejected, 0 number diffs, 6/6 quoted cross-references)
- **Delivery location (git-ignored):**
  - `tools/practice-narration/out/fr/audio/<slug>/cue-NN.mp3`
  - `tools/practice-narration/out/fr/manifest.json`
  - Unprocessed originals preserved in `tools/practice-narration/out/fr/_original/`

## Post-Generation Tempo Processing (Variant B — 0 credits)

Because Caroline's unstretched `eleven_v4` delivery averaged `0.62×` of English (`52.82 min` vs `84.94 min`, and ~151 wpm on sleep practices), Mincho tested Variants A and B on `descent-into-sleep` and `the-night-sky` and selected **Variant B** (`tools/practice-narration/apply_tempo_b.py`) across all 601 French cues from lossless-decoded `_raw/` audio:

1. **8% pitch- and formant-preserving slowdown:** `ffmpeg rubberband=tempo=0.925926:pitch=1.0:formant=preserved:transients=crisp:window=standard` (well within the 15% maximum in the brief).
2. **Internal pause extension (punctuation-aligned, 25 ms raised-cosine fades at minimum-RMS midpoint):**
   - Phrase / comma / em-dash breaks: extended to `2.0×` original pause (capped at `0.80 s`).
   - Sentence breaks (`. ? !`): extended up to `1.20 s` total.
3. **Final mastering:** two-pass `-16 LUFS` loudnorm + `aresample=24000` + `alimiter` ceiling (`<= -1.5 dBTP`), mono 24 kHz 96 kbps MP3.

## Final Verification Summary (after Variant B)

| Check | Result |
|---|---|
| Practice folders / MP3 files | **60 / 60 folders, 601 / 601 files** (all 601 originals preserved in `out/fr/_original/`) |
| Audio format | MP3, mono, 24 kHz, 96 kbps (`wise-eating-production-narration/v2`) |
| `manifest.json` `holdSec` match | **601 / 601 exact match** with English; `durationSec` freshly measured for all 601 cues |
| Total spoken duration | **65.07 min** vs English **84.94 min** (**0.77× EN**, up from `52.82 min` / `0.62× EN`; `484 / 601` cues = **80.5%** inside `0.6×–1.8×`, `0` above `1.8×`) |
| ASR back-transcription (`mlx-community/whisper-large-v3-turbo`, `fr`) | **601 / 601 passed** (mean similarity **0.9911**, up slightly from `0.9906` before processing; 0 clipped syllables or lost words; the only 4 cues `<0.85` are identical word-vs-digit normalizations: `Un, deux, trois, quatre` → `1, 2, 3, 4`, `dix` → `10`, `vingt-sept` → `27`) |
| Integrated loudness (`ebur128` post-mastering) | Median **-16.6 LUFS** (standard cues `-15.1 .. -17.5 LUFS`; ultra-short <3s cues down to `-24.4 LUFS` due to EBU R128 gating) |
| True Peak (`ebur128` post-mastering) | **601 / 601 ≤ -1.5 dBTP** (`-3.3 .. -1.5 dB`; 2 cues initially at `-1.1 dB` re-limited locally to `-2.5` / `-2.4 dB` at 0 credits) |

## Billing

- **Total French cue text:** 47,622 characters (601 cues)
- **Total ElevenLabs credits billed:** **~18,908 credits** (~0.40 credits/char on `eleven_v4`)
  - Pilot (`rain-on-the-roof`, 8 cues, reused via `--resume`): `204` credits (Account 1, paid Starter)
  - Batch 1 (166 cues, `so-hum-breath` through `wind-through-grass/cue-06`): `5,482` credits (Account 1, paid Starter)
  - Batch 2 (427 remaining cues, `wind-through-grass/cue-07` through `descent-into-sleep`): `13,222` credits (Account 2, paid Starter)
  - Variant B local tempo/pause processing & verification: **`0` credits**
- **Retakes needed:** **0**
