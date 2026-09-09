# REPORT WE-4 — Ayurvedic facets in FoodSearch

Date: 2026-07-24
Branch: `ayurveda-app`
Status: **COMPLETE — all local gates green**

## Summary

WE-4 adds canonical Ayurvedic facets to the existing 14,484-row FoodSearch
index without changing ordinary text, nutrient, diet, allergen, pH, favorite,
recipe/menu, or semantic behavior.

The shipped version-4 index now carries:

- per-item canonical facet sets on exactly the 714 seeded dravyas and 1,500
  seeded recipes;
- a separate 64-key inverted facet index;
- natural-speech and explicit facet parsing that composes with the existing
  query residue; and
- the regenerated build-time store, so a fresh install still performs no
  Ayurveda inserts and no search-index rebuild.

Plain USDA rows have empty facet sets. A linked or derived Ayurveda
classification never becomes a direct searchable claim.

The donor `CanonicalFacetParser.swift` was consulted read-only for its
canonical `kind:value` parsing idea. WiseEating's persisted cache, existing
tokenizer, candidate intersection, ranking, lifecycle, and ownership rules
remain authoritative.

## T1 — index-time facets

### Projection

Facets are projected from the bundled canonical seed before the normal compact
index is serialized. The rebuild path decodes only the small facet projection
from `ayurveda_seed.json.gz`; it does not materialize all full SwiftData
profiles. Single-item cache updates still inspect the direct profile and reject
noncanonical kinds.

| Family | Keys / assignments |
|---|---:|
| Virya | cooling 321 · heating 331 · neutral 62 |
| Pacifies | vata 1,299 · pitta 1,066 · kapha 1,036 |
| Aggravates | vata 196 · pitta 408 · kapha 422 |
| Agni | kindles 288 · dampens 121 |
| Digestibility | light 364 · heavy 95 |
| Seasons | grishma 1,493 · hemanta 1,716 · sharad 1,462 · shishira 1,685 · varsha 1,470 · vasanta 1,410 |
| Category | 22 canonical category keys · 2,214 assignments |
| Concept | the same 22 category concepts plus digestion 441 · 2,655 assignments |
| **Total** | **64 keys · 20,114 assignments** |

Dosha zeroes intentionally produce no pacifies/aggravates claim. Agni zeroes
and middle digestibility values likewise produce no directional claim.
Winter is a query-time alternative across hemanta and shishira, not a new
stored value.

### Ownership and persistence audit

| Check | Result |
|---|---:|
| Compact foods | 14,484 |
| Canonical facet foods | 2,214 |
| Non-profile foods with facets | 0 |
| Facet keys in ordinary text index | 0 |
| Facet index mismatch vs per-item sets | 0 |
| Duplicate FoodItem IDs / profile slugs / profile food-kind rows | 0 / 0 / 0 |
| Cache version / row count | 4 / 14,484 |

The permanent test independently recomputes every facet from the 714 + 1,500
seed records and compares all 2,214 item sets plus the complete inverted index.

### Artifact

| Measurement | WE-2 version 3 | WE-4 version 4 | Delta |
|---|---:|---:|---:|
| Cache JSON payload | 27,436,229 B | 28,233,788 B | +797,559 B (+2.91%) |
| Two compressed bundle parts | 91,947,443 B | 92,057,352 B | +109,909 B (+0.12%) |

Two independent builds from the audited source store reproduced byte-for-byte:

```text
part-aa  4e18d019b9ef2e94f1492216f445fa21b87317c5a1e53b79e60f8c005227fe57
part-ab  72d19e2f6fb86c51297a6cd65a0bc75eb3fe55113f69249934dfaadc986c13ab
```

## T2 — query grammar

Recognized phrases are removed before the existing tokenizer runs. The
remaining name/nutrient/diet/pH query follows the unchanged pipeline. Keys
inside one constraint are OR alternatives; separate constraints are
intersected.

| Family | Natural speech | Canonical constraint |
|---|---|---|
| Virya | cooling; warming; heating; neutral virya | `virya:*` |
| Pacifies | balances, calms, pacifies, good for vata/pitta/kapha; reverse “vata pacifying” form | `pacifies:*` |
| Aggravates | aggravates, avoid for vata/pitta/kapha; reverse form | `aggravates:*` |
| Agni | kindles agni; dampens agni | `agni:*` |
| Digestion | for digestion; digestive foods | `concept:digestion` |
| Digestibility | light/easy to digest; heavy/hard to digest | `digestibility:*` |
| Seasons | summer, winter, spring, autumn/fall, monsoon/rainy; all six ritu names | `season:*` |
| Categories | 22 conservative singular/plural category aliases when another Ayurveda facet is present | `category:*` |
| Explicit | `virya:cooling`, `pacifies:pitta`, `ritu:grishma`, `category:grain`, etc. | validated canonical key |

The three Sanskrit additions in `food_synonyms.json` are intentionally narrow:

| Added term | Expansion | Reason |
|---|---|---|
| `ushna` | heating | direct virya vocabulary |
| `sheeta` | cooling | direct virya vocabulary |
| `deepana` | kindles agni | direct agni vocabulary |

No broad semantic guessing was added. Unknown text and unknown explicit values
remain untouched for the existing text/semantic path. Standalone category words
also keep their prior text meaning. Exact indexed titles bypass facet parsing;
for example, `Warming Brown Lentil Soup` still resolves to that exact recipe.

Mixed examples exercise all three paths:

| Query | Facet constraints | Existing residue |
|---|---|---|
| cooling tomatoes low fat | cooling | `tomatoes low fat` |
| high iron pacifies pitta | pacifies pitta | high-iron nutrient intent |
| warming winter grains | heating AND (hemanta OR shishira) AND grain | empty |

`cooling tomatoes low fat` honestly returns no result because both canonical
tomato dravyas are heating; the parser does not weaken a facet to manufacture a
match.

## Golden queries

The production `SmartFoodSearch3.searchCompact` path was captured before and
after with a five-result limit. All 25 legacy queries matched exactly, including
existing empty/comparative behavior; no comparative feature was added.
The complete before/after arrays are pinned in
`tests/fixtures/we4_golden_queries.json`.

| Legacy query | First result after | Result |
|---|---|---|
| tomato | Tomato powder | 5/5 stable |
| tomatoes low fat | — | empty stable |
| rice | Rice, white, medium-grain, cooked, unenriched | 5/5 stable |
| brown rice | Bread, gluten-free, whole grain… | 5/5 stable |
| chicken | Chicken cornbread | 5/5 stable |
| chicken without tomato | Chicken cornbread | 5/5 stable |
| high iron | Babyfood…added iron fortified | 2/2 stable |
| more iron than spinach | — | empty stable |
| low sodium soup | Soup, pea, low sodium… | 5/5 stable |
| high protein breakfast | — | empty stable |
| vitamin c orange | Beverages, orange drink… | 1/1 stable |
| gluten free bread | Bread, gluten free | 5/5 stable |
| vegan curry | Curry Leaves | 5/5 stable |
| dairy free yogurt | Yogurt, soy | 3/3 stable |
| no peanuts | — | empty stable |
| acidic fruit | Lemonade, fruit juice drink | 5/5 stable |
| alkaline foods | Spinach, frozen… | 2/2 stable |
| ph 7 | — | empty stable |
| salmon | Salmon salad | 5/5 stable |
| lentil soup | Fennel Red Lentil Soup | 5/5 stable |
| apple | Apple cider | 5/5 stable |
| banana | Banana chips | 5/5 stable |
| egg | Egg bhurji | 5/5 stable |
| whole milk | Cheese, mozzarella, whole milk | 5/5 stable |
| olive oil | Olive oil | 5/5 stable |

New facet goldens include:

| Query | Top result |
|---|---|
| cooling foods | Aam panna |
| warming foods | Aged honey |
| pacifies vata | Aam panna |
| deepana foods | Aam panna |
| high iron pacifies pitta | Punjabi Methi Matar Fennel |
| warming winter grains | Browntop millet |
| Warming Brown Lentil Soup | Warming Brown Lentil Soup |

## Performance

Measurements use the exact production `searchCompact` path over 14,484 compact
items on the same iOS 26.2 simulator and Mac. Each query had five warmups and 30
timed iterations. The initial fresh-launch sample was discarded because it
overlapped unrelated host work; the final table is the idle, repeated run.

### As-you-type pure text

| Query | Baseline median / p95 | Final median / p95 | Median delta |
|---|---:|---:|---:|
| `t` | 48.11 / 53.39 ms | 48.25 / 49.66 ms | +0.3% |
| `tom` | 17.21 / 18.50 ms | 16.01 / 19.01 ms | −7.0% |
| `tomato` | 15.86 / 17.56 ms | 15.63 / 17.05 ms | −1.4% |
| `rice` | 15.39 / 17.58 ms | 14.57 / 15.15 ms | −5.4% |
| `chicken` | 19.56 / 24.13 ms | 18.64 / 20.37 ms | −4.7% |
| `lentil soup` | 14.35 / 15.35 ms | 13.83 / 14.59 ms | −3.6% |

The worst pure-text median change is **+0.3%**, below the allowed +10%.

### Facet queries

| Query | Median / p95 |
|---|---:|
| cooling foods | 14.62 / 15.77 ms |
| pacifies pitta | 21.37 / 23.29 ms |
| winter foods | 32.83 / 33.98 ms |
| high iron pacifies pitta | 37.75 / 39.35 ms |
| warming winter grains | 12.57 / 13.48 ms |

Facet queries remain in the same millisecond order of magnitude.

### Index build

| Measurement | Baseline | Final | Delta |
|---|---:|---:|---:|
| Full 14,484-row build + serialize + save | 359.11 s | 381.13 s | +22.02 s (+6.1%) |

The final path reads the 1.3 MB bundled facet projection. A discarded prototype
that fetched every full profile was not shipped.

## Fresh-install guarantee

The final non-instrumented build was uninstalled, installed, and launched from
the regenerated bundle. Its log was:

```text
✅ Ayurveda v3 preseed stamp verified; no inserts or updates.
✅ SearchIndexStore: Index is up-to-date (version: 4, DB: 14484). Skipping rebuild.
🔎 SearchIndexStore: Loaded from cached index (version: 4, 14484 foods).
```

The WE-2 fresh-store and second-run idempotence tests remain green.

## Local gates

| Gate | Result |
|---|---|
| Final artifact validator + D34 resolver simulation | PASS — 714 dravyas / 1,500 recipes; 12,601/12,601 USDA foods resolved |
| Full repository Python suite | PASS — 19/19 |
| Grammar families / mixed / Sanskrit / unknown fallback | PASS |
| Exact seed-to-index facet projection | PASS — 2,214/2,214; 64 keys; 20,114 assignments |
| Non-Ayurvedic USDA ownership | PASS — 0 non-profile rows with facets |
| 25-query legacy golden | PASS — every before/after top array identical |
| Facet golden queries | PASS |
| Pure-text latency | PASS — worst median +0.3%, limit +10% |
| Facet latency | PASS — same order of magnitude |
| Index build / artifact size | PASS — +6.1% / +0.12% |
| Two-build artifact determinism | PASS — both part hashes reproduced |
| Fresh-install zero inserts / no rebuild | PASS — final runtime log |
| WE-2 idempotence | PASS — second seed run inserts zero |
| iOS simulator build | PASS |
| Lifecycle | PASS — all 2,214 canonical profiles remain `aiDraft` |
| Claims boundary | PASS — plain USDA rows have no facets; no content or medical-language changes |
| Scope | PASS — search/index, synonyms, tests, artifact, and required docs only |

The Xcode project has no test target. As in WE-2/WE-3, the repository suite
compiles production Swift where possible, deeply audits the shipped store, and
is paired with production simulator build/runtime gates.

## Follow-up candidates

These are candidates only; none was started:

1. Add an Xcode test target so production-engine golden runs can execute without
   the current local simulator capture harness.
2. Profile the existing nutrient-index build loop if future index versions need
   a tighter full-rebuild budget.
3. Consider visible facet chips only as a separate founder-approved UI task;
   WE-4 changes search behavior, not views.
