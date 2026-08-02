# nutrition/

Nutrition sourcing for the 376 placeholder dravyas — the ones with no USDA match,
so their food row carries no macros, no micronutrients and no description.

## Files

    ifct2017-compositions.csv   IFCT 2017, 542 Indian foods, 214 value columns.
                                From npm @ifct2017/compositions. Every nutrient
                                is g/100g (calcium 0.181 = 181 mg); energy is kJ.
                                Each value has a parallel `_e` column carrying
                                the published SD — that is the spread, not a guess.
    ifct2017-descriptions.csv   food codes, scientific names, local-language names

    match_ifct.py               dravya -> IFCT matcher. Writes /tmp/match.json.
    apply_ifct_values.py        writes matched values into dravya_foods.json
    build_dravya_foods.py       builds the 376 records in Legacy/foods.json shape

    dravya_foods.json           the output under review
    ifct-unresolved.json        22 ambiguous + 298 unmatched
    canon-unbuilt.json          26 canon entries never built as dravya or recipe

    REJECTED_usda_analogue_matcher.py
                                kept as a warning, not a tool. See below.

## IFCT HEADER LABELS ARE NOT RELIABLE

Verify every new mapping against the data and its position in the composition
table, never against the header alone.

- `glu` is labelled "Glucose", but it sits in the amino-acid block and is
  glutamic acid. Free glucose is the separate `glus` column.
- `amiac` is labelled "Essential Amino acids", but its value equals the sum of
  `amiace` essential + `amiacce` conditionally essential + `amiacne`
  non-essential amino acids. It is the total amino-acid mass.

Both labels have already produced plausible-looking wrong mappings during
review; they are data hazards, not cosmetic naming issues.

## THERE IS NO SYNONYM LIST

match_ifct.py builds its synonyms from IFCT's own `Local Name; lang` column,
which carries the Hindi, Tamil, Marathi, Malayalam, Kannada, Bengali, Oriya,
Punjabi and Telugu names for each row, e.g. for amaranth seed:

    A. Moricha guti; H. Ramdana; Kan. Danthu beeja; Kash. Mawal; ...

Each is stripped of its language prefix and normalised, giving 3,435 match keys
across 542 foods. A dravya matches when its name, sanskrit name or any alias
normalises to exactly one of those keys.

So to tell a genuine non-match from a synonym gap: grep the dravya's names
against the `lang` column. If it appears there and still did not match, the
normaliser is at fault. If it does not appear, IFCT has no row for it — which
is expected for the ~92 preparations and ~42 medicinal entries.

Matching is deliberately strict: exact normalised token-set equality, no
scoring, no threshold. That is a decision, not laziness.

## WHY THE REJECTED MATCHER IS KEPT

REJECTED_usda_analogue_matcher.py scored the 376 against our own 12,601 USDA
rows by token overlap. At a 0.60 threshold it found 63 analogues. Reading them:

    Edible lime (chuna)   -> Lime, raw                     1.00
    Cucumber seed (magaz) -> Cucumber, raw                 1.00
    Tulsi seed            -> Holy basil (dried)            1.00
    Black rice            -> Black beans and white rice    0.75
    Barley water          -> Soup, mushroom barley, canned 0.63

Chuna is calcium hydroxide. The matcher scored it 1.00 against a citrus fruit.
Roughly a third of the 63 were defensible and all 63 were discarded.

This is the wrong-food image bug in nutritional form, and worse, because nobody
looks at a vitamin C figure and thinks "that is the wrong food". Any future
loosening of match_ifct.py must be reviewed food by food.

## RULES

Never invent a nutrient value. Source it or leave it null. Null means "not
established", never zero. `_review` in dravya_foods.json is review scaffolding —
strip it, and `dravyaId`, before ingest.
