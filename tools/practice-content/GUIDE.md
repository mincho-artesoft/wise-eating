# Translating the practices (meditation, breathing, relaxation)

`work/batch-0.json` … `batch-3.json` hold 1,023 strings (about 10,900 words):
everything a person reads in the 60 guided practices. Each item has `i`, `k`
(what it is), `p` (the practice it belongs to; `labels` for the shared
labels), `s` (the text to translate), and for cues `n` (the cue's place in
the practice) and `hold` (the seconds of silence that follow it).

Write `work/<language>/out-N.json`: a JSON array of strings, the same length
and order as `batch-N.json`.

A practice is given whole and in order: title, Sanskrit name, description,
source, cautions, then its cues from first to last. Read the whole practice
before translating its cues.

## Cues — the most important part

A cue is one thing the guide says, followed by silence. The recorded voice is
English; the translation is shown on screen while that recording plays.

- **One cue in, one cue out.** Never merge two cues, split one, or move a
  sentence from one cue to the next. Each cue is tied to its own recording
  and its own silence.
- Keep the length close to the English. A cue with `hold` 8 is on screen for
  a few seconds; it cannot become a paragraph.
- Keep the voice: second person, present tense, quiet, unhurried, concrete.
  Use the form of address a meditation teacher of the target language uses
  with one adult listener, and the same form in every practice.
- No exclamation marks. No added reassurance, no "now", "please" or "gently"
  that the English does not have.
- Sounds that are heard or made stay as sounds: "so", "hum", "om", "ha" are
  not words to translate. Respell them in the target script.
- Numbers that are counted aloud ("in for four, out for six") stay the same
  numbers.
- A cue repeated inside a practice is translated the same way each time.

## By kind

- `title` — the practice's name ("So Hum", "Alternate Nostril Breath",
  "Before the Day Starts"). Use the established name when the target language
  has one for the technique; otherwise translate plainly.
- `sanskrit` — the Sanskrit name ("So'ham", "Nadi Shodhana"). Never
  translate: keep it in Latin-script languages, respell it in others (the
  real spelling in Indian languages), translate only a note in brackets.
- `description` — two or three sentences on what the practice is. Same plain
  voice as the cues; keep the sentence count.
- `source` — the tradition or text the practice comes from ("Brihadaranyaka
  Upanishad", "Caraka Samhita; the six rasas"). Names of texts and schools
  are respelled, not translated; translate the ordinary words around them.
- `caution` — when not to do the practice, or how to do less of it. Translate
  exactly: do not soften "do not" into "try not to", and do not add warnings.
  Use the ordinary medical word a patient would recognise.
- `kind` — kriya, meditation, pranayama, relaxation, visualisation.
- `posture`, `eyes`, `time_of_day`, `goal` — one-word labels ("seated",
  "soft-open" = eyes half open, "dawn", "anxiety").
- `guna` — rajasic, sattvic: Sanskrit qualities, respell.
- `agni_effect` — the effect on the digestive fire: "cools", "kindles",
  "neutral".
- `season` — the six Ayurvedic seasons by their Sanskrit names (vasanta,
  grishma, varsha, sharad, hemanta, shishira): respell.
- `technique`, `theme` — hyphenated tags such as `breath-counting`,
  `after-eating`, `attention-on-the-gap`. Translate the meaning as a short
  label with spaces, lower case where the language allows. They are also
  what the search finds a practice by, so use words a person would type.

## Rules

- Translate the Sanskrit names of poses and techniques the same way as
  `tools/yoga-names/<language>.json` when the same word appears there.
- Sanskrit terms inside a sentence (prana, agni, vata, pitta, kapha, ujjayi,
  mantra, chakra) stay Sanskrit, respelled where the script is not Latin.
- These texts are about the body, breath and death in places. Translate what
  is there, in the same sober register; do not make it more spiritual, more
  medical or more comforting than the English.
- Keep Western digits. One translation per item, no notes.
