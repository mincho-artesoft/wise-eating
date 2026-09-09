# MP-3 — Deterministic Food Resolution

Date: 2026-07-26

Branch: `mp-3-deterministic-resolution`

Starting tip: `161689e8efd6d54b657b8eac4d3bd5128e5f6093`

Status: **COMPLETE — LOCAL COMMIT ONLY, NOT PUSHED**

## Outcome

Meal-plan component resolution is now deterministic and contains no model call.
The planner derives conservative lexical queries from the component name,
collects candidates through the existing `SmartFoodSearch3.searchCompact`
path, applies the unchanged Ayurveda exclusion gate, assigns the existing
classical/derived/estimated tiers, and chooses only a candidate whose
auditable score reaches the threshold.

The supplied corpus was verified before implementation: valid JSON, 12,259
bytes, 59 cases, and exactly the three ordered `expectUnresolved` controls
`unicorn steak`, `xyzzy`, and the empty string. Its 59 cases were not changed.

Against the shipped 14,484-row catalogue, the two engine-excluded food IDs
leave 14,482 eligible candidates. All 56 positive cases pass and all three
controls remain unresolved. No model fallback is needed to satisfy this corpus.

## Implementation

The production path now:

1. normalizes the concept with a fixed POSIX locale;
2. builds an ordered query list from the concept, conservative local aliases,
   and the semantic headword;
3. unions up to 120 existing search results per query by stable integer food
   ID;
4. applies `AyurvedaRecommendationGate` by name and food ID exactly as before;
5. assigns a tier from direct profiles and existing Ayurveda links;
6. scores the prepared candidates with a pure deterministic function;
7. rejects a best score below `46`; and
8. materializes the selected `FoodItem` without changing the MP-2 unresolved
   path.

Tier mapping is direct profile → classical, derived link → derived,
exact/near link → classical, and no Ayurveda binding → estimated. Plain USDA
rows remain eligible; they do not acquire an Ayurvedic claim.

The deterministic query aliases are deliberately small and local: mung/moong,
toor/arhar/pigeon pea, chana/chickpea/garbanzo/bengal gram, urad/black gram,
ghee/clarified butter, paneer/cheese, yogurt spellings, cilantro/coriander
leaf, chilli/cayenne/red pepper, ash and bitter gourd names, jaggery/gur/raw
sugar, atta, kitchari spellings, dal-tadka spelling, basmati, and lemongrass.
Unknown concepts do not invoke a model; the threshold leaves them unresolved.

## Scorer weights and rationale

| Signal | Weight | Rationale |
|---|---:|---|
| Headword match | required, base `+42` | A candidate cannot score at all unless the concept head or a conservative alias is present. |
| Exact normalized concept | `+100` | A direct lexical identity should dominate descriptive variants. |
| Exact normalized alias | `+80` | Strong but below a literal identity. |
| Contiguous concept phrase | `+26` | Rewards the intended phrase inside verbose USDA names. |
| Contiguous alias phrase | `+26` | Gives regional names the same auditable evidence. |
| All concept tokens present | `+18` | Supports reordered USDA naming without replacing the head gate. |
| Matched qualifier | `+14` each | Rewards named species/form qualifiers. |
| Missing qualifier | `−24` each | A requested qualifier is stronger negative evidence when absent. |
| Explicit form match/miss | `+10` / `−14` | Preserves milk/oil/flour/seed/dal and other named forms. |
| Named cooked form | `+14` cooked, `−28` raw/dry conflict | Prefers the matching USDA cooked analysis when requested. |
| Composite concept | recipe `+28`, non-recipe `−10` | Kitchari/curry/stew/tadka concepts should prefer recipe rows. |
| Atomic concept resolving to recipe | `−36` | Prevents a bare ingredient from drifting to a composite dish. |
| Tier | classical `+9`, derived `+5`, estimated `+0` | Implements classical > derived > estimated without overpowering relevance. |
| Strong unexplained content token | `−50` each | Blocks derivatives such as milk, oil, soup, chutney, powder, and other wrong-but-plausible products. |
| Other unexplained content token | `−4` each | Prefers the simpler candidate while tolerating USDA descriptors. |
| Unexplained leading token | `−20` | Headword direction matters: `camel milk` and `cumin water` are not bare milk/water. |
| No unexplained tokens | `+6` | Stable final preference for the cleanest match. |
| Acceptance threshold | `46` | Leaves unknown or contradictory concepts unresolved rather than forcing a match. |

Preparation words and structural USDA descriptors are not treated as content
products. Explicit form and cooked/raw logic still score them separately.
`without salt` and `no added fat` are recognized as negative descriptors so
the absent ingredient is not misclassified as an extra. Final ties are
resolved by score, tier, composite recipe preference, normalized name, then
integer food ID; no set/dictionary iteration order participates.

## Gate results

| Gate | Result | Evidence |
|---|---|---|
| MP3-G1 Debug + Release | PASS | Clean generic-iOS Debug and Release builds succeeded with signing disabled. Both have 45 unique warning messages versus MP-2's 46; no new warning was introduced and one obsolete unused-variable warning disappeared. |
| MP3-G2 full suite | PASS | `81/81` in 71.477s on the final report-ready tree: the previous 71 plus 10 MP-3 tests. |
| MP3-G3 search goldens | PASS | 25/25 legacy plus 2/2 safety, unchanged; no FoodSearch source changed. |
| MP3-G4 removed sites | PASS | Swift-source grep returned no output, exit 1. |
| MP3-G5 resolution corpus | PASS | 56/56 positive cases pass (100%); the remaining 3/59 are the expected controls and are unresolved. All 59 expectations are met. |
| MP3-G6 controls | PASS | `unicorn steak`, `xyzzy`, and empty string all return unresolved on host and simulator. |
| MP3-G7 determinism | PASS | Run A = same-process run B; run A = clean-process run C byte-for-byte. Both persisted evidence files SHA-256 `bc8ecc9cfe028c026b9fe0c58458169e4a07d0978e6a33688efc98f47ac6fcfc`. |
| MP3-G8 resolution model calls | PASS / runtime deferred | Static calls in resolution are zero. Planner-wide static inventory falls from 20→18 model sessions and 25→23 responses. MP-1 runtime confirmation remains device-deferred as authorized. |
| MP3-G9 no Apple Intelligence | PASS | Exact production helper compiled into a minimal arm64 iOS app without importing or linking `FoundationModels`; iPhone 17 Pro simulator, iOS 26.2, completed all 59 cases against 14,482 eligible rows: 56 positives resolved, 3 controls unresolved. |
| MP3-G10 structural integrity | PASS | MP-2 structure tests retain two meals/three ordered items and positive portions. Production still counts `conceptual − resolved`, excludes unresolved components from goal math, and then uses the unchanged calorie rebalance path. |

The authoritative content validator also passed 714 dravyas and 1,500 recipes
with 12,601/12,601 base foods resolved.

### G4 empty-result command

The old names are assembled so this evidence block does not itself create a
stale Swift-source match:

```sh
old_query='aiBuild''SmartQueries'
old_choice='aiChooseBest''FoodCandidate'
rg -n "$old_query|$old_choice" WiseEating --glob '*.swift'
```

Result: no output; exit status `1` (no matches).

### G7 comparison

| Comparison | Result |
|---|---|
| Run A vs run B, same executable process | identical (`sameSessionIdentical: true`) |
| Run A vs run C, newly launched executable | identical (`cmp` exit `0`) |
| Run A SHA-256 | `bc8ecc9cfe028c026b9fe0c58458169e4a07d0978e6a33688efc98f47ac6fcfc` |
| Run C SHA-256 | `bc8ecc9cfe028c026b9fe0c58458169e4a07d0978e6a33688efc98f47ac6fcfc` |

### G9 simulator method

`ayurveda-data/tests/run_mp3_simulator_gate.py` extracts the exact marked
production resolver, reconstructs the shipped catalogue from the version-5
prebuilt store, compiles a minimal UIKit app for
`arm64-apple-ios26.0-simulator`, checks its linked frameworks with `otool`,
installs it with `simctl`, and reads the result from the app's simulator data
container. The gate binary reports `resolverUsesSystemModel: false`, and
`otool` reports no `FoundationModels` link.

## Full 59-case corpus

### Positive cases

| Concept | Status | Resolved food | Score | Tier |
|---|---|---|---:|---|
| `grilled chicken breast` | PASS | Chicken, broiler or fryers, breast, skinless, boneless, meat only, cooked, grilled | 91 | derived |
| `chicken` | PASS | Chicken, broilers or fryers, meat only, raw | 101 | classical |
| `roast turkey` | PASS | Turkey, whole, meat only, cooked, roasted | 85 | derived |
| `basmati rice` | PASS | White basmati rice | 221 | classical |
| `brown rice` | PASS | Rice, brown, cooked, no added fat | 70 | estimated |
| `rice` | PASS | Rice, cooked, NFS | 82 | estimated |
| `moong dal` | PASS | Split mung dal | 93 | classical |
| `split yellow mung dal` | PASS | Split mung dal | 53 | classical |
| `toor dal` | PASS | Whole pigeon pea | 93 | classical |
| `chana dal` | PASS | Chana dal (split bengal gram) | 137 | classical |
| `urad dal` | PASS | Split black gram | 93 | classical |
| `ghee` | PASS | Ghee, clarified butter | 127 | classical |
| `paneer` | PASS | Cheese, paneer | 127 | classical |
| `yogurt` | PASS | Yogurt, NFS | 92 | estimated |
| `milk` | PASS | Milk, whole | 111 | classical |
| `coconut milk` | PASS | Coconut milk | 202 | estimated |
| `olive oil` | PASS | Olive oil | 207 | derived |
| `coconut oil` | PASS | Coconut oil | 207 | derived |
| `sesame oil` | PASS | Sesame oil | 207 | derived |
| `cumin` | PASS | Cumin | 192 | estimated |
| `turmeric` | PASS | Spices, turmeric, ground | 101 | classical |
| `coriander seed` | PASS | Coriander (seed) | 202 | estimated |
| `cilantro` | PASS | Cilantro / Coriander (leaf) | 118 | estimated |
| `cardamom` | PASS | Spices, cardamom | 101 | classical |
| `black pepper` | PASS | Black Pepper | 211 | derived |
| `chilli powder` | PASS | Cayenne | 145 | derived |
| `spinach` | PASS | Spinach, raw | 101 | classical |
| `tomato` | PASS | Tomatoes, raw | 92 | estimated |
| `carrot` | PASS | Carrots, raw | 101 | classical |
| `potato` | PASS | Potato, NFS | 97 | derived |
| `sweet potato` | PASS | Sweet potato, NFS | 111 | derived |
| `ash gourd` | PASS | Ash gourd (juicing flesh) | 101 | classical |
| `bitter gourd` | PASS | Balsam-pear (bitter gourd), pods, raw | 131 | classical |
| `lentils` | PASS | Lentils, raw | 101 | classical |
| `cooked lentils` | PASS | Lentils, mature seeds, cooked, boiled, without salt | 66 | estimated |
| `chickpeas` | PASS | Chickpeas, from dried, no added fat | 92 | estimated |
| `almonds` | PASS | Nuts, almonds | 101 | classical |
| `walnuts` | PASS | Nuts, walnuts, english | 91 | classical |
| `coconut` | PASS | Nuts, coconut meat, raw | 101 | classical |
| `honey` | PASS | Honey | 201 | classical |
| `jaggery` | PASS | Jaggery (Gur) | 127 | classical |
| `whole wheat flour` | PASS | Whole wheat flour (atta) | 161 | classical |
| `oats` | PASS | Oats, raw | 101 | classical |
| `barley` | PASS | Barley | 197 | derived |
| `kitchari` | PASS | Fresh Methi Mung Kitchari | 115 | classical |
| `dal tadka` | PASS | Masoor Dal Tadka | 109 | classical |
| `vegetable curry` | PASS | Vegetable curry | 196 | estimated |
| `curry leaves` | PASS | Curry Leaves | 211 | classical |
| `water` | PASS | Water, NFS | 92 | estimated |
| `rock salt` | PASS | Rock Salt | 215 | classical |
| `ginger` | PASS | Spices, ginger, ground | 101 | classical |
| `garlic` | PASS | Garlic, raw | 101 | classical |
| `lemon` | PASS | Lemon (fresh) | 97 | derived |
| `lemongrass` | PASS | Lemongrass | 201 | classical |
| `green tea` | PASS | Tea, hot, leaf, green | 85 | classical |
| `chamomile tea` | PASS | Tea, hot, chamomile | 75 | classical |

### Expected unresolved controls

| Concept | Status | Resolved food | Score | Tier |
|---|---|---|---:|---|
| `unicorn steak` | UNRESOLVED | — | — | — |
| `xyzzy` | UNRESOLVED | — | — | — |
| empty string | UNRESOLVED | — | — | — |

## Failure list / tuning worklist

- Corpus failures: **none**.
- Unexpected unresolved cases: **none**.
- Expected unresolved controls: **3**, all correct.

The current corpus is satisfiable without a model fallback. This is not a
claim that every future free-text concept is resolvable; unknown concepts
intentionally remain unresolved below threshold and flow through MP-2's honest
count/exclusion path. New real-world misses should be added to the corpus
before any future deterministic tuning. The present evidence does not justify
an LLM fallback.

## Scope and handoff

Production changes are confined to
`WiseEating/AI/MealPlanning/USDAWeeklyMealPlanner.swift`. Tests and the supplied
corpus live under `ayurveda-data/tests/`; the simulator utility is test-only.
FoodSearch implementation/ranking, prompts, UI, seed artifacts, lifecycle and
claims boundaries, handbook, and `PROGRESS.md` are unchanged.

The branch is intentionally not merged into `ayurveda-app` and not pushed.
MP-1's device matrix and MP-2's device evidence remain deferred and are not
claimed here.
