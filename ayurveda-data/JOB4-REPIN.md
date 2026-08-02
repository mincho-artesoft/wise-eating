# Job 4 shipped-artifact repin

Tracking issue: [#3](https://github.com/mincho-artesoft/wise-eating/issues/3)

The source and bundled artifacts intentionally describe different populations
between NUT-3 and job 4. Do not update a `SHIPPED_*` assertion before its input
artifact has been regenerated. Job 4 must regenerate the seed, preseed, food
concept, food role, and search-cache artifacts first, then complete every row
below.

Target population after regeneration:

- foods: 14,488
- profiles: 2,216
- recipes: 1,511
- ingredient links: 10,644
- ingredient owners: 1,511
- AyurvedaLinks: 2,336 (unchanged)

## Repin checklist

| Done | Shipped site | Current semantics | Job 4 target |
| --- | --- | --- | --- |
| [ ] | `build_seed.py:31-36` | Central `SHIPPED_*` constants | Remove the interim population and retain `TARGET_FOODS = 14_488`, `TARGET_PROFILES = 2_216`, `TARGET_RECIPES = 1_511`, `TARGET_INGREDIENT_LINKS = 10_644`, `TARGET_INGREDIENT_OWNERS = 1_511`, and `TARGET_AYURVEDA_LINKS = 2_336`. |
| [ ] | `build_preseeded_store.py:55-63` | `SHIPPED_EXPECTED` audit envelope | Delete the shipped override and audit the regenerated bundle with `TARGET_EXPECTED`: 14,488 foods, 2,216 profiles, 1,511 recipes, 10,644 ingredient links, 1,511 owners, and 2,336 AyurvedaLinks. |
| [ ] | `validate.py:390-406` | Transitional base/shipped/target store detector | Remove the shipped branch; projected stores must contain 14,488 foods and pass `TARGET_EXPECTED`. Keep the 12,601-food USDA base branch. |
| [ ] | `validate.py:486-503` | Bundled seed count block | Repin to 1,511 recipes, 2,216 profiles, 10,644 age contributors, and 2,336 AyurvedaLinks; nutrition coverage must match the regenerated seed. |
| [ ] | `validate.py:508-512` | Bundled seed link-array count | Keep 2,336 AyurvedaLinks, but remove the shipped alias. |
| [ ] | `validate.py:643-647` | Bundled recipe-nutrition coverage | Repin full/estimated/none to the regenerated target result for 1,511 recipes. |
| [ ] | `tests/test_fc1_concepts.py:302-342` | Concept artifact rebuilt from the bundled seed | Repin to 10,644 ingredient links, 1,511 owners, 14,488 foods, and use 14,488 as the membership-ratio denominator. |
| [ ] | `tests/test_mp3_resolution.py:551-553` | Resolver catalog read from the bundled preseed | Repin to 14,488 catalog rows and 14,486 candidates after the two exclusions. |
| [ ] | `tests/test_mp7_roles.py:296,463` | Role artifact rebuilt from the bundled seed | Repin to 14,488 catalog rows and 1,511 recipe rows. |
| [ ] | `tests/test_mp7_validity.py:203` | Validity checker reads the bundled role artifact | Repin to 14,488 role items. |
| [ ] | `tests/test_we2_preseed.py:20,34,52-57,136-140` | Bundled preseed audit and no-op reseed snapshot | Audit with `TARGET_EXPECTED`: 14,488 foods, 2,216 profiles, 1,511 recipes, 10,644 ingredient links, 1,511 owners, and 2,336 AyurvedaLinks. |
| [ ] | `tests/test_we4_search.py:210,221` | Search cache and canonical profiles read from the bundled preseed | Repin to 14,488 cached foods and 2,216 direct profiles. |
| [ ] | `tests/test_we8_safety.py:240,372-373` | Canonical safety and ingredient rows read from bundled seed/preseed | Repin to 2,216 profiles, 10,644 ingredient links, and 1,511 owners. |
| [ ] | `Ayura/Ayurveda/FoodConcepts.swift:32` | Runtime guard for bundled food-concept artifact | Repin `catalogCount` to 14,488. |
| [ ] | `Ayura/AI/MealPlanning/FoodRoleResolver.swift:66` | Runtime guard for bundled food-role artifact | Repin `catalogCount` to 14,488. |
| [ ] | `Ayura/Main/DBSeed/AyurvedaSeeder.swift:564-578` | Runtime guard for bundled seed | Repin recipes to 1,511 and age contributors to 10,644; keep AyurvedaLinks at 2,336. |
| [ ] | `Ayura/FoodSearch/Structs/AyurvedaFacet.swift:90-91` | Runtime guard for bundled seed | Repin recipes to 1,511; keep AyurvedaLinks at 2,336. |

## Completion gates

1. Regenerate each artifact once, after the catalogue and image archive are final.
2. Re-derive the AyurvedaLink decomposition. The current measured source and
   shipped value is 2,336 = 306 exact + 64 near + 1,966 derived; do not copy the
   stale handbook decomposition.
3. Remove the transitional `SHIPPED_*` population and its annotations.
4. Run the full Python suite and Debug/Release builds.
5. Confirm the regenerated archive, seed, preseed, concept, role, and search
   cache artifacts all describe the target population.
