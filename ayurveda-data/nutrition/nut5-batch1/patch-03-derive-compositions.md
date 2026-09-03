# Patch 03 — compute dravya panels from authored compositions

Reuses machinery that already exists. Do not write a second nutrition calculator.

## Input

`ayurveda-data/nutrition/compositions.json` — 34 authored entries, each giving `yieldG`,
optional `waterG`, and an `ingredients` list of `{dravyaId, grams}`. Every referenced
ingredient was verified to resolve against the current catalogue: **0 unresolvable slugs**.

## How

`build_seed.py` already has `derive_recipe_nutrition`, which takes ingredient grams, sums
panels from `nutrition_by_id`, and returns `per100g` plus a `status` of `full` / `estimated`
/ `none`. A composition is the same computation with two differences: the divisor is the
authored `yieldG` rather than the summed ingredient weight, and water contributes mass but
no nutrients.

Add `derive_dravya_composition`, which:

1. resolves each ingredient's panel through the same `preferred_bindings` path
   `derive_recipe_nutrition` uses;
2. **returns `None` if any ingredient panel is missing.** Partial is not allowed. A dish
   computed from half its ingredients understates every nutrient while looking
   authoritative — that is worse than a blank row, which at least tells the truth;
3. divides totals by `yieldG`, not by the ingredient sum. `waterG` is documentation of where
   the mass went; it is never a divisor term of its own;
4. returns the same shape `dravya_nutrition_payload` emits in patch 01, with
   `status: "derived"`.

Feed the result into the same `output["nutrition"]` slot patch 01 adds, so a composed dravya
and a measured one reach the app by one path.

Order matters: a measured panel from `dravya_foods.json` wins over a derived one. If a row
somehow has both, take the measurement and log the collision.

## Provenance

Every derived row must carry, in `dravya_foods.json` `_review`:

- `status`: `derived — computed from <ingredient ids>`
- `source`: the composition's `basis` string, verbatim
- any `note` from the composition entry, verbatim

The notes are not decoration. Several record real approximations that a reviewer must be
able to find and challenge: shrikhand models a whey separation as a mixture, sattu-drink uses
raw chana dal for roasted sattu, kadhi uses chana dal for besan, masala-chai counts milk and
sugar but not the strained spices. Losing those notes would turn stated approximations into
apparently measured values.

## What must NOT be derived

`compositions.json` `_meta.excluded_deliberately` names four groups, and the reasoning
matters more than the list:

- **Strained infusions** — jeera water, ajwain water, saunf water, dhania water, methi
  water, CCF tea, barley water, tulsi tea, lemongrass tea, herbal kadha, khus sherbet. The
  solids are strained out and the extraction fraction is not published. Computing from whole
  seed weight would overstate every nutrient by roughly an order of magnitude and would look
  entirely plausible doing it.
- **Plain water** — warm-water, copper-water. Mark not-applicable. Do not write zeros.
- **Transformative ferments** — gundruk, sinki, kinema, hawaijar, khalpi, black carrot kanji,
  neera.
- **Unmeasurable losses** — besan pakora, medu vada, urad papad (oil uptake unknown), mango
  pickle (long cure with brine exchange).

If a future packet wants any of these, it needs a measured extraction or uptake figure, not
a better guess.

## Gate

- Print each derived row with its ingredient count and resulting nutrient count.
- Assert every composition either produced a full panel or produced nothing — no partial rows.
- Assert no row that previously held `null` now holds `0`.
- Assert the 34 compositions resolve to 34 dravyas that exist and are placeholders.
- Print the `_review.status` histogram before and after.
