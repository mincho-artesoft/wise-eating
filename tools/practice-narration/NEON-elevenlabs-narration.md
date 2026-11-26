# For Neon: the practice narration in other languages, with ElevenLabs

The 60 guided practices are narrated in English (601 cues, six voices, made
with Maya1). This is the same narration in the other languages, generated with
Mincho's ElevenLabs subscription from the translated cues.

## What you are given

- [`SCRIPT.en.md`](SCRIPT.en.md) — the whole English script to read through:
  the six voices and how each one reads, then every practice with its voice,
  its cues, the silence after each cue and how long the English recording of
  the cue runs.
- `narration.en.json` — the same as data: `voices`, and `practices[]` with
  `slug`, `voice`, an optional `note` (direction that overrides the voice's
  general delivery) and `cues[]` (`n`, `text`, `hold`, `englishSeconds`).
- The translated cues come from `tools/practice-content/<language>.json`
  (`{ "English cue": "translation" }`), so that package is finished and
  reviewed for a language before its audio is generated. Look a cue up by its
  English `text`.
- The English recordings, for reference by ear only:
  `Resources/PracticeNarration/audio/<slug>/cue-NN.mp3`.

English is about 42,000 characters for the whole library; a translation is
that, give or take a fifth. ElevenLabs bills by the character, and every retake
is billed again.

## The voices

Six voices, one per entry in `voices`. A practice is always read by the voice
it is cast to, in every language.

- Make or choose each voice **once** and reuse its voice id for every cue and
  every language. Write the six ids in `voices.elevenlabs.json` (voice name →
  voice id, plus the model and settings used) and commit that file. A voice
  that changes between cues or between practices is the failure the English
  production spent most of its time on.
- Build each voice from its written description (`who`, `timbre`, `tone`,
  `power`), with ElevenLabs' voice design or by choosing a library voice that
  fits. **Do not clone the voices from the English Maya1 recordings.** A local
  trial that cloned the English voice for Bulgarian (Fish Audio S2 Pro,
  2026-11-26) came out sounding like a foreigner reading Bulgarian; Mincho
  rejected it on first listen. The voice must sound native in the language it
  speaks.
- If one voice id does not sound native in some language, that language gets
  its own voice id for that role, recorded in `voices.elevenlabs.json`. Same
  role and delivery, different speaker.
- The accent wanted in English was Californian; in every other language it is
  simply the standard, unmarked accent of that language.

## How it is read

The direction in `voices` is the brief, and it applies in every language:

- About 95 words a minute — far slower than the service's default. Use the
  speed setting and the punctuation of the text, not time-stretching beyond
  15 %.
- Flat, settled, unperformed. No brightness, no encouragement, no rising
  lines, no audiobook acting. `avoid` says what each voice must never do.
- No expressive tags or sound effects other than a breath or a sigh where the
  English voice is allowed one. Nothing laughed, gasped or whispered for
  effect.
- `note` on a practice comes first: `descent-into-sleep` never rises;
  pranayama and kriya cautions and counts are read plainly, not soothingly.
- Mantra sounds and counted numbers are spoken as the translation writes
  them.

## One cue, one file

- Generate each cue as its own file. Never join cues into one generation and
  cut them apart, and never let the service merge or drop a sentence.
- Give the service the neighbouring cues as context where it accepts them
  (previous and next text), so that a cue is read as part of its practice
  and not as a headline.
- Fix the seed and the settings per voice and record them; a retake changes
  only the seed.
- Nothing is spoken for the `hold`: the app inserts that silence.

## Delivery

Per language, outside the app bundle and outside git:

```
tools/practice-narration/out/<language>/audio/<slug>/cue-NN.mp3
tools/practice-narration/out/<language>/manifest.json
```

- MP3, mono, 24 kHz, 96 kbps, each cue normalised to −16 LUFS integrated with
  a true peak of −1.5 dB, leading and trailing silence trimmed to a natural
  edge — the same as the English delivery.
- `manifest.json` in the shape of `Resources/PracticeNarration/manifest.json`,
  with the measured `durationSec` of every cue and the unchanged `holdSec`.
- `out/` is ignored by git. Commit `voices.elevenlabs.json`, the generation
  script and a short report per language; not the audio. Do not put anything
  under `Resources/PracticeNarration` or change the app: how the languages
  reach the app (bundled or downloaded) is not decided.

## Checks before a language is done

1. Every practice has every cue: 60 folders, 601 files.
2. Each cue transcribed back with a speech recogniser in that language and
   compared with the text it was generated from. A cue with a missing,
   repeated or changed sentence is regenerated.
3. Each cue's length against `englishSeconds`: outside 0.6×–1.8× is listened
   to or regenerated. The whole practice should land near the English length.
4. Loudness and peak measured after mastering, not assumed.
5. A report: characters billed, cues regenerated and why, anything that
   still sounds wrong.

## Order — a pilot before the library

1. Check the subscription: characters left this month, which model speaks
   which of the 48 languages, and the commercial-use terms of the plan. Tell
   Mincho the numbers before spending anything. A language the model does not
   officially support is skipped, not forced.
2. **Pilot in Bulgarian**, because Mincho can judge it by ear: the six voices,
   one short practice each — `rain-on-the-roof` (Solene) is the one he has
   already heard in English and in the failed trial. Stop and wait for him to
   listen.
3. After he accepts the voices: the rest of the Bulgarian library, then one
   language at a time in the order he gives, each with the checks above.
4. Stop and report when the month's characters are close to running out
   rather than leaving a language half done.

## Rules

- The API key is read from the environment variable `ELEVENLABS_API_KEY`.
  Never write it into a file, a commit, a log or a message.
- No audio is generated from a translation that has not been through
  `tools/practice-content` and its second reader.
- Do not regenerate or replace the English narration.
- Check the service's current documentation for model names, settings and
  limits; do not rely on memory for them.
