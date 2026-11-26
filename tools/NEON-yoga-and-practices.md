# For Neon: yoga and practices in 47 languages

The food names and the recipe content are done. This is the same job for the
yoga catalogue and the guided practices, in the same file format, with the
same languages:

ar bg bn ca cs da de el es es-MX fi fr fr-CA gu he hi hr hu id it ja kk kn ko
ml mr ms nb nl or pa pl pt pt-PT ro ru sk sl sv ta te th tr uk ur vi zh-Hans
zh-Hant

## The three packages

| Folder | What | Strings | Words | Batches |
|---|---|---|---|---|
| `tools/yoga-names` | pose titles, Sanskrit names, families, muscle groups, levels | 1,827 | 5,400 | 2 |
| `tools/yoga-content` | pose descriptions; breath, gaze and caution labels; the parts of a sequence's title and note | 1,062 | 22,100 | 4 |
| `tools/practice-content` | the 60 practices: titles, descriptions, sources, cautions, labels and the 601 spoken cues | 1,023 | 10,900 | 4 |

About 38,400 English words per language. The 4,419 sequences need nothing of
their own: a sequence's title and note are put together from 38 strings in
`yoga-content`, and its poses are in `yoga-names`.

Each folder has `GUIDE.md` — read it before translating — and
`work/batch-N.json`. An item is `{"i": number, "k": kind, "s": English text,
…context}`; only `s` is translated.

## What to write

For each language and batch, `work/<language>/out-N.json`: a JSON array of
strings, exactly as long as `batch-N.json` and in the same order. A reviewer's
corrections, if any, go in `work/<language>/fixes-N.json` as
`[{"i": 12, "en": "the English string", "fix": "the corrected translation"}]`,
the same as for the food names.

Then:

```
python3 tools/yoga-names/assemble.py          # writes tools/yoga-names/<language>.json
python3 tools/yoga-content/assemble.py
python3 tools/practice-content/assemble.py
python3 tools/food-names/pack.py --catalog yoga <languages>   # yoga names into the app
```

`assemble.py` skips a language with a missing or short batch and says which.
It also counts translations whose numbers differ from the English; look at
those.

## Order

1. `yoga-names` first, for every language. The other two packages must call a
   pose what this one calls it.
2. `yoga-content` and `practice-content`, each translator being given that
   language's finished `tools/yoga-names/<language>.json` as a glossary.
3. A second reader per language, as for the food names. The cues and the
   cautions deserve it most: a cue is read by someone with their eyes half
   closed, and a caution is safety text.

## Rules that hold for all three

- Sanskrit names are never translated. Latin-script languages keep them as
  they are; other scripts respell them the way that language's yoga books do,
  and the Indian languages use the word's real spelling.
- A practice's cues are translated one to one: never merged, split or
  reordered. Each is tied to its own English recording and its own silence,
  and the translation is what is shown on screen while it plays.
- Cautions keep exactly the strength of the English.
- Western digits; no notes, alternatives or explanations in the output.

## What is ready in the app and what is not

- **Yoga names: ready.** `pack.py --catalog yoga` writes
  `Ayura/Yoga/Names/yoga_names.<language>.z`, the app picks it up by language,
  and `testYogaSearch` plus the golden run cover the search.
- **Yoga content and practice content: the app does not read them yet.**
  `<language>.json` is the deliverable. Do not write `.z` files or app code
  for these two unless Mincho asks; the lookup (English string → translation,
  the same shape as `RecipeContentLocalizer`) and the sequence title built
  from its parts are a separate piece of work.
- The narration stays English. Translated cues are subtitles.

## If the English changes

`python3 tools/yoga-names/build_segments.py && python3 tools/yoga-names/make_batches.py`,
`python3 tools/yoga-content/extract.py`, `python3 tools/practice-content/extract.py`
rewrite the string lists and the batches. Item numbers change when they do, so
finish a language before re-extracting, or redo its `out` files.
