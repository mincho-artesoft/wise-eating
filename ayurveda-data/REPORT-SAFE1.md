# SAFE1 report — exclude what is not eatable

Date: 2026-08-03
Baseline: `bbf30cb` on `ayurveda-app`

## Gate 1 — exclusion decisions

| id | category | former authored serving | decision | reason |
|---|---|---|---|---|
| `dravya.camphor-edible` | spice | 1 pinch / 0.1 g | `edible: false` | neurotoxic — paediatric lethal dose is a few times the culinary pinch |
| `dravya.alkanet-root` | spice | 1 tsp / 2 g | `edible: false` | dye, not an ingredient — pyrrolizidine alkaloids, not swallowed |
| `dravya.edible-lime` | salt-mineral | 1 grain-sized trace / 0.1 g | `edible: false` | caustic alkali — a reagent, not a food |
| `dravya.castor-oil` | oil-fat | 1 tsp / 4.5 g | `edible: false` | stimulant laxative — a drug dose, not a cooking oil |
| `dravya.shilajit` | medicinal | 1 tsp / 3 g | `edible: false` | supplement taken by dose — contamination risk, not a food |
| `dravya.kaunch-beej` | medicinal | 1 tsp / 3 g | `edible: false` | pharmacologically active L-DOPA seed — requires processing and dosing, not a food |

Shilajit is a dose-form supplement rather than a portioned food, and its own
contraindication rejects raw/unpurified material. Kaunch beej is likewise taken
by dose after processing, and its L-DOPA content has pharmacological interactions.
Both therefore satisfy the packet's narrow rule. Total `edible: false`: **6**.

## Gates 2 and 3 — reachability and age

All six excluded IDs have **zero recipe references**. The seed writes no
portion for an inedible profile, every food/search/browse/suggestion path rejects
`isEdible == false`, and the Ayurveda display suppresses its dosha panel.

The fresh v9 search cache proves the age invariant on both representations:

- database `isEdible == false`: six food IDs;
- compact `isEdible == false`: the same six IDs;
- compact enforced age nil/omitted: the same six IDs;
- Ayurveda metadata enforced age nil/omitted: the same six IDs;
- every edible row carrying Ayurveda metadata has a non-nil enforced age.

The six database IDs are `900007`, `900054`, `900056`, `900098`, `900172`
and `900306`. `CompactFoodItem.enforcedMinAgeMonths` is now optional. The
persisted search-cache format changed from a required integer to an optional
integer, so the cache was deliberately bumped from v8 to **v9**; otherwise an
old payload could retain the fail-open 0/6-month values.

The honey dravyas both remain at display/enforced **12/12** months. Their five
recipes remain:

| recipe | display minimum | enforced minimum |
|---|---:|---:|
| `recipe.amla-ginger-shot` | 24 | 12 |
| `recipe.drink-ginger-oat-warmer` | 24 | 12 |
| `recipe.ginger-lemon-honey-tea` | 24 | 12 |
| `recipe.panchamrit-classic` | 12 | 12 |
| `recipe.vasanta-kapha-clearer` | 24 | 12 |

## Honey row correction

The completed preseed has 40 food names containing `honey`. The table below is
the full before/after comparison requested by the director. Blank provenance
means no provenance value.

| id | name | before age | before provenance | after age | after provenance |
|---:|---|---:|---|---:|---|
| 2000 | Almonds, honey roasted | 48 | | 48 | |
| 2007 | Cashews, honey roasted | 48 | | 48 | |
| 2020 | Mixed nuts, honey roasted | 48 | | 48 | |
| 2029 | Peanuts, honey roasted | 48 | | 48 | |
| 2034 | Pecans, honey roasted | 48 | | 48 | |
| 2040 | Walnuts, excluding honey roasted | 48 | | 48 | |
| 2041 | Walnuts, honey roasted | 48 | | 48 | |
| 2522 | Sopaipilla, without syrup or honey | 12 | | 12 | |
| 2523 | Sopaipilla with syrup or honey | 12 | | 12 | |
| 2851 | Rice, sweet, cooked with honey | 12 | | 12 | |
| 2893 | Cereal, O's, honey nut | 12 | | 12 | |
| 2915 | Cereal, other, honey | 12 | | 12 | |
| 3667 | Honeydew melon, raw | 6 | | 6 | |
| 4477 | Honey mustard dip | 12 | | 12 | |
| 4569 | Honey butter | 12 | | 12 | |
| 4592 | Honey mustard dressing | 12 | | 12 | |
| 4613 | Honey mustard dressing, light | 12 | | 12 | |
| 4623 | Honey mustard dressing, fat free | 12 | | 12 | |
| 5175 | Candies, honey-combed, with peanut butter | 48 | | 48 | |
| 5518 | Cinnamon buns, frosted (includes honey buns) | 24 | | 24 | |
| 6122 | Nuts, almonds, honey roasted, unblanched | 48 | | 48 | |
| 7075 | Honey | 12 | authored | 12 | authored |
| 7298 | Melons, honeydew, raw | 24 | | 24 | |
| 8193 | Babyfood, cereal, oatmeal, with honey, dry | 12 | | 12 | |
| 8246 | Salad dressing, honey mustard dressing, reduced calorie | 12 | | 12 | |
| 8253 | Salad dressing, honey mustard, regular | 12 | | 12 | |
| 8256 | Dressing, honey mustard, fat-free | 12 | | 12 | |
| 9003 | Beverages, tea, green, ready to drink, ginseng and honey, sweetened | 12 | | 12 | |
| 9332 | Babyfood, cereal, oatmeal, with honey, prepared with whole milk | 12 | | 12 | |
| 9334 | Babyfood, cereal, rice, with honey, prepared with whole milk | 12 | | 12 | |
| 9760 | Doughnuts, yeast-leavened, glazed, enriched (includes honey buns) | 12 | | 12 | |
| 9940 | Honey roll sausage, beef | 12 | | 12 | |
| 10359 | Babyfood, cereal, mixed, with honey, prepared with whole milk | 12 | | 12 | |
| 10814 | Cookies, graham crackers, plain or honey, lowfat | 12 | | 12 | |
| 11303 | Ham, honey, smoked, cooked | 12 | | 12 | |
| 11571 | Cookies, graham crackers, plain or honey (includes cinnamon) | 12 | | 12 | |
| 11676 | Doughnuts, yeast-leavened, glazed, unenriched (includes honey buns) | 12 | | 12 | |
| 12117 | Honey (especially Leatherwood) | **6** | | **12** | **authored** |
| 900147 | Aged honey | 12 | authored | 12 | authored |
| 1000645 | Ginger-Lemon-Honey Tea | 24 | authored | 24 | authored |

Exactly ID `12117` changed. It carries the same NHS/WHO source string as ID
`7075`. IDs `3667`, `7298`, `2040`, `2522`, `5518`, `9760` and `11676` were
asserted unchanged.

Open data items, recorded but not changed here:

1. ID `12117` remains unbound to `dravya.honey` in the crosswalk. Binding it
   would change the contested-count gate and needs its own reviewed packet.
2. IDs `3667` and `7298` are duplicate honeydew-melon rows with ages 6 and 24.
   This is a data-consistency discrepancy, not a honey safety issue.

## Gate 4 — shipped artifact and regression results

| measure | result |
|---|---:|
| dravyas | 706 |
| recipes | 1,511 |
| foods | 14,489 |
| profiles | 2,217 |
| Ayurveda links | 2,336 |
| ingredient links / owners | 10,644 / 1,511 |
| placeholders | 377 |
| `edible: false` | 6 |
| `engineExcluded` | 8 |
| cache foods / version | 14,489 / 9 |

Two independent builds were byte-identical:

- `ayurveda_seed.json.gz`: `3d32007982a40cc19031c352f6e5c289cbc680ba899258188e34b725bad0e258`
- `ayurveda_rules.json`: `e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c`
- `food_concepts.json.gz`: `da2f5b46e6a1b3627e4f27256da1e075094710865cc5aa5bb502a778ad58241c`
- `food_roles.json.gz`: `fb4907085f2b3dc29450fed326b7c983ac40547ebfa84864cc46f29b93c1ba8a`

`validate.py --store /tmp/safe1-pre/default.store` passed. Debug and Release
simulator builds passed, each with required assets 8/8. The final repository
suite passed **175/175** in 292.394 seconds.

The only tracked file over 80 MB is
`Ayura/Food/food_archive_480.mp4` at **85,633,724 bytes**. No tracked file is
90 MB or larger.
