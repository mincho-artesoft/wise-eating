# TASK R1 Final Report

## Batches completed

| Batch | Theme | Recipes | Commit |
|---|---|---:|---|
| r01 | Kitchari, gruel, and yusha | 50 | `9e0dd74` |
| r02 | Classical dals, rasams, sambars, and soups | 50 | `6156ce7` |
| r03 | Vegetable sabzis, poriyals, thorans, and kootus | 50 | `0684212` |
| r04 | Breakfasts and grains | 50 | `be9a49b` |
| r05 | Sweets, food tonics, and avaleha-style preserves | 50 | `ef6f108` |
| r06 | Drinks and condiments | 50 | `a4beb3e` |

Total: **300 classical recipes**. Every batch has `qualityState: "aiDraft"`, and every recipe has an empty `viruddhaFlags` array.

## Validation output

Each batch was validated against the prescribed `/tmp/pre` store before its commit.

### r01

```text
Checked 210 dravyas, 50 recipes
All checks passed.
```

### r02

```text
Checked 210 dravyas, 100 recipes
All checks passed.
```

### r03

```text
Checked 210 dravyas, 150 recipes
All checks passed.
```

### r04

```text
Checked 210 dravyas, 200 recipes
All checks passed.
```

### r05

```text
Checked 210 dravyas, 250 recipes
All checks passed.
```

### r06

```text
Checked 210 dravyas, 300 recipes
All checks passed.
```

## Dravya-link percentages

Percentages are aggregate ingredient-level dravya links. Verified FDC-linked ingredients, principally water and a few exact store-only ingredients, are included in the denominator but not the dravya-linked numerator.

| Batch | Dravya-linked ingredients | Total ingredients | Percentage |
|---|---:|---:|---:|
| r01 | 373 | 423 | 88.18% |
| r02 | 448 | 498 | 89.96% |
| r03 | 379 | 430 | 88.14% |
| r04 | 320 | 370 | 86.49% |
| r05 | 275 | 290 | 94.83% |
| r06 | 217 | 256 | 84.77% |

Every individual recipe meets the validator's minimum 50% dravya-link threshold.

## Canon-12 coverage

Covered **122 of 133** canonical recipe IDs. The following 11 names were not covered:

- `recipe.horse-gram-soup` — horse gram/kulthi has no exact dravya or verified store binding.
- `recipe.parwal-sabzi` — pointed gourd/parwal has no exact dravya or verified store binding.
- `recipe.tinda-sabzi` — tinda/apple gourd has no exact dravya or verified store binding.
- `recipe.amla-chutney` — amla/Indian gooseberry has no exact dravya or verified store binding; a generic gooseberry item was not treated as equivalent.
- `recipe.sol-kadhi` — kokum has no exact dravya or verified store binding.
- `recipe.khajur-smoothie` — the canonical date-banana-milk combination would introduce the fruit-and-dairy incompatibility called out in the canon; r01-r06 were required to contain zero viruddha content.
- `recipe.amla-ginger-shot` — amla/Indian gooseberry has no exact dravya or verified store binding.
- `recipe.gond-ladoo` — edible acacia gum/gond has no exact dravya or verified store binding.
- `recipe.samak-rice-fasting` — barnyard millet/samak has no exact dravya or verified store binding.
- `recipe.singhara-pakora-fasting` — water-chestnut flour/singhara atta has no exact dravya or verified store binding.
- `recipe.ugadi-pachadi` — neem flower has no exact dravya or verified store binding.

No substitute ingredient was relabeled as any of these missing foods.

## Review notes added

- `recipe.avial` — vegetable combinations and yogurt versus raw mango vary by Kerala lineage; this version uses yogurt and verified linked vegetables.
- `recipe.kootu` — local gourd choices vary; ridge gourd is used because the canon's snake-gourd key lacks an exact binding.
- `recipe.undhiyu-light` — regional combinations vary; this light version omits fried dumplings and uses linked green beans in place of unavailable broad beans.
- `recipe.rava-idli` — leavening methods vary; the recipe uses a rested yogurt batter without an unlinked modern raising agent.
- `recipe.poha-lemon` — flattened rice is linked to its parent white-rice dravya because no standalone poha binding is available.
- `recipe.bagara-khichdi-bajra` — small-millet choices vary; the recipe uses exactly linked proso millet.
- `recipe.baked-vegetable-cutlet` — flattened rice is linked to its parent white-rice dravya because no standalone poha binding is available.
- `recipe.coconut-ladoo` — the recipe uses jaggery and ghee rather than modern condensed milk.
- `recipe.panchamrit-classic` — ritual proportions vary; honey and ghee are deliberately unequal by weight, and the serving is ceremonial and small.
- `recipe.licorice-tea` — individual suitability varies; the entry avoids medicinal dosing and treatment guidance.
- `recipe.boondi-raita-light` — traditional boondi is deep-fried; this version pan-cooks tiny batter drops in measured ghee.
