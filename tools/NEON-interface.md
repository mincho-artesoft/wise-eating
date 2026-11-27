# For Neon: the interface in 48 languages

The content is translated — foods, recipes, poses, pose descriptions,
practices. The interface around it is not: every button, title and message is
English. This is that job, in the same hand-off format, for the same 48
languages:

ar bg bn ca cs da de el es es-MX fi fr fr-CA gu he hi hr hu id it ja kk kn ko
ml mr ms nb nl or pa pl pt pt-PT ro ru sk sl sv ta te th tr uk ur vi zh-Hans
zh-Hant

## The package

`tools/ui-strings`: 1,394 strings, about 5,100 words. The first round is
batches 0–3 (678 strings), the second batches 4–8 (716 strings, below).

| Batch | Strings | What |
|---|---|---|
| 0 | 284 | AI, analytics, Ayurveda, barcode scanner, calendar, shared views, exercise, fitness |
| 1 | 221 | food, food search, main, meals, nodes, nutrients, practices |
| 2 | 116 | profile, prompts, settings, shopping list, storage, training plan, yoga, permission texts |
| 3 | 57 | onboarding and paywall — **last, and only when Mincho says so** |

Read [`ui-strings/GUIDE.md`](ui-strings/GUIDE.md) before translating. Two
things in it are unlike the earlier packages:

- **Format specifiers.** A string such as `%lld of %lld` or `%@ kcal / %@`
  is a format; a translation with a missing, extra or altered specifier
  crashes the app. `assemble.py` checks every one and does not write a
  language until all of them match.
- **Plurals.** An item marked `plural` may be answered with an object of that
  language's plural forms instead of a string.

## What to write

`work/<language>/out-N.json` (array aligned with `batch-N.json`; a string, or
a plural object), a reviewer's `work/<language>/fixes-N.json`, then:

```
python3 tools/ui-strings/assemble.py            # writes tools/ui-strings/<language>.json
python3 tools/ui-strings/apply.py               # writes the translations into the app
```

`apply.py` puts the finished languages into `Ayura/Localizable.xcstrings`
(under the English key) and the permission texts into
`Ayura/InfoPlist.xcstrings`. It adds; it never removes what a catalogue
already holds. It skips a language that does not have every string;
`--partial` writes batches 0–2 without batch 3, and is used only if Mincho
agrees to ship before the onboarding and paywall strings.

## Order

1. Batches 0–2 for every language: a translator given
   `tools/food-names/<language>.json`, `tools/yoga-names/<language>.json` and
   `tools/practice-content/<language>.json` as glossaries, then a second
   reader with the strong model. The second reader's first job here is the
   specifiers and the system words (Cancel, Done, Save…); its second is
   length.
2. `assemble.py`, and a report per language: corrections, anything
   `assemble.py` refused, and the strings left identical to the English with
   the reason for each kind (units, names).
3. Stop. Batch 3 and `apply.py` wait for Mincho.
4. After `apply.py`: `tools/search-golden/remote.sh run` must still pass, and
   the app must build.

## Second round: batches 4–8

The app has since been changed so that the text it held in ordinary values is
translatable too. `extract.py --append` added it after the first round's
batches; item numbers go on from 678 and batches 0–3 are untouched.

| Batch | Strings | What |
|---|---|---|
| 4 | 215 | ads, analytics, Ayurveda (with the constitution questionnaire), barcode scanner |
| 5 | 257 | calendar, shared views, exercise, fitness, food |
| 6 | 215 | food search, health, live activity, main (tabs, permissions, notifications), meals, nodes, nutrients, practices, profile, settings, shopping list, storage, training plan, yoga |
| 7 | 17 | Live Activity widget, subscription period words |
| 8 | 12 | onboarding — **last, with batch 3, only when Mincho says so** |

Same procedure as batches 0–2, and the section "The second round" of the
guide. `assemble.py` reads every batch that has an out file and keeps what a
language already has.

Still English after this: the paywall and the profile wizard (about to be
rewritten), the names of vitamins and minerals from the seed data, default
names the app saves (meals, trainings), and the built-in theme names.

Do not change Swift code, and do not edit the catalogues by hand.

## If the English changes

`tools/search-golden/remote.sh test` (a build), `tools/ui-strings/fetch.sh`
(copies what the compiler extracted), `python3 tools/ui-strings/extract.py
--append`.
