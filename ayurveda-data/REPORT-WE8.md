# REPORT WE-8 — Derived Safety & Search Metadata

Date: 2026-07-25
Branch: `ayurveda-app`
Audit tip: `2de3b22fd694bb6b8ad89ce0d5007388d649ca4e`
Phase-A commit: `52a0d4c`
Derivation/artifact commit: `a02cece`
Status: **COMPLETE — 53/53 tests, 25/25 production legacy goldens plus two
safety goldens, deterministic artifacts, and all local gates green.**

Phase A was written and committed before any seed, seeder, artifact, or test
behavior changed. Phase C originally stopped on the changed `vegan curry`
result. The founder then ruled that change correct, selected decision candidate
2, and authorized the auditable baseline update recorded below.

## Phase A — pre-change coverage audit

### Method and immutable baseline

The two shipped `preseeded_db.store.gz.part-*` files were concatenated and
decompressed to a temporary SQLite store. The audit joined the 2,214 canonical
`ZAYURVEDAPROFILE.ZFOODID` values to `ZFOODITEM`, decoded the persisted
version-4 `ZSEARCHINDEXCACHE` payload, and compared every recipe's seed
ingredient multiset with `ZINGREDIENTLINK`.

| Artifact | Pre-change SHA-256 |
|---|---|
| `WiseEating/ayurveda_seed.json.gz` | `1830a19134b7aabb044023140dea319424789cc7cfdfdde331230e357ef509b6` |
| preseed part `aa` | `4e18d019b9ef2e94f1492216f445fa21b87317c5a1e53b79e60f8c005227fe57` |
| preseed part `ab` | `72d19e2f6fb86c51297a6cd65a0bc75eb3fe55113f69249934dfaadc986c13ab` |

### Search-consumed field inventory

`SearchKnowledgeBase` classifies query vocabulary; it does not read
`FoodItem` directly. `SearchIndexStore` projects the following `FoodItem`
values into `CompactFoodItem`, and `SmartFoodSearch3` consumes them:

| `CompactFoodItem` field | `FoodItem` source | Search use |
|---|---|---|
| `id` | `id` | explicit excluded-ID filter, result identity, index joins |
| `name` / lowercased and padded helpers | `name` | literal/name matching and tie-breaking |
| `searchTokens` | `searchTokens`, `searchTokens2`, or name fallback | positive/negative text filtering and scoring |
| `minAgeMonths` | `minAgeMonths` | persona, explicit-age, and profile-age filters |
| `diets` | `diets[].name` | required, included, excluded, and UI diet filters |
| `allergens` | `allergens[].name` | profile avoidance, named allergen exclusion, and exclude-all |
| `ph` | direct `other.alkalinityPH`, or recipe aggregate | pH filtering, unknown exclusion count, and pH sorting |
| `referenceWeightG` | `referenceWeightG` | converts stored nutrient totals to per-100 g comparisons |
| `isRecipe` | `isRecipe` | recipe-only and search-mode filters |
| `isMenu` | `isMenu` | menu-only and search-mode filters |
| `isFavorite` | `isFavorite` | favorites-only filter |
| `nutrientValues` | `calculatedValue(for:)` | nutrient filtering, sorting, ranking, and display context |
| `ayurvedaFacets` | direct canonical profile projection | WE-4 virya/dosha/agni/digestibility/season/category constraints |

This audit treats `id`, name/tokens, nutrients, and Ayurveda facets as
identity/search inputs. The medical-adjacent safety inputs are
`minAgeMonths`, `diets`, and `allergens`; the structural filter inputs are the
three booleans and pH.

### Coverage matrix: 2,214 canonical rows before WE-8

“Populated” for collections means nonempty. For numeric values it means
nonzero. Boolean rows show the true count; false is the expected default unless
noted. A serialized empty Swift array can occupy a non-null SQLite blob, so the
persisted compact value—not blob nullability—is authoritative.

| Field | Dravya populated / default (714) | Recipe populated / default (1,500) | Total populated / default |
|---|---:|---:|---:|
| `id` | 714 / 0 | 1,500 / 0 | 2,214 / 0 |
| `name` | 714 / 0 | 1,500 / 0 | 2,214 / 0 |
| `searchTokens` | 714 / 0 | 1,500 / 0 | 2,214 / 0 |
| `minAgeMonths > 0` | 331 / 383 | **0 / 1,500** | 331 / 1,883 |
| nonempty `diets` | 330 / 384 | **0 / 1,500** | 330 / 1,884 |
| nonempty `allergens` | 80 / 634 | **0 / 1,500** | 80 / 2,134 |
| `ph != 0` | 331 / 383 | 1,500 / 0 | 1,831 / 383 |
| `referenceWeightG > 0` | 714 / 0 | 1,500 / 0 | 2,214 / 0 |
| `isRecipe == true` | 0 / 714 | 1,500 / 0 | 1,500 / 714 |
| `isMenu == true` | 0 / 714 | 0 / 1,500 | 0 / 2,214 |
| `isFavorite == true` | 0 / 714 | 0 / 1,500 | 0 / 2,214 |
| nonempty `nutrientValues` | 331 / 383 | 1,500 / 0 | 1,831 / 383 |
| nonempty `ayurvedaFacets` | 714 / 0 | 1,500 / 0 | 2,214 / 0 |

The 331 non-placeholder dravyas inherit USDA-row metadata. The 383 placeholder
dravyas have default safety and nutrition fields. All 1,500 recipes have
component nutrition and aggregate pH, but every recipe has empty diets,
empty allergens, and age zero. This is the safety-derivation gap.

### IngredientLink parity

**Gap #1 is refuted for the current artifact.** `build_seed.py` already emits
resolved `foodId` and grams for each recipe ingredient, and the completed
build-time artifact contains the exact runtime-seeder projection.

| Check | Pre-change result |
|---|---:|
| Seed recipes | 1,500 |
| Seed ingredient rows | 10,571 |
| Artifact `ZINGREDIENTLINK` rows | 10,571 |
| Distinct recipe owners | 1,500 |
| Owners with no links | 0 |
| Mismatched `(ingredient foodId, grams)` multisets | 0 |
| Non-positive gram rows | 0 |

Classic Mung Kitchari spot-check:

| Ingredient FoodItem | Grams |
|---:|---:|
| 6,372 white basmati rice | 180 |
| 10,962 split yellow mung dal | 180 |
| 4,558 ghee | 24 |
| 8,148 cumin | 4 |
| 9,277 turmeric | 2 |
| 6,687 ginger | 7 |
| 11,888 rock salt | 5 |
| 10,444 water | 1,450 |

The Phase B work therefore preserves and hard-gates this already-correct
projection rather than introducing a second IngredientLink path.

### Empty-allergen sharp edge

The storage/filter sharp edge is **confirmed**, with one natural-language
qualification:

- `SmartFoodSearchEngine.swift` accepts an item for
  `excludeAllAllergens` exactly when `item.allergens.isEmpty`. Therefore every
  seeded recipe currently passes “no allergens,” including dairy recipes.
- Named allergen exclusion rejects only when `item.contains(allergen:)` finds a
  stored tag. An empty set therefore also passes the `.milk` exclusion branch.
- The exact phrase **“no dairy”** is phrase-protected and classified as the
  positive `Dairy-Free` diet by the existing tokenizer. Because seeded recipes
  also have empty diets, they currently fail that particular diet filter by
  accident. The equivalent named-allergen path (“without dairy”) exposes the
  empty-allergen bug. This distinction is preserved rather than misreporting
  parser behavior.

Concrete example: `recipe.amaranth-kheer` contains 1,200 g whole cow milk and
8 g ghee (plus pistachio), but its compact row has `allergens: []` and
`diets: []`. Before WE-8 it:

| Filter | Pre-change outcome | Why |
|---|---|---|
| exclude all allergens | **incorrectly included** | empty allergen set |
| exclude milk / “without dairy” | **incorrectly included** | no stored `Milk` tag |
| “no dairy” (`Dairy-Free`) | excluded | empty diets fail the positive diet requirement |

This is a metadata defect, not a request to change parser or filter semantics.

## Phase B — candidate build-time derivation

Status: **implemented and committed in `a02cece`.**

The candidate bumps the Ayurveda seed to version 4 and gives every canonical
row a reviewable `safety` block:

```text
provenance: scaffold-default
reviewRequired: true
rules: [the exact derivation rules that fired]
reviewFlags: []
```

No content claim, lifecycle value, or medical language is changed. Runtime
projection is limited to the 2,214 canonical food IDs; the cache still gives
Ayurveda facets only to those IDs.

### Conservative derivation rules

| Field | Dravya rule | Recipe rule | Safety boundary |
|---|---|---|---|
| allergens | Union existing USDA tags with exact reviewed category/slug rules | Union all ingredient allergen sets | No substring inference; ghee is `Milk`; misleading names such as buckwheat, water chestnut, butternut, eggplant, and oyster mushroom cannot trigger |
| composition diets | Animal/dairy/honey and allergen facts determine Vegan, Vegetarian, Pescatarian, Dairy-/Lactose-/Egg-/Gluten-/Nut-/Soy-Free | Intersection of ingredient composition diets | A recipe receives a diet only when every ingredient carries it |
| non-composition diets | Preserve existing USDA flags only | Not invented | No inference for keto, halal, kosher, low-fat, low-sodium, etc. |
| `minAgeMonths` | Preserve existing value; honey floor is 12 months | Maximum ingredient age; honey floor is 12 months | Existing stricter ages win |
| provenance | `scaffold-default`, mandatory review | same | All 2,214 rows are explicitly review-required |

The exact allergen rules cover the app's existing enum vocabulary needed by
the reviewed map: dairy, gluten cereals, tree nuts, peanut, sesame, eggs, fish,
crustaceans, soy, mustard, and celery. Existing USDA sulphite tags are
preserved. No mollusc was guessed from `oyster-mushroom`.

### Candidate post-derivation coverage

| Field | Dravya populated / default (714) | Recipe populated / default (1,500) | Total populated / default |
|---|---:|---:|---:|
| `minAgeMonths > 0` | 334 / 380 | 1,500 / 0 | 1,834 / 380 |
| nonempty `diets` | 714 / 0 | 1,500 / 0 | 2,214 / 0 |
| nonempty `allergens` | 156 / 558 | 1,182 / 318 | 1,338 / 876 |
| `ph != 0` | 331 / 383 | 1,500 / 0 | 1,831 / 383 |
| nonempty `nutrientValues` | 331 / 383 | 1,500 / 0 | 1,831 / 383 |
| nonempty `ayurvedaFacets` | 714 / 0 | 1,500 / 0 | 2,214 / 0 |

All unchanged identity, token, reference-weight, and structural boolean rows
remain as shown in the Phase A matrix.

Recipe composition results include 749 Vegan, 1,500 Vegetarian, 751
Dairy-Free, 1,225 Gluten-Free, 1,203 Nut-Free, 1,500 Egg-Free, and 1,419
Soy-Free recipes. Four honey dravyas and four honey recipes meet the
12-month floor. Higher existing ingredient ages remain higher.

### Founder-requested metadata audits

These are report-only analyses of the committed derivation. No flag or
intersection rule was changed in response.

#### Coconut contribution to nut flags

The 297-recipe denominator is the conservative Nut-Free exclusion population:
recipes carrying `Peanuts`, `Nuts`, or a `Nuts (…)` tag. Of those, **94 recipes
carry a nut-family tag only because of coconut-family ingredients**. In other
words, every nut-bearing ingredient in those 94 contributes
`Nuts (coconut)` (sometimes alongside the inherited generic `Nuts` tag), and
there is no peanut, almond, cashew, walnut, or other nut-bearing ingredient.

Five examples:

- `recipe.ash-gourd-kootu`
- `recipe.ash-gourd-poriyal`
- `recipe.asia-black-bean-pumpkin-curry`
- `recipe.asia-chickpea-cauliflower-curry`
- `recipe.asia-chickpea-plantain-curry`

The recipe corpus reaches that set through `dravya.coconut-fresh` (73 recipes),
`dravya.coconut-oil` (70), `dravya.coconut-water` (7), and
`dravya.coconut-dried` (6); recipes can contain more than one, so those counts
overlap. There are 104 coconut-tagged recipes total; the other 10 also contain
a non-coconut nut. Coconut remains conservatively in the existing nut
vocabulary pending the founder/expert taxonomy ruling.

#### Vegetarian and Egg-Free corpus truth

The 1,500/1,500 Vegetarian and Egg-Free result is a **true property of the
current recipe corpus**, not an unresolved-input default:

| Resolution check | Result |
|---|---:|
| recipe ingredient rows | 10,571 |
| rows resolved to a dravya or direct FDC row | 10,571 |
| unresolved rows | **0** |
| animal-category dravya references | 0 |
| egg allergen references | 0 |
| fish/crustacean references | 0 |
| direct FDC ingredients lacking Vegetarian or Egg-Free | 0 |

The intersection rule has no permissive unresolved fallback. A missing
dravya/FDC safety row raises `BuildError`, and an ingredient that cannot resolve
to a store food ID fails the build; it never enters the diet intersection.

#### Recipe age-floor distribution

All 1,500 recipe age fields are now nonzero because the maximum existing
ingredient age is carried forward. Only four recipe rows carry the explicit
`honey-min-age:12` rule (plus four honey dravyas, eight canonical rows total).

| Statistic | Months / count |
|---|---:|
| minimum | 6 months |
| median | 24 months |
| maximum | 192 months |
| recipes above 12 months | 1,499 |

Exact distribution:

| `minAgeMonths` | Recipes |
|---:|---:|
| 6 | 1 |
| 24 | 1,201 |
| 48 | 226 |
| 60 | 70 |
| 192 | 2 |

The three ingredients driving the highest floors are inherited source values:

| Ingredient | Floor | Recipes driven |
|---|---:|---:|
| `dravya.chamomile-tea` (loose dried chamomile) | 192 | 1 |
| `dravya.hibiscus-tea` (loose dried hibiscus petals) | 192 | 1 |
| `dravya.oats` (rolled oats) | 60 | 70 |

The unexpectedly high source floors are exposed for expert review; WE-8 does
not reinterpret or lower existing values.

### IngredientLink parity and deterministic artifacts

The candidate does not introduce a parallel IngredientLink path. It
hard-gates the already correct build-time projection:

| Check | Candidate result |
|---|---:|
| `ZINGREDIENTLINK` rows | 10,571 |
| recipe owners | 1,500 |
| positive-gram rows | 10,571 |
| kitchari spot-check | exact 8/8 |
| seed-to-store multiset mismatches | 0 |

Two independent seed builds were byte-identical:

```text
e4bfcd638ce10d2815238a0c7da2dff00114f041bbd620425b7db92ac2d55156
```

Two independent compact/store builds were also byte-identical:

```text
part-aa  fb44696a82f9ad53bd8e98a65164865a2a160fb4e285a73173847226bc7fb0b8
part-ab  c2a569744291bcb89cfa509810a08aa991477c0d7e54e8a2be8c9a3db7d73bb2
```

The complete post-restart rerun again built the seed twice and reproduced the
checked-in seed SHA. It also re-audited and re-compacted the same immutable
store twice; those two outputs were mutually byte-identical and passed every
count/link/cache/safety assertion. Re-VACUUMing the already compacted shipped
SQLite produces a different page layout than the original one-time source-store
compaction, so that diagnostic output did not replace the checked-in parts.

The cache remains version 4 with 14,484 rows, 64 Ayurveda facet keys,
20,114 facet assignments, and a 28,454,643-byte JSON payload. Compressed
preseed size increased by 478,317 bytes (0.52%); seed size increased by
35,927 bytes (2.73%). The one-time manufacturing rebuild took 680.0 seconds.

### Upgrade and fresh-store evidence

The controlled v3-to-v4 simulator upgrade logged:

```text
Ayurveda v4 slug-keyed delta: inserted 0 rows
(0 foods, 0 profiles, 0 links);
updated 2214 profiles, 0 links, 0 recipe foods, 2170 safety rows;
replaced 0 ingredient sets.
```

The **44-row difference** is exact: 44 dravya FoodItems already had the target
USDA-derived diets, allergens, and age, so the idempotent updater skipped them;
all 1,500 recipe rows and the other 670 dravyas required an update.

The stopped upgrade store was then compacted into the candidate artifact. A
fresh install of that artifact logged:

```text
Ayurveda v4 preseed stamp verified; no inserts or updates.
SearchIndexStore: Index is up-to-date (version: 4, DB: 14484).
Skipping rebuild.
```

A second run logged `Ayurveda seed version already applied, skipping` and again
skipped index rebuilding. Thus the candidate satisfies zero insert, zero
rebuild, and second-run idempotence.

## Phase C — final evidence

### Founder ruling and auditable golden history

The founder selected decision candidate 2: `recipe.curry-leaf-chutney` remains
Vegan, no derived flag was weakened, and FoodSearch ranking code was not
changed. The `vegan curry` entry in
`tests/fixtures/we4_golden_queries.json` now carries a `baselineHistory` object
with task, date, and reason. Its approved top five are:

1. Curry Leaves
2. Curry sauce
3. Curry leaf (dried)
4. Curry Leaf Chutney
5. Curry leaves (dried)

The production engine matched **25/25** updated legacy arrays exactly.

Two negative safety goldens now live in the same fixture:

| Query | Invariant | Production result |
|---|---|---|
| `without dairy` | must exclude `recipe.amaranth-kheer` | PASS — absent |
| `no allergens` | must exclude every allergen-bearing seeded recipe | PASS — zero violating seeded recipes |

These complement the derivation tests: they lock both the stored safety
property and the actual production-query behavior that consumes it.

### Production search performance

Method: the production `searchCompact` path over all 14,484 compact rows, five
warmups plus 30 samples per query on the same iOS 26.2 simulator. The comparison
is the WE-4 baseline; the gate is no pure-text median above +10%.

| Query | WE-4 median | WE-8 median / p95 | Median delta |
|---|---:|---:|---:|
| `t` | 48.25 ms | 50.324 / 51.988 ms | +4.3% |
| `tom` | 16.01 ms | 15.059 / 16.661 ms | −5.9% |
| `tomato` | 15.63 ms | 14.697 / 14.954 ms | −6.0% |
| `rice` | 14.57 ms | 13.700 / 14.736 ms | −6.0% |
| `chicken` | 18.64 ms | 18.984 / 20.381 ms | +1.8% |
| `lentil soup` | 13.83 ms | 13.394 / 14.058 ms | −3.2% |

Worst median delta: **+4.3%**; gate limit: **+10%**.

### Fresh install, idempotence, and launch

The final uninstrumented Debug product was installed after removing the app
container. Fresh launch logged:

```text
Ayurveda v4 preseed stamp verified; no inserts or updates.
SearchIndexStore: Index is up-to-date (version: 4, DB: 14484).
Skipping rebuild.
```

The next launch and all three cold-process samples logged:

```text
Ayurveda seed version already applied, skipping.
SearchIndexStore: Index is up-to-date (version: 4, DB: 14484).
Skipping rebuild.
```

Settled host start-to-first-frame samples were 1.583s, 1.592s, and 1.611s;
median **1.592s**, preserving the WE-6 `<2.0s` gate. The one-time fresh path
took 4.953s inside app-controlled signposts; a 21-second simulator-service delay
before app process start after the Mac reboot was discarded rather than
misattributed to app launch.

### Complete local gate rerun

| Gate | Final result |
|---|---|
| Validator + D34 resolver | PASS — 714 dravyas, 1,500 recipes, 12,601/12,601 USDA rows |
| Deterministic seed SHA | PASS — both builds and shipped seed `e4bfcd…5156` |
| Deterministic compact-store rerun | PASS — two outputs matched byte-for-byte; all hard audits green |
| Artifact integrity / duplicates | PASS — SQLite `quick_check`; 14,484 unique foods; 2,214 unique profiles |
| IngredientLink parity | PASS — 10,571 positive-gram rows, 1,500 owners, exact kitchari links |
| Complete repository suite | PASS — **53/53** |
| WE-8 safety methods | PASS — **15/15**, including both safety goldens |
| Production legacy goldens | PASS — **25/25** exact |
| Production safety goldens | PASS — **2/2** |
| Search performance | PASS — worst median +4.3%, limit +10% |
| Fresh no-insert/no-rebuild | PASS |
| Second seed run | PASS — version-stamped no-op |
| Cold-process launch | PASS — 1.592s median, target <2.0s |
| Clean Debug arm64 simulator build | PASS |
| Clean Release arm64 simulator build | PASS |
| Lifecycle | PASS — 2,214/2,214 remain `aiDraft` |
| Claims boundary | PASS — canonical-only projection; non-profile USDA rows have no Ayurveda facets or claims |

## Follow-up decisions — not started

1. Founder/expert ruling on whether coconut should remain in the existing
   nut-family allergen vocabulary or receive a distinct tag; the conservative
   94-recipe set remains flagged meanwhile.
2. Expert review of inherited `minAgeMonths` source values, especially the two
   192-month tea floors and the 60-month oat floor. WE-8 intentionally preserves
   rather than normalizes them.
