# Founder Decision Record — `main` Age Gating

Date: 2026-07-26
Audited branch/tip: `main` at `9a5429d`
Status: **OPEN PRODUCT ISSUE — audit only; no `main` change made**

## Finding

The shipping `main` application hard-hides plain USDA foods whose imported
`minAgeMonths` exceeds the active profile or parsed target age. This behavior
predates the Ayurveda work and is independent of the WE-8c provenance split.

| Profile age | Visible plain USDA | Hidden plain USDA |
|---:|---:|---:|
| 9 months | **4,353** | 8,248 |
| 24 months | **11,807** | 794 |
| 60 months | **12,243** | 358 |

At 9 months, 8,248 of 12,601 rows (65.5%) are therefore absent from matching
search results.

## Imported-age histogram

The source is the shipping `WiseEating/Legacy/foods.json` at `main`. It
contains exactly 12,601 rows.

| `minAgeMonths` | USDA rows |
|---:|---:|
| 0 | 25 |
| 4 | 103 |
| 6 | 1,559 |
| 8 | 1,946 |
| 9 | 720 |
| 10 | 64 |
| 12 | 819 |
| 18 | 133 |
| 24 | 6,438 |
| 48 | 408 |
| 60 | 28 |
| 192 | 180 |
| 252 | 178 |
| **Total** | **12,601** |

## Exact shipping code path

1. `WiseEating/Main/DBSeed/SeedManager.swift:100–120` loads
   `Legacy/foods.json`, decodes `[FoodItemDTO]`, and calls `dto.model(...)`.
2. `WiseEating/Food/Structs/FoodItemDTO.swift:73` decodes the optional source
   value; line 201 assigns `item.minAgeMonths = minAgeMonths ?? 0` unchanged.
3. `WiseEating/FoodSearch/SearchIndexStore.swift:403` copies that value into
   every `CompactFoodItem`.
4. `WiseEating/FoodSearch/VM/SmartFoodSearch 3.swift:834` compares the compact
   value with `profileConstraints.ageInMonths`; line 925 compares it with
   `intent.targetConsumerAge`. Both branches execute `continue`, so the row is
   hidden rather than badged or downranked.

The shipping model has no age-provenance field and this path performs no
authority check.

## Does `main` carry an authored honey floor?

**No — `main` contains no auditable authored age floor, including no authored
12-month honey rule.**

Evidence:

- a source search at `main` finds no infant-botulism rule or citation and no
  honey-specific age assignment in Swift;
- `FoodItemDTO.model(...)` copies the JSON number unchanged, with no rule layer;
- among 36 source names containing the standalone word “honey,” the imported
  values are `6: 1`, `12: 25`, `24: 1`, and `48: 9`;
- the plain row `Honey` (ID 7075) happens to carry 12 months, while
  `Honey (especially Leatherwood)` (ID 12117) carries 6 months. Neither row has
  provenance or a citation.

Accordingly, the shipping app enforces the untraced imported fill values while
lacking the only age rule in this project with a cited clinical basis: the
authored 12-month honey/infant-botulism floor introduced on
`ayurveda-app`.

## Decision boundary

This file records the issue for founder review only. WE-8c did not edit
`main`, branch from `main`, change USDA enforcement, or propose a silent
baseline update.
