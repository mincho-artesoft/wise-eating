# Job 4 shipped-artifact repin

Tracking issue: [#3](https://github.com/mincho-artesoft/wise-eating/issues/3)

NUT-3 temporarily left source and bundled artifacts describing different
populations. Job 4 regenerated the seed, preseed, food-concept, food-role, and
search-cache artifacts and repinned every guard atomically.

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
| [x] | `build_seed.py:31-36` | Central interim population constants | Removed the interim population and retained `TARGET_FOODS = 14_488`, `TARGET_PROFILES = 2_216`, `TARGET_RECIPES = 1_511`, `TARGET_INGREDIENT_LINKS = 10_644`, `TARGET_INGREDIENT_OWNERS = 1_511`, and `TARGET_AYURVEDA_LINKS = 2_336`. |
| [x] | `build_preseeded_store.py:55-63` | Interim audit envelope | Audits the regenerated bundle with `TARGET_EXPECTED`: 14,488 foods, 2,216 profiles, 1,511 recipes, 10,644 ingredient links, 1,511 owners, and 2,336 AyurvedaLinks. |
| [x] | `validate.py:390-406` | Transitional base/shipped/target store detector | Projected stores must contain 14,488 foods and pass `TARGET_EXPECTED`; the 12,601-food USDA base branch remains. |
| [x] | `validate.py:486-503` | Bundled seed count block | Repinned to 1,511 recipes, 2,216 profiles, 10,644 age contributors, and 2,336 AyurvedaLinks; nutrition coverage matches the regenerated seed. |
| [x] | `validate.py:508-512` | Bundled seed link-array count | Keeps 2,336 AyurvedaLinks without an interim alias. |
| [x] | `validate.py:643-647` | Bundled recipe-nutrition coverage | Repinned full/estimated/none to the regenerated target result for 1,511 recipes. |
| [x] | `tests/test_fc1_concepts.py:302-342` | Concept artifact rebuilt from the bundled seed | Repinned to 10,644 ingredient links, 1,511 owners, 14,488 foods, and a 14,488 membership-ratio denominator. |
| [x] | `tests/test_mp3_resolution.py:551-553` | Resolver catalog read from the bundled preseed | Repinned to 14,488 catalog rows and 14,486 candidates after the two exclusions. |
| [x] | `tests/test_mp7_roles.py:296,463` | Role artifact rebuilt from the bundled seed | Repinned to 14,488 catalog rows and 1,511 recipe rows. |
| [x] | `tests/test_mp7_validity.py:203` | Validity checker reads the bundled role artifact | Repinned to 14,488 role items. |
| [x] | `tests/test_we2_preseed.py:20,34,52-57,136-140` | Bundled preseed audit and no-op reseed snapshot | Audits with `TARGET_EXPECTED`: 14,488 foods, 2,216 profiles, 1,511 recipes, 10,644 ingredient links, 1,511 owners, and 2,336 AyurvedaLinks. |
| [x] | `tests/test_we4_search.py:210,221` | Search cache and canonical profiles read from the bundled preseed | Repinned to 14,488 cached foods and 2,216 direct profiles. |
| [x] | `tests/test_we8_safety.py:240,372-373` | Canonical safety and ingredient rows read from bundled seed/preseed | Repinned to 2,216 profiles, 10,644 ingredient links, and 1,511 owners. |
| [x] | `Ayura/Ayurveda/FoodConcepts.swift:32` | Runtime guard for bundled food-concept artifact | Repinned `catalogCount` to 14,488. |
| [x] | `Ayura/AI/MealPlanning/FoodRoleResolver.swift:66` | Runtime guard for bundled food-role artifact | Repinned `catalogCount` to 14,488. |
| [x] | `Ayura/Main/DBSeed/AyurvedaSeeder.swift:564-578` | Runtime guard for bundled seed | Repinned recipes to 1,511 and age contributors to 10,644; AyurvedaLinks remains 2,336. |
| [x] | `Ayura/FoodSearch/Structs/AyurvedaFacet.swift:90-91` | Runtime guard for bundled seed | Repinned recipes to 1,511; AyurvedaLinks remains 2,336. |

## Completion gates

1. Regenerate each artifact once, after the catalogue and image archive are final.
2. Re-derive the AyurvedaLink decomposition. The current measured source and
   shipped value is 2,336 = 306 exact + 64 near + 1,966 derived; do not copy the
   stale handbook decomposition.
3. Remove the transitional population and its annotations.
4. Run the full Python suite and Debug/Release builds.
5. Confirm the regenerated archive, seed, preseed, concept, role, and search
   cache artifacts all describe the target population.
