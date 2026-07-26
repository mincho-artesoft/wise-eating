# FC-1d — rev4 Part A stop

Date: 2026-07-26
Branch: `fc-1c-g12-rulings`
Starting commit: `36799dc`
Status: **STOPPED IN PART A — FC-2 wiring was not started**

## Executive finding

The founder-corrected Git-tracked size gate passes, and the rev4 matcher
candidate reduces equivalent G12 disagreements from 184 to 80. It does not,
however, satisfy the blocking ontology gates:

1. G6 has one non-contested must-not-exclude failure: `pineapple`.
2. Coconut falls from 105 misses to one, but the last recipe is vetoed by its
   `peanut` name despite containing a positively matched coconut ingredient.
3. The inverted oyster case still fails because the catalogue token is plural
   `mushrooms`, while rev4 supplies singular `mushroom`.

These results mean the director's rev4 model still does not describe the
production matcher/corpus completely. Per the explicit stop conditions, Part B
was not started and no generated artifact was replaced.

## Corrected repository-size gate

The permanent candidate gate enumerates `git ls-files`, not arbitrary files on
disk. It reports all tracked files of at least 1 MB and fails at 90,000,000
bytes.

| Measurement | Actual |
|---|---:|
| Git-tracked files scanned | 990 before this task's pending small files |
| Tracked files ≥1 MB | 26 |
| Largest tracked file | `WiseEating/Food/food_archive_480.mp4` |
| Largest tracked-file size | **82,726,160 bytes** |
| Files over 90 MB | **0** |

The ignored 285,519,148-byte `food_archive_1024.mp4` is absent from
`git ls-files` and is correctly outside this gate. It was not modified.

The handbook now records the founder's corrected rule verbatim:

> No GIT-TRACKED file may exceed 100 MB (GitHub's hard push limit). Split at 90 MB. Bundled media excluded from version control — currently WiseEating/Food/food_archive_1024.mp4 — is out of scope for this gate; it is governed by App Store bundle limits (4 GB uncompressed, 200 MB cellular download) and is tracked separately under the IMG workstream.

`.gitignore` now contains the 1024 archive path once instead of five times.

## Part A implementation candidate

The bounded build-time matcher changes are:

- validate `vetoTokens` as non-empty groups of individual normalized tokens;
- reject duplicate tokens within a group and duplicate groups;
- evaluate matching in the specified order:
  `vetoTokens → negativePhrases → phrases`;
- treat a group as matched only when every exact token occurs anywhere in the
  normalized catalogue name, independent of order or adjacency;
- record token veto diagnostics as `tokens:<group>`;
- retain the existing contiguous negative-phrase and positive-phrase behavior.

The received director inputs remain unchanged:

| Input | SHA-256 | Parsed state |
|---|---|---|
| `ayurveda-data/rules/food-concepts.json` | `e9ab96625bf0abcec1015a633dd1b2adb59dfabfb53d8b9612103df3d4e29913` | rev4, 25 concepts, 75 aliases, 8 concepts with `vetoTokens` |
| `ayurveda-data/tests/exclusion-goldens.json` | `db0c331132001543fd4baf18ab83abcd28b5b109b5a66be53a47b19ca8240ec8` | rev3, 81 must-exclude, 36 must-not-exclude, 7 contested |

## Part A gate actuals

| Gate | FC-1c/rev3 | FC-1d/rev4 actual | Result |
|---|---:|---:|---|
| G5 non-contested must-exclude | 61 pass / 14 unresolved / 0 fail | **62 / 14 / 0** | Improved by the new coconut case. |
| G6 non-contested must-not-exclude | 26 pass / 8 unresolved / 0 fail | **25 / 8 / 1** | **BLOCKING FAILURE: `pineapple`.** |
| `meat` membership | 3,819 / 14,484 (26.367%) | **3,785 / 14,484 (26.132%)** | Lower after rev4 token vetoes; below 40%. |
| Equivalent G12 total, honey omitted | 184 | **80** | 74 WE-8-only / 6 FC-1-only. |
| Coconut-related WE-8-only | 105 | **1** | Improved, but did not fully converge. |
| Oyster mushroom false concepts | mollusc + shellfish | **mollusc + shellfish** | Still not vetoed in the inverted USDA form. |
| Water chestnut | not a tree nut | **not a tree nut** | Pass via `vetoTokens` in either group order. |

No concept exceeds 40%; `meat` is the only concept above 25%.

### Blocking G6 row: `pineapple`

The non-contested golden matches 55 catalogue names. Three are tree-nut members:

| Food ID | Catalogue name | Why tree-nut membership is correct |
|---:|---|---|
| 6344 | Frozen novelties, ice type, pineapple-coconut | Direct `name:coconut` |
| 1000459 | Warm Pineapple Coconut Bake | Direct `name:coconut` plus coconut ingredient |
| 1000508 | Pineapple Coconut Water Smoothie | Direct `name:coconut water` plus coconut ingredient |

This is not a substring false positive. All three rows explicitly contain
coconut, which rev4 deliberately classifies as a tree nut. The current
`pineapple` must-not-exclude case is therefore unsatisfiable over full concept
membership, just as the earlier bare `peanut` case was unsatisfiable. Narrowing
the corpus fixture is director work; weakening coconut membership would violate
the founder ruling.

### Coconut's final residual

The one remaining row is
`recipe.condiment-peanut-fennel-dry-chutney` (food ID 1000337). Its ingredients
include 35 g of food ID 7896, `Nuts, coconut meat, dried (desiccated), toasted`.
That ingredient is correctly a `tree_nuts` member by `name:coconut meat`.

The recipe does not inherit the membership because its title contains
`Peanut`, a current `tree_nuts.negativePhrases` veto. Build order applies
name-level vetoes before recipe ingredient propagation, and propagation
deliberately skips a vetoed owner. WE-8 therefore correctly carries
`Nuts (coconut)` while FC-1 does not.

This is a second model miss: a negative name phrase intended to protect
peanut-only rows can suppress a true tree-nut ingredient in a mixed recipe.
No exception or precedence change was invented.

### Oyster token-order result

The new helper behaves exactly as specified for exact normalized tokens:

| Input | Normalized tokens | `["oyster","mushroom"]` matched? |
|---|---|---|
| `Oyster mushroom` | `oyster`, `mushroom` | Yes |
| `Mushrooms, oyster, raw` | `mushrooms`, `oyster`, `raw` | **No** |

Token-order independence solves inversion, but it does not add stemming or
singular/plural equivalence. The authoritative food ID 6110 therefore has no
token veto and remains in both `mollusc` and `shellfish`. Adding morphology to
the generic normalizer or changing the director token would exceed the
mechanical implementation authorized here.

### G12 recount

Honey remains omitted because “not Vegan” is not an equivalent honey
predicate.

| Concept/direction | Rows |
|---|---:|
| Dairy, WE-8-only | 25 |
| Gluten, WE-8-only | 23 |
| Meat, WE-8-only | 14 |
| Tree nuts, WE-8-only | 4 |
| Fish, WE-8-only | 4 |
| Soy, WE-8-only | 4 |
| Meat, FC-1-only | 3 |
| Dairy, FC-1-only | 1 |
| Mollusc, FC-1-only | 1 |
| Shellfish, FC-1-only | 1 |
| **Total** | **80 = 74 WE-8-only + 6 FC-1-only** |

The four tree-nut residuals are the coconut-vetoed recipe above plus
`dravya.brazil-nut`, `dravya.panchmeva`, and `dravya.thandai`.

## Missing oat/plural fixtures

The exclusion corpus still has no independent must-exclude fixtures for these
rev3/rev4 additions:

- oats: `oat`, `oats`, `oatmeal`, `rolled oats`, `oat bran`, `oat flour`;
- tree-nut plurals: `almonds`, `cashews`, `walnuts`, `pecans`, `pistachios`,
  `hazelnuts`, `macadamias`, `brazil nuts`, `pine nuts`, `chestnuts`;
- regional tree-nut names: `badam`, `kaju`, `pista`, `akhrot`, `chironji`.

Useful paired negatives would include certified/gluten-free oat names and
regional strings whose catalogue fixtures are known to be non-nuts.

## G7 missing viaIngredient fixtures

The prior 4/13 nominal result is unchanged. The nine missing recipe fixtures
remain:

- absent entirely: `butter chicken`, `aioli`, `marzipan`;
- only plain USDA rows, no recipe fixture: `caesar`, `worcestershire`,
  `mayonnaise`, `meringue`, `hollandaise`, `praline`.

## 1024 video reproducibility audit

Report-only; no media action was taken.

- The untracked file is HEVC, 1024×1024, 30 fps, 12,601 frames, 420.033 seconds,
  285,519,148 bytes.
- SHA-256:
  `04de4e63370c280c967b498cf7c29033c04ff4417d29f15712d1329d1bf2ed31`.
- The repository contains lower-resolution 480×480 and 144×144 archives plus
  `frame_map.json` and `frame_timestamps.json`.
- No checked-in archive builder, FFmpeg command, original 1024 source frames,
  source-image set, or lossless 1024 master was found.
- `FoodVideoSource.swift` references the 480 archive; it is not a build recipe
  for the 1024 asset.

Conclusion: the repository cannot reproduce the original-quality 1024 archive
from checked-in sources. The lower-resolution archives could only be upscaled,
not recreate the missing source detail. Unless another external copy exists,
the current untracked file is an irreplaceable single copy and is a backup risk
for the IMG workstream.

## Work not performed after the stop

- FC-2 planner wiring was not started.
- The hardcoded alcohol array was not changed.
- The 75 aliases were not wired into the MP-3 resolver.
- No generated concept, seed, preseed, or search artifact was replaced.
- Full suite, search goldens, resolution corpora, Debug/Release, fresh-install,
  determinism, and cold-launch gates were not run after the blocking Part A
  result.
- The ignored video and media pipeline were not modified.

Resume requires director corrections for the non-contested `pineapple` fixture,
the plural oyster veto, and the mixed peanut-plus-tree-nut recipe precedence.
