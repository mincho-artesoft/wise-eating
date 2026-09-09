# NUT-5 batch 1 — authored data and pipeline patches

Prepared 2026-08-04 against `12e7b79`. **No build was run** — there is no Xcode in the
environment this was authored in. Everything here is data and specification; Codex applies
and builds.

## The finding that reframes this work

`Aam panna` showing no nutrition led to a check of the shipped preseed, which showed all
375 placeholder foods carrying `NULL` nutrient blobs — **including the 73 that already have
measured values in `dravya_foods.json`**. `dravya.agathi-leaf` has a 33-nutrient panel in the
source file; food 900005 in the shipped store has NULL macronutrients, vitamins and minerals.

The chain breaks at emission. `build_seed.py` loads and validates the panels and merges them
into `nutrition_by_id`, but the dravya entries it writes into the seed carry no `nutrition`
field at all, and `AyurvedaSeeder` only ever handles recipe nutrition. There is no path from
a measured panel to a placeholder food.

So the gap was never purely a sourcing problem. **73 rows are already sourced and one
pipeline step from the app.** Patches 01 and 02 are that step, and they should land first —
they cost no new data and they prove the path before any sourcing effort is spent.

Verify the defect first:

```
cat Ayura/preseeded_db.store.gz.part-a? > /tmp/ps.gz && gunzip -f /tmp/ps.gz
sqlite3 /tmp/ps "SELECT ZID,ZNAME,ZMACRONUTRIENTS IS NULL FROM ZFOODITEM WHERE ZID=900005"
```

Expect `900005|Agathi leaf|1`. The `1` is the bug.

## Contents

| file | what it is |
|---|---|
| `patch-01-build_seed-emit.diff` | emit a `nutrition` payload on placeholder dravyas |
| `patch-02-AyurvedaSeeder-write.md` | write that payload onto the placeholder `FoodItem` |
| `patch-03-derive-compositions.md` | compute panels from authored compositions, reusing `derive_recipe_nutrition` |
| `compositions.json` | 34 authored preparations — ingredient grams, yield, basis, caveats |
| `ifct-matches-reviewed.json` | 17 accepted IFCT matches, 34 explicit rejections with reasons |

## Impact

| | rows |
|---|---|
| unsourced before | 267 |
| closed by this batch | 51 (17 matched + 34 derived, no overlap) |
| unsourced after | 216 |
| **already sourced but invisible, unlocked by patches 01–02** | **73** |

Every referenced ingredient slug was checked against the catalogue: **0 unresolvable**. No
target already holds values, so nothing collides.

## How the matching was done, and why it is conservative

Fuzzy scoring generated candidates only. In this run it scored `Bathua` at 0.90 against
`Milk, whole, Cow` and `Ambarella` at 0.77 against `Potato` — the same failure that got
`REJECTED_usda_analogue_matcher.py` retired for scoring calcium hydroxide at 1.00 against a
lime. Every accepted match was then confirmed by scientific name and plant organ by hand.

The rule applied: **accept only when species and organ agree.** A different species, a
different plant part, or a processed form of a raw row is a rejection. That is why there are
34 rejections against 17 accepts, and why the rejection list carries its reasoning — so a
future pass does not rediscover and re-reject the same candidates.

Three accepts carry notes because they are approximations within a species rather than exact
identities: `long-brinjal` uses IFCT's published all-varieties aggregate, `snake-gourd` uses
the common long pale green cultivar, `pomegranate-sweet` uses the single pomegranate row.
`pomegranate-sour` deliberately does **not** take that row — sourness is the defining
difference and no sour row exists.

## What was deliberately not derived

`compositions.json` `_meta.excluded_deliberately` lists four groups. The largest is the
strained infusions — jeera water, ajwain water, CCF tea and the rest. Their solids are
strained out and the extraction fraction into the water is not published. Deriving them from
whole seed weight would overstate every nutrient by roughly an order of magnitude and would
look completely plausible. They stay null.

Plain water rows are marked not-applicable rather than zeroed. Transformative ferments and
deep-fried items are excluded because the compositional change and the oil uptake are not
measured.

## Approximations that must survive into `_review`

Several compositions are honest approximations and say so. If the notes are dropped, stated
approximations become apparently measured values:

- `shrikhand` models a whey separation as a mixture, carried by the yield figure
- `sattu-drink` uses raw chana dal where sattu is roasted — understates by roughly 8–10%
- `kadhi` uses chana dal for besan, a milling difference
- `masala-chai` counts milk and sugar but not the strained spices
- `rice-gruel` encodes peya specifically; manda and vilepi are different consistencies
- `pakhala` and `ambali` are fermented, and fermentation is not modelled

## Order of application

1. Patches 01 and 02, then build. Gate: `nutritionAppliedFoods` = 73, and `900005` comes out
   with 33 nutrients and non-NULL blobs.
2. `ifct-matches-reviewed.json` through `apply_ifct_values.py`. Gate: 17 rows change status
   to measured, no value becomes zero.
3. Patch 03 with `compositions.json`. Gate: 34 rows derive fully or not at all — no partials.
4. Full cascade, suite, both builds.

## What remains after this

216 unsourced rows. The realistic split is roughly 33 medicinal (mostly `not-applicable` now
that they are tiered out), about 48 more preparations and beverages that could be composed
the same way as this batch, and the remainder needing sources that may not exist in
published form. Batch 2 should take the remaining compositions first — it is the same method
and needs no new source.
