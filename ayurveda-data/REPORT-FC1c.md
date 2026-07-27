# FC-1c — rev3 G12 rulings audit

Date: 2026-07-26
Branch: `fc-1c-g12-rulings` from `ayurveda-app` `95da00f`
Status: **STOPPED IN PART A — FC-2 wiring was not started**

## Executive finding

The non-contested exclusion safety gate remains green, but the director's
coconut ruling is not implemented by the supplied rev3 ontology. Rev3 removes
`coconut` from `tree_nuts.negativePhrases` without adding `coconut` to
`tree_nuts.phrases`, to a child concept, or to an override. Removing a veto
cannot create a positive match.

Consequently, all **105** coconut-related tree-nut disagreements identified in
FC-1b remain. Wiring FC-2 would make this incomplete ontology authoritative for
the 12,601 plain USDA rows and would under-flag coconut there, contrary to the
director's conservative allergen ruling. Part B therefore did not begin.

The received director artifact was not edited. Its SHA-256 is
`df4bfae9e01dd9007a3abbc7401a7f1b53855c98df4637202a343361b9e268a4`.

## Part A actuals

The audit built membership in memory from rev3, the committed seed, the 12,601
USDA catalogue rows, empty overrides, and the production token-boundary
matcher. No generated artifact was written.

| Check | FC-1b | rev3 actual | Finding |
|---|---:|---:|---|
| Non-contested must-exclude | 61 pass / 14 unresolved / 0 fail | **61 / 14 / 0** | No count improvement. The corrected oat and plural/regional cases are not separate fixtures in the current exclusion corpus. |
| Non-contested must-not-exclude | 26 pass / 8 unresolved / 0 fail | **26 / 8 / 0** | **GREEN — zero failures.** |
| `meat` catalogue membership | 3,890 / 14,484 (26.857%) | **3,819 / 14,484 (26.367%)** | Improved by 71 rows after removing `flesh`. |
| Largest concept | `meat`, 26.857% | **`meat`, 26.367%** | Below the 40% stop threshold. |
| G12 disagreements | 1,217 including invalid honey proxy | **184**, with honey omitted | 6 FC-1-only and 178 WE-8-only. The invalid 831-row honey comparison is gone. |

The non-contested G5 count stays flat because the 80-case must-exclude corpus
does not contain an oat case or a new plural/regional tree-nut case. Catalogue
membership still moved as expected: `gluten` rose from 489 to **679** members
and `tree_nuts` rose from 209 to **324**.

### G12 recount

Honey is omitted entirely because FC-1b proved that “not Vegan” is not an
equivalent honey predicate.

| Concept and direction | Rows | Example |
|---|---:|---|
| Tree nuts, WE-8 only | **108** | `dravya.coconut-fresh` |
| Dairy, WE-8 only | 25 | `dravya.basundi` |
| Gluten, WE-8 only | 23 | `dravya.khakhra` |
| Meat, WE-8 only | 14 | `dravya.catla` |
| Fish, WE-8 only | 4 | `dravya.catla` |
| Soy, WE-8 only | 4 | `dravya.hawaijar` |
| Dairy, FC-1 only | 1 | `dravya.chaas-masala` |
| Meat, FC-1 only | 3 | `dravya.desi-egg` |
| Mollusc, FC-1 only | 1 | `dravya.oyster-mushroom` |
| Shellfish, FC-1 only | 1 | `dravya.oyster-mushroom` |
| **Total** | **184** | **178 WE-8-only / 6 FC-1-only** |

Of the 108 tree-nut WE-8-only rows, **105 carry
`Nuts (coconut)`**. The other three are `dravya.brazil-nut`,
`dravya.panchmeva`, and `dravya.thandai`.

The corpus contains 11 coconut-tagged dravyas and 104 recipes that inherit a
coconut ingredient. Some recipes also contain another recognized tree nut;
after accounting for those overlaps, the exact unresolved coconut disagreement
population remains the same 105 rows reported by FC-1b.

### Why rev3 cannot apply the coconut ruling

- `tree_nuts.phrases` contains no `coconut` phrase.
- No other concept has a positive phrase containing `coconut`.
- `concept-overrides.json` has zero overrides.
- The only coconut-related canonical alias is `nariyal → coconut`; aliases feed
  deterministic food resolution and are not membership assertions.
- Every coconut food ID inspected has neither a tree-nut reason nor a
  tree-nut negative veto. Examples:

| Food ID | Catalogue name | Tree-nut member |
|---:|---|---|
| 7556 | Nuts, coconut meat, raw | No |
| 7557 | Nuts, coconut meat, dried (desiccated), not sweetened | No |
| 7561 | Nuts, coconut water (liquid from coconuts) | No |
| 8580 | Oil, coconut | No |
| 900076 | Coconut chutney | No |

This is an incomplete artifact application, not a disagreement with the
director's policy ruling. Fixing it requires the director-owned ontology to
supply a positive tree-nut membership path.

### Second incomplete residual correction

`dravya.oyster-mushroom` still enters both `mollusc` and `shellfish`. Its
authoritative catalogue name is `Mushrooms, oyster, raw`; the negative phrase
`oyster mushroom` is the reverse token order and therefore cannot veto it.
The added `oyster sauce` and `oyster plant` negatives do not apply to that row.
This also requires a director-artifact correction rather than a matcher
special case.

## G7 viaIngredient fixtures

The result remains **4/13 nominal**, with these nine missing recipe fixtures:

| Pattern | Catalogue state |
|---|---|
| `butter chicken` | Absent |
| `caesar` | Nine plain USDA matches, no recipe fixture |
| `worcestershire` | Two plain USDA matches, no recipe fixture |
| `mayonnaise` | 57 plain USDA matches, no recipe fixture |
| `meringue` | Five plain USDA matches, no recipe fixture |
| `aioli` | Absent |
| `hollandaise` | One plain USDA match, no recipe fixture |
| `marzipan` | Absent |
| `praline` | One plain USDA match, no recipe fixture |

The four nominally represented patterns are `palak paneer`, `raita`, `lassi`,
and `kheer`.

## Contested cases

Contested cases remain non-blocking and are excluded from G5/G6 arithmetic.
Current rev3 outcomes are:

- Must-exclude: `salami` pass, `pepperoni` pass, `caesar` fail,
  `scallop` pass, `vanilla extract` pass.
- Must-not-exclude: `coconut` currently catches 6 of 119 catalogue-name
  matches through other recognized tree-nut paths; `fishcake, vegetarian` and
  `chicken of the woods` remain unresolved.

## Gates not run after the stop

FC1c-G1 through G4 and FC1c-G7 through G11 were not run after the Part A stop.
No Swift source, planner exclusion behavior, resolver behavior, tests, bundled
concept artifact, seed, preseed store, or search index was changed. In
particular:

- FC-2 planner wiring was not started.
- The 30-item `alcoholKeywords` array was not changed.
- The MP-3 resolver was not changed.
- No build-time artifact was regenerated.
- No cold-launch number was recorded.
- No handbook or progress registry was advanced for an incomplete milestone.

The next valid step is a director correction to the rev3 ontology followed by a
fresh FC-1c Part A run. No matcher or runtime workaround is recommended.
