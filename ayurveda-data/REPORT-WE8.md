# REPORT WE-8 — Derived Safety & Search Metadata

Date: 2026-07-25  
Branch: `ayurveda-app`  
Audit tip: `2de3b22fd694bb6b8ad89ce0d5007388d649ca4e`

> Phase A was written and committed before any seed, seeder, artifact, or test
> behavior changed. The remaining sections are intentionally pending at this
> checkpoint.

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

## Phase B — build-time derivation

Pending after the Phase A checkpoint commit.

## Phase C — safety and regression gates

Pending after implementation.

