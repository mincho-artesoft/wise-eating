# Translating yoga descriptions and labels

`work/batch-0.json` … `batch-3.json` hold 1,062 strings (about 22,000 words):
the description of each of the 908 poses and the short labels around poses and
sequences. Each item has `i`, `k` (what it is), `s` (the text to translate)
and, for descriptions, `in` (the pose it describes — context only).

Write `work/<language>/out-N.json`: a JSON array of strings, the same length
and order as `batch-N.json`.

Translate the pose names first (`tools/yoga-names`) and use the same names
here: a description that mentions "Locust Pose" must call it what
`tools/yoga-names/<language>.json` calls it.

## By kind

- `pose_description` — two or three sentences a teacher would say about the
  pose: what it is, what it is for, what to watch. Keep that voice: plain,
  exact, calm, no exclamation marks, no promises of health benefits that the
  English does not make. Keep the sentence count.
- `breath` — how to breathe in the pose ("Even ujjayi", "Belly, ribs,
  chest", "Exhale then inhale"). A label of a few words.
- `gaze` — where the eyes rest ("Fixed point", "Between feet", "Eyes
  closed"). Some are Sanskrit drishti names ("Nasagra"): treat those like
  Sanskrit pose names.
- `pose_caution` — a condition in which the pose is not advised ("high blood
  pressure", "late pregnancy without support", "recent abdominal surgery",
  "menstruation"). Use the ordinary word a patient would recognise, lower
  case where the language allows. Do not soften or strengthen it.
- `sequence_school` — Hatha, Iyengar, Vinyasa, Yin, Restorative. The first
  four are names: respell in the target script, do not translate.
- `sequence_intent` — what a sequence is for ("Back Care", "Energising",
  "Evening"). A label.
- `sequence_season` — the Ayurvedic season and its gloss, "Vasanta (spring)".
  Respell the Sanskrit name, translate the gloss.
- `sequence_stage` — the part of a class a pose belongs to: `open` (opening),
  `warm` (warm-up), `salute` (sun salutations), `standing`, `balance`,
  `core`, `back` (backbends), `hips` (hip openers), `twist`, `fold` (forward
  folds), `invert` (inversions), `rest` (final rest). Translate the meaning in
  brackets here, as a one- or two-word heading.
- `sequence_note_sentence` — one sentence; the app joins two of them into a
  sequence's note, so each must stand alone and end with a full stop.
- `sequence_title_word` — "min" (minutes, abbreviated) and "Level", as in
  "Hatha Energising — 15 min — Level 1 — Vasanta".

## Rules

- Sanskrit terms inside a sentence (ujjayi, drishti, bandha, prana, vata,
  pitta, kapha, agni) stay Sanskrit: Latin-script languages keep them,
  others respell them. Do not explain them in brackets unless the English
  does.
- Keep numbers and digits as Western digits.
- One translation per item, no notes, no alternatives.
- Cautions and the safety parts of descriptions ("do not", "avoid", "stop
  if") must keep exactly the strength of the English.
