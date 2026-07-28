# MP-3c — Two Scorer Logic Fixes

Date: 2026-07-26

Branch: `mp-3-deterministic-resolution`

Starting tip: `777f0d4ba31c044c56b8e4bf6401ab3189c84a30`

Status: **COMPLETE — LOCAL COMMIT ONLY, NOT PUSHED**

## Outcome

The resolver now closes the two authorized scorer defects without adding an
alias or changing the acceptance threshold:

1. a common one-token concept must be a substantive food-identity anchor in
   the candidate, rather than an incidental token anywhere in its name; and
2. catalogue form words are canonicalized and scored symmetrically for
   compatible and conflicting forms.

The 59-case training corpus retains all 59 expectations. The corrected
held-out rev2 corpus improves from MP-3b's published **35/48** to **40/48**.
The remaining eight real-food misses are all honest `UNRESOLVED` outcomes;
there are **zero wrong-confident matches**. All five controls, including
`food`, are unresolved.

`fresh ginger` now resolves to shipped ID 6687, **Ginger root, raw**, at score
71. `roasted almonds` resolves to **Nuts, almonds, dry roasted, without salt
added** at score 80. `steamed broccoli` remains unresolved because the shipped
catalogue has raw and boiled/cooked broccoli rows but no compatible steamed
row; the symmetric method rule correctly does not substitute boiled for
steamed.

## Frozen boundaries

- `aliasPhrases(for:)` is byte-identical to the function at `348d8fc`.
  Both blocks have SHA-256
  `46afe2ce151443412181964d4b76926660c42c4bfa7fcf90c918fdad9f2c09f2`.
- No alias was added, removed, or edited.
- `minimumScore` remains `46.0`.
- No FoodSearch ranking, seed artifact, search index, nutrition path, UI,
  lifecycle, or claims code changed.
- The director-supplied `resolution-holdout.json` rev2 is retained exactly as
  the corrected input: zero `expectRecipe` assertions and the relaxed apple
  cider vinegar trap.

## Bug A — substantive headword principle

### Chosen rule

The implementation combines catalogue discriminating power with an identity
anchor:

1. The rule is considered only for one-token concepts whose head matches at
   least `max(64, ceil(candidateCount × 0.5%))` catalogue candidates. Rare,
   discriminating regional words therefore keep the existing path.
2. A common head must anchor the candidate's first identity phrase, or an
   exact second identity phrase after a one-token catalogue class wrapper
   such as `Spices, ginger` or `Fish, salmon`.
3. Every token in that identity phrase must be explained by the concept or
   its already-frozen aliases.
4. The concept must explain at least half of the candidate's non-form,
   non-structural content.
5. A modifier-only form such as `raw`, `fresh`, or `instant` cannot become a
   food head by itself.

This is not a stoplist. It tests the structural role and explanatory share of
the token in each candidate, while the 64/0.5% floor limits the stricter
identity proof to catalogue-common heads. The score threshold is unchanged.

For the blocking case, `food` is common but does not anchor the first identity
phrase in **Oatmeal, fast food, plain**; `oatmeal` and `fast` are also
unexplained content. The candidate is rejected before score acceptance.

### Incidental-token generality

The exact production helper was run against all 14,482 eligible shipped
candidates. The dispatch required at least eight tokens beyond `food`; all 14
additional probes below are also unresolved.

| Standalone concept | Result |
|---|---|
| `raw` | UNRESOLVED |
| `cooked` | UNRESOLVED |
| `mix` | UNRESOLVED |
| `salad` | UNRESOLVED |
| `prepared` | UNRESOLVED |
| `canned` | UNRESOLVED |
| `instant` | UNRESOLVED |
| `baby` | UNRESOLVED |
| `nfs` | UNRESOLVED |
| `dry` | UNRESOLVED |
| `fresh` | UNRESOLVED |
| `juice` | UNRESOLVED |
| `home` | UNRESOLVED |
| `restaurant` | UNRESOLVED |
| `food` | UNRESOLVED |

## Bug B — symmetric form vocabulary

### Canonical vocabulary

The semantic relationships are deliberately explicit, while surface
spellings are derived from the catalogue's naming through canonicalization:
`baked` → `bake`, `boiled` → `boil`, `cooked` → `cook`, `fried` → `fry`,
`frozen` → `freeze`, `grilled` → `grill`, `powdered` → `powder`,
`prepared` → `prepare`, `roasted` → `roast`, `steamed` → `steam`, and
`whipped`/`whipping` → `whip`. The shipped catalogue exercises the resulting
canonical vocabulary.

Vocabulary size: **29**.

`baby`, `bake`, `boil`, `breast`, `can`, `cook`, `dal`, `dry`, `flour`,
`fresh`, `freeze`, `fry`, `grill`, `ground`, `instant`, `leaf`, `milk`,
`oil`, `powder`, `prepare`, `raw`, `roast`, `seed`, `split`, `steam`,
`tadka`, `tea`, `whip`, `whole`.

### Relationships

| Requested form | Compatible candidate forms | Conflicting candidate forms |
|---|---|---|
| fresh/raw | fresh, raw | dry, ground, powder, canned, frozen, or any cooked form |
| ground/powder/dry | exact form; ground and powder are compatible | fresh or raw |
| generic cooked | baked, boiled, cooked, fried, grilled, roasted, steamed | fresh or raw |
| a specific cooking method | exact method, or generic cooked | every other specific cooking method; fresh/raw |
| canned/frozen | exact form | fresh/raw and the other preservation form |
| whole | whole | split |
| split | split | whole |
| seed | seed | leaf |
| leaf | leaf | seed |

An explicit match retains the established `+10` form signal and gains the
existing preparation preference. A missing form remains `−14`; a conflicting
preparation also receives the symmetric conflict penalty. An atomic concept
with an explicit preparation form receives an additional recipe penalty, so a
composite such as **Fresh Ginger Achar** cannot outrank the compatible atomic
root row. Product-form words such as milk, oil, flour, seed, and leaf remain
content-bearing when the concept names them.

The scorer therefore treats both directions consistently:

- `fresh ginger` → **Ginger root, raw**, not ground ginger or ginger achar;
- `ground ginger` → **Spices, ginger, ground**;
- `roasted almonds` → the dry-roasted almond row; `dry roasted` is not treated
  as a raw/dry conflict when the requested cooking method `roast` is present;
- `steamed broccoli` does not silently substitute raw or boiled broccoli; and
- seed/leaf and whole/split synthetic inverses select the matching side.

## Held-out rev2 result

### Score bridge

| Measurement | Pass | Unresolved real foods | Wrong-confident real foods | Notes |
|---|---:|---:|---:|---|
| MP-3b published rev1 | 35/48 | 9 | 4 raw `FAIL` rows | Three of the four were later accepted as director predicate defects. |
| Rev2 accounting at the frozen scorer | 38/48 | 9 | 1 | Sambar, idli, and apple cider vinegar become passes from predicate correction alone; fresh ginger remains wrong. |
| MP-3c rev2 | **40/48** | **8** | **0** | Fresh ginger and roasted almonds are fixed by scorer logic. |

The total published delta is **+5 passes**: three predicate corrections and
two scorer improvements. The code-only delta against the corrected rev2
accounting is **+2 passes**.

### Remaining failures

| Concept | Result | Classification | Finding |
|---|---|---|---|
| `rajma` | UNRESOLVED | alias-attributable | FC-1 canonical concept layer: kidney bean |
| `dahi` | UNRESOLVED | alias-attributable | FC-1 canonical concept layer: yogurt |
| `sooji` | UNRESOLVED | alias-attributable | FC-1 canonical concept layer: semolina |
| `saunf` | UNRESOLVED | alias-attributable | FC-1 canonical concept layer: fennel |
| `dalchini` | UNRESOLVED | alias-attributable | FC-1 canonical concept layer: cinnamon |
| `chicken stock` | UNRESOLVED | alias-attributable | FC-1 canonical concept layer: chicken broth |
| `nutritional yeast` | UNRESOLVED | alias-attributable | FC-1 must choose a nutritionally safe canonical yeast row |
| `steamed broccoli` | UNRESOLVED | form/catalogue logic | No steamed row exists; boiled is now an explicit conflicting method. |

No remaining case returns a wrong food. The seven alias-attributable misses
were intentionally left untouched.

### Controls

| Control | Result |
|---|---|
| `glorbnax` | UNRESOLVED |
| `asdfgh` | UNRESOLVED |
| `the` | UNRESOLVED |
| `a` | UNRESOLVED |
| `food` | UNRESOLVED |

Controls pass **5/5**.

## Sambar and idli row-type audit

The original `expectRecipe` assertions were not literally unsatisfiable:
recipe rows exist for both terms. They were nevertheless the wrong acceptance
condition for the canonical concept because every recipe row is a qualified
variant, while the selected non-recipe row is the direct food.

| Concept | All name matches | `isRecipe` rows | Exact bare-name recipe rows | Selected row |
|---|---:|---:|---:|---|
| sambar | 12 | 10 | 0 | Sambar, vegetable stew (`isRecipe = false`, score 87) |
| idli | 6 | 3 | 0 | Idli (`isRecipe = false`, score 201) |

Examples of recipe rows are **Classic Mixed Vegetable Sambar**, **Bottle
Gourd Sambar**, **Rice-Mung Steamed Idli**, and **Rava Idli**. Requiring a
recipe would force a more specific variant for a bare dish concept. Rev2
correctly makes row type informational.

## Gate results

| Gate | Result | Evidence |
|---|---|---|
| MP3c-G1 Debug + Release | PASS | Clean generic-iOS Debug and Release builds, signing disabled, each succeeded from a separate empty DerivedData directory. Both report the same 45 unique pre-existing warning messages recorded by MP-3; no new warning was introduced. |
| MP3c-G2 full suite | PASS | **85/85** in 28.947s on the final source: prior 81 plus four MP-3c tests. |
| MP3c-G3 search goldens | PASS | 25/25 legacy plus 2/2 safety, unchanged. |
| MP3c-G4 training corpus | PASS | All 59 expectations: 56/56 positive cases pass and 3/3 controls are unresolved. |
| MP3c-G5 held-out rev2 | PASS | **40/48** real-food passes; 8 unresolved, 0 wrong-confident. Previous published score was 35/48. |
| MP3c-G6 controls | PASS | 5/5 unresolved, including `food`. |
| MP3c-G7 incidental generality | PASS | 15/15 standalone incidental probes unresolved; 14 are beyond `food`. |
| MP3c-G8 determinism | PASS | Training, held-out rev2, and incidental corpora each run twice in one executable and once in a clean relaunch with byte-identical decoded output. |
| MP3c-G9 no FoundationModels | PASS | iPhone 17 Pro simulator, iOS 26.2: exact production helper resolved 56 training positives and left 3 controls unresolved against 14,482 eligible rows. `otool` found no `FoundationModels` link and the helper reports no system model use. |

### Determinism evidence

| Evidence | SHA-256 |
|---|---|
| Training run and clean relaunch | `438d9bd1880c0cc7be57884829f40ec697140a73183b39143072a4a1d7a980a0` |
| Held-out rev2 canonical output | `5b1de7ce33428411e2b4f688455c3d270b9945b22f684868169fa825213d4d71` |
| Incidental-token canonical output | `95677c93cc8d485d45c03821dcaa4dff5aa442a4359057198b0d17afacb1cbe3` |

`sameSessionIdentical` is true for every corpus, and the test compares each
canonical output directly with a separately launched executable's output.

## Scope

Production logic changed only inside the marked deterministic resolver in
`USDAWeeklyMealPlanner.swift`. Tests changed only in
`test_mp3_resolution.py`; the old synthetic “grilled” property now uses a
grilled chicken candidate rather than a roasted candidate because distinct
cooking methods are intentionally conflicting. The corrected held-out rev2
file and this report are the only data/document changes.

The branch is intentionally not merged and not pushed.
