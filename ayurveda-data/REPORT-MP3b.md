# MP-3b — Held-Out Resolution Measurement

Date: 2026-07-26

Branch: `mp-3-deterministic-resolution`

Frozen scorer commit: `37552c069e957cac8b1e450ab7d77f859c6c7047`

Status: **MEASURED — BLOCKING CONTROL DEFECT FOUND; NO TUNING**

## Headline

| Corpus | Real-food passes | Rate | Controls |
|---|---:|---:|---:|
| MP-3 training (`resolution-goldens.json`) | 56/56 | 100% | 3/3 unresolved |
| MP-3b held-out (`resolution-holdout.json`) | **35/48** | **72.9%** | **4/5 unresolved** |

The held-out score is materially below the training score. Of the 13
real-food non-passes, nine are honest `UNRESOLVED` coverage gaps, three are
confident resolution-contract failures, and one is an internally
contradictory held-out predicate rather than a resolver error.

The blocking finding is the fifth control: `food` resolved to **Oatmeal, fast
food, plain** at score **63**. Per the dispatch, the frozen measurement stopped
without tuning. `the`, the other new control shape, remained unresolved.

## Method and measurement integrity

- The supplied held-out file parsed as 53 cases: 48 real-food cases and five
  controls, with 158 total `mustNotMatch` trap patterns.
- Input SHA-256:
  `a2331c3e746c22072b171c20089e18b186cd0a44aff7b8abcd4e3d469bbf6f6f`.
- The existing MP-3 harness extracted the exact production helper between
  `MP3_TESTABLE_BEGIN` and `MP3_TESTABLE_END`; no resolver or harness source
  was edited.
- Production resolver source SHA-256 before and after measurement:
  `aece8725c8bcdfd28bd263ac640a45d81515067f406f950b7eeea00d1625aa6a`.
- The shipped cache contained 14,484 compact foods. The two existing
  engine-excluded IDs left 14,482 eligible candidates.
- Two evaluations in one process were identical. A newly launched harness
  evaluation was also byte-identical. Both captured JSON results had SHA-256
  `a4b6f282ec64911af4ac3f08e8e8b8207709ab5c7463b5d3c1d26e0dca763aa8`.
- No alias, weight, threshold, special case, resolver code, index artifact,
  or catalogue row changed.

This was a measurement-only task. No build, full suite, or other product gate
was run or claimed.

## Failure modes

### Unexpected unresolved real foods — 9

These are honest coverage gaps: `rajma`, `dahi`, `sooji`, `saunf`,
`dalchini`, `steamed broccoli`, `roasted almonds`, `chicken stock`, and
`nutritional yeast`.

### Confident incorrect decisions — 4

Three occur on real-food cases and one is the blocking control. The complete
list is:

| Concept | Score | Returned row | Why incorrect |
|---|---:|---|---|
| `sambar` | 87 | Sambar, vegetable stew | Correct dish name, but a non-recipe row was selected although the case requires a recipe row. |
| `idli` | 201 | Idli | Correct dish name, but a non-recipe row was selected although the case requires a recipe row. |
| `fresh ginger` | 57 | Spices, ginger, ground | Wrong ingredient form; fresh root was requested. |
| `food` | 63 | Oatmeal, fast food, plain | Blocking generic-control false positive caused by the incidental token `food`. |

The real-food wrong-confident/contract count is **3**. Including the control
defect, the total confident incorrect-decision count is **4**.

### Mis-authored held-out predicate — 1

`apple cider vinegar` returned the exact intended row **Apple Cider Vinegar**
at score 220, but the case also forbids `cider, apple`. The accepted harness
matches multi-token patterns without regard to token order, so that forbidden
pattern necessarily matches the correct row. The raw result remains `FAIL`;
the case was not skipped or rewritten. This is a corpus-definition finding,
not a resolver-quality defect.

## Controls

| Concept | Status | Resolved food | Score | Finding |
|---|---|---|---:|---|
| `glorbnax` | UNRESOLVED | — | — | Correct |
| `asdfgh` | UNRESOLVED | — | — | Correct |
| `the` | UNRESOLVED | — | — | Correct; new stopword-only shape |
| `a` | UNRESOLVED | — | — | Correct |
| `food` | FAIL | Oatmeal, fast food, plain | 63 | **Blocking false positive; new generic-word shape** |

Controls therefore pass **4/5**, not 5/5.

## Ginger form finding

| Concept | Status | Resolved food | Score | Tier |
|---|---|---|---:|---|
| `fresh ginger` | FAIL | Spices, ginger, ground | 57 | classical |
| `ground ginger` | PASS | Spices, ginger, ground | 75 | classical |

The ground form succeeds, but the fresh form does not. The form signal is
therefore **not working correctly as a disambiguator**: it recognizes the
literal ground form but does not prefer shipped ID 6687, **Ginger root, raw**,
for `fresh ginger`. This is the exact corpus gap identified by the director;
no alias or scoring change was made.

## Alias-attributable analysis

The 14 observed non-passes (13 real foods plus the failed control) separate as
follows:

| Cause | Count | Cases |
|---|---:|---|
| One canonical alias would mechanically satisfy the case | **7** | `rajma` → kidney bean; `dahi` → yogurt; `sooji` → semolina; `saunf` → fennel; `dalchini` → cinnamon; `chicken stock` → chicken broth; `nutritional yeast` → the catalogue's plain yeast row |
| Scorer/token/form/type logic; a food-name alias is not the right fix | **6** | `sambar`, `idli`, `fresh ginger`, `steamed broccoli`, `roasted almonds`, and control `food` |
| Held-out predicate defect | **1** | `apple cider vinegar` |

The first bucket is alias-attributable, and supports the proposed FC-1
canonical concept layer rather than more hand-maintained resolver aliases.
The `nutritional yeast` classification is mechanical relative to this
corpus's allowed plain `yeast` result; the ontology must still decide whether
that equivalence is nutritionally safe.

The logic bucket has distinct evidence:

- `sambar` and `idli` are dish concepts, but neither activates the frozen
  composite/recipe preference, so exact non-recipe rows win.
- `fresh ginger` loses to ground ginger despite the raw-root row being in the
  shipped catalogue.
- `steamed` is not canonicalized to the scorer's `steam` preparation token.
- dry-roasted almond rows carry `dry`; the frozen cooked-form logic treats
  that token as a conflict even though it is part of `dry roasted`.
- `food` is allowed as a semantic head and is also ignored as candidate extra
  content, permitting a generic-word false positive.

## Full 53-case held-out result

| Concept | Status | Resolved food | Score | Tier |
|---|---|---|---:|---|
| `rajma` | UNRESOLVED | — | — | — |
| `masoor dal` | PASS | Masoor Dal Chilla | 65 | classical |
| `methi` | PASS | Methi thepla | 91 | classical |
| `fenugreek seeds` | PASS | Spices, fenugreek seed | 111 | classical |
| `hing` | PASS | Asafoetida (Hing) | 67 | derived |
| `besan` | PASS | Besan ladoo | 91 | classical |
| `dahi` | UNRESOLVED | — | — | — |
| `bhindi` | PASS | Bhindi Sabzi | 55 | classical |
| `lauki` | PASS | Lauki Paratha | 55 | classical |
| `sooji` | UNRESOLVED | — | — | — |
| `poha` | PASS | Kanda poha | 71 | classical |
| `sabudana` | PASS | Sabudana khichdi | 91 | classical |
| `makhana` | PASS | Fox nut (makhana) | 71 | classical |
| `amla` | PASS | Dried amla | 101 | classical |
| `tamarind` | PASS | Tamarind | 197 | derived |
| `ajwain` | PASS | Ajwain | 197 | derived |
| `saunf` | UNRESOLVED | — | — | — |
| `dalchini` | UNRESOLVED | — | — | — |
| `sambar` | FAIL | Sambar, vegetable stew | 87 | classical |
| `idli` | FAIL | Idli | 201 | classical |
| `fresh ginger` | FAIL | Spices, ginger, ground | 57 | classical |
| `ground ginger` | PASS | Spices, ginger, ground | 75 | classical |
| `boiled egg` | PASS | Egg, whole, boiled or poached | 75 | derived |
| `egg white` | PASS | Egg, white, dried | 111 | derived |
| `raw spinach` | PASS | Spinach, raw | 85 | classical |
| `steamed broccoli` | UNRESOLVED | — | — | — |
| `roasted almonds` | UNRESOLVED | — | — | — |
| `greek yogurt` | PASS | Yogurt, Greek, plain, lowfat | 70 | estimated |
| `cottage cheese` | PASS | Cottage cheese, farmer's | 97 | derived |
| `cheddar` | PASS | Cheese, Cheddar | 71 | classical |
| `butter` | PASS | Butter, without salt | 101 | classical |
| `cream` | PASS | Cream, fluid, heavy whipping | 83 | classical |
| `olives` | PASS | Olives, NFS | 92 | estimated |
| `peanut butter` | PASS | Peanut butter | 206 | estimated |
| `quinoa` | PASS | Quinoa, no added fat | 97 | derived |
| `sourdough bread` | PASS | Bread, french or vienna (includes sourdough) | 62 | estimated |
| `avocado` | PASS | Avocado, raw | 97 | derived |
| `ground beef` | PASS | Beef, ground | 66 | estimated |
| `salmon` | PASS | Fish, salmon, raw | 71 | classical |
| `maple syrup` | PASS | Syrups, maple | 89 | classical |
| `apple` | PASS | Apple, dried | 97 | derived |
| `orange` | PASS | Orange, raw | 97 | derived |
| `dates` | PASS | Fresh dates | 101 | classical |
| `corn` | PASS | Corn, raw | 97 | derived |
| `kale` | PASS | Kale, raw | 101 | classical |
| `chicken stock` | UNRESOLVED | — | — | — |
| `apple cider vinegar` | FAIL | Apple Cider Vinegar | 220 | estimated |
| `nutritional yeast` | UNRESOLVED | — | — | — |
| `glorbnax` | UNRESOLVED | — | — | — |
| `asdfgh` | UNRESOLVED | — | — | — |
| `the` | UNRESOLVED | — | — | — |
| `a` | UNRESOLVED | — | — | — |
| `food` | FAIL | Oatmeal, fast food, plain | 63 | derived |

## Conclusion

The frozen scorer's held-out real-food accuracy is **35/48 (72.9%)**, versus
the training corpus's **56/56 (100%)**. The observed gap is mixed: seven cases
are mechanically alias-attributable, while five real-food cases expose
scorer/form/type behavior and one case exposes a held-out predicate defect.
Most importantly, the resolver makes one generic-control confident false
match. This report records the finding without attempting to improve it.

The branch is intentionally not merged and not pushed.
