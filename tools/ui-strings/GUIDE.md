# Translating the interface

`work/batch-0.json` … `batch-9.json` hold 1,429 strings (about 5,400 words):
the buttons, titles, labels, messages and placeholders of the app, and the six
texts iOS shows when it asks for a permission. Batches 0–3 are the first round,
4–8 the second (text the app used to hold in plain values: option names, the
constitution questionnaire, error and status messages, notification texts). Each item has

- `i` — its number;
- `k` — what it is: `button`, `title`, `heading`, `label`, `text`, `alert`,
  `message`, `placeholder`, `accessibility` (read aloud by VoiceOver, never
  shown), `permission`;
- `p` — the part of the app (`Food`, `Yoga`, `Practices`, `Settings`, …);
- `s` — the English text to translate;
- `in` — the screens it appears on;
- `code` — the line of Swift it comes from. Read it: it says whether "Set" is
  a verb on a button or a set of an exercise, and what each `%@` is filled
  with;
- `above` — on short items whose own line says little: the declaration or the
  text above it. For an answer of the questionnaire it is the question;
- `plural` and `note` on some items, explained below.

Write `work/<language>/out-N.json`: a JSON array, the same length and order
as `batch-N.json`. A reviewer's corrections go in `work/<language>/fixes-N.json`
as `[{"i": 12, "en": "the English string", "fix": "the corrected translation"}]`.

## Format specifiers — a mistake here crashes the app

- `%@` is replaced by text, `%lld` by a whole number, `%.2f` by a decimal,
  `%%` is a literal per cent sign. Every specifier of the English must be in
  the translation, with the same letters.
- To change their order, number them all: English `%@ for %@` may become
  `%2$@ — %1$@`. Never number only some.
- Never translate, space out or change a specifier (`% @`, `%s`, `％@` are
  all wrong), and never add one.
- A line break inside a string (`\n`) stays, the same number of them, in the
  same places in the meaning.
- `assemble.py` refuses a language while any translation takes different
  arguments from the English, and lists the items.

## Plurals

An item with `"plural": true` has one whole number in it (`%lld items`). Where
the language needs different words for different numbers, answer with an
object instead of a string, with exactly that language's plural categories:

| Categories | Languages |
|---|---|
| `one`, `other` | bg bn ca da de el es es-MX fi fr fr-CA gu hi hu it kk kn ml mr nb nl or pa pt pt-PT sv ta te tr ur |
| `other` only — answer with a plain string | id ja ko ms th vi zh-Hans zh-Hant |
| `one`, `few`, `many`, `other` | cs pl ru sk uk |
| `one`, `few`, `other` | hr ro |
| `one`, `two`, `few`, `other` | sl |
| `one`, `two`, `other` | he |
| `zero`, `one`, `two`, `few`, `many`, `other` | ar |

```json
{"one": "%lld предмет", "few": "%lld предмета", "many": "%lld предметов", "other": "%lld предмета"}
```

Every form keeps the `%lld`. Where the number does not change the words
(`Day %lld`, `Question %lld of 12`, `%lld%%`), answer with a plain string.

Three English strings build their own plural with a second specifier
(`%lld day%@`, `%lld item%@ bought`): the `%@` is the English ending "s" or
nothing. Their `note` says so. Leave that `%@` out and word the translation so
that it reads with any number ("days: %lld" rather than "%lld day").

## How the text should read

- Use the words the system itself uses in that language for Cancel, Done,
  Save, Delete, Edit, Settings, Search, Back, Close, Share. A person sees
  them next to Apple's own.
- Short. A button or a tab has room for one or two words; if the natural
  translation is much longer than the English, find the shorter one. Do not
  abbreviate into something unreadable.
- Capitalise the way the language does, not the way English titles do
  ("Select Workouts" is not two capitalised words in most languages).
- One form of address for the whole app, the one a modern app in that
  language uses with an adult — the same one the practices use
  (`tools/practice-content/<language>.json`).
- Destructive questions ("This action cannot be undone.") keep their full
  weight. Do not soften them.
- No exclamation marks the English does not have.

## Words that must match the rest of the app

- Foods, poses and practices are called what `tools/food-names`,
  `tools/yoga-names` and `tools/practice-content` call them in that language.
- Ayurvedic terms — dosha, vata, pitta, kapha, rasa, virya, vipaka, guna,
  agni, prakriti — stay Sanskrit: kept in Latin-script languages, respelled
  in the others, the real spelling in the Indian languages. The English
  gloss next to them ("Virya · energy", "Vipaka post-digestive effect") is
  translated.
- The app's name, "Ayurveda & Asana Yoga", is not translated or respelled.
  Neither are HealthKit, Apple Health (use Apple's own name for Health in
  that language), AI, kcal, g, mg, METs.
- Units and abbreviations of one or two letters (`%llds` = seconds, `%lld mo`
  = months, `%lldy+` = years and over, `C` / `P` / `F` = carbohydrates,
  protein, fat) become the abbreviation that language uses, as short as the
  English.

## By kind

- `placeholder` — grey sample text in an empty field ("e.g., Morning Run",
  "Blueberries", "John Appleseed"). Translate "e.g." and give a natural
  sample in that language; a sample name may become a local one.
- `accessibility` — a full, speakable phrase; it is heard, not seen.
- `permission` — one or two full sentences shown by iOS under "… would like
  to access …". Say plainly what is read or written and why, as the English
  does. Do not promise more or less.
- `alert`, `message` — complete sentences with their punctuation.

## Rules

- Western digits. One translation per item; no notes, no alternatives.
- A string that is only a name, a unit or a symbol in that language may stay
  as the English; do not leave a real word untranslated.
- Batches 3, 8 and 9 (`onboarding-paywall`) are the first screens a person
  sees and the plan screen: 3 and 8 the earlier variant, 9 the new one, which
  is the one shown by default. They are translated when Mincho says so.

## The second round (batches 4–8)

- **The constitution questionnaire** (batch 4, `Ayurveda`): twelve questions,
  each with three answers, and five check-in questions. The three answers of a
  question describe the three doshas in everyday words; keep them parallel in
  form and about the same length, and do not name the dosha. A question ends
  with a question mark; an answer has no full stop.
- **Fragments.** A few strings are pieces a sentence is put together from
  (`" and "`, `", but "`, `"Contains: "`, `"Created: "`). Their leading and
  trailing spaces are kept for you; translate the word, and look at `code` to
  see what they join.
- **Names of nutrients, muscles, allergens, pose families and months** are
  labels: the ordinary word of the language, capitalised as a label.
- **Notification texts** (`NotificationManager`, reminders) are whole
  sentences shown on the lock screen: short, no exclamation marks.
- A string that also exists in batches 0–3 is not repeated; a word that now
  appears as a label must read the same as it did there.
