# MP-4 — Single-call intent parse

**Date:** 2026-07-26

**Branch:** `mp-4-intent-parse`

**Branch point:** `95da00f`

**Status:** **PASS — implementation and all authorized local gates are green;
not merged and not pushed.**

## INT-1 launch question — answered first

The reported `1.653787s → 1.461324s` launch movement is accounted for by the
bounded INT-1 paydown in commit `1918b58`, not by MP-3 silently removing a
launch check.

Before `1918b58`, `AyurvedaSeeder.bundleSeedVersion()` called `loadSeed()` and
therefore decompressed and decoded all 2,214 seed records merely to read
`seedVersion`. After that commit, the same authoritative bundle is
decompressed but its JSON is decoded into the one-field
`AyurvedaSeedVersionDTO`. Actual seed and delta work still calls the unchanged
full `AyurvedaSeedDTO` decoder and validator.

The same-session signposts account for the measured change:

| Phase | `d393bda` median | Integrated final median | Delta |
|---|---:|---:|---:|
| Warm Ayurveda check | 0.226336s | 0.043991s | −0.182345s |
| Total seed checks | 0.249819s | 0.068091s | −0.181728s |
| Full first-interactive launch | 1.653787s | 1.461324s | −0.192463s |
| Paired launch delta | — | — | −0.195318s |

All 20 accepted INT-1 launch samples still emitted the seed-version skip,
search-cache `Skipping rebuild`, and first-interactive markers. The fresh
install also retained the v5 stamp verification, zero Ayurveda inserts or
updates, and no index rebuild. The improvement is therefore the measured
version-only decode optimization; no verification, seed, cache, or index work
silently disappeared.

## Director-authored file compile audit

The supplied `MealPlanRequest.swift` was first compiled unchanged. Its parser
logic was not edited to make it build.

| Compiler finding | Bounded correction | Behavior impact |
|---|---|---|
| `DietPattern`, `GoalTag`, `DoshaTag`, `AgniTag`, and `AllergenTag` did not conform to `Generable`, causing `PlanRequest` macro expansion failures. | Added conditional `@Generable` to the five closed enums. | None. This supplies the conformance required by guided generation; raw values and cases are unchanged. |
| Foundation Models macro-generated `GenerationSchema`, `GeneratedContent`, and conversion conformances are iOS 26 APIs, while the enclosing enums and transport helpers had no matching availability. | Added `@available(iOS 26.0, *)` to the five enums, `ParsedRequest`, `RequestSanitizer`, and `FallbackParser`. | None in the planner: `USDAWeeklyMealPlanner` was already iOS 26-only. Parser decisions and sanitizer values are unchanged. |
| G8 required compiling the production fallback path with no Foundation Models module. | Added the test-only `MP4_NO_FOUNDATION_MODELS` conditional around Foundation Models import/macros. Shipping builds do not define it. | None in shipping. It lets the gate prove the fallback binary has no FoundationModels linkage. |

After the first two corrections, the previously uncompiled 411-line file
compiled in the app and in isolation. The one-call coordinator added below the
director code is MP-4 integration code, not a modification to the supplied
fallback/sanitizer decisions.

## Implementation

### One interpretation call

Checkpoint 1 in `fillPlanDetails` now calls `interpretIntent` once. The former
Checkpoint 1 calls to:

- `aiSplitIntoAtomicPrompts`
- `aiExtractRequestedFoods`
- `aiFixAtomsAndFoods`
- `aiInterpretUserPrompts`

are absent from the active checkpoint. All non-empty prompt strings are
trimmed, joined, and passed to one
`respond(to:generating: PlanRequest.self)` call with greedy guided generation.
There is no session construction in a prompt loop.

A single prewarmed session is held on the main actor. It is created on the
generation UI appearing, consumed by the next parse, and cleared so a later job
does not inherit an earlier session transcript. Prewarming is wired from:

- `AIPlanGenerationView`;
- `AIDailyMealGeneratorView`;
- the meal-plan editor's prompt-selection generation surface.

No submit action calls `prewarm()`.

### Existing vocabulary mappings

No duplicate app allergen or diet type was introduced.

| `AllergenTag` | Existing `Allergen` |
|---|---|
| dairy | `.milk` |
| gluten | `.cerealsContainingGluten` |
| tree nuts | `.nuts` |
| peanuts | `.peanuts` |
| soy | `.soybeans` |
| egg | `.eggs` |
| shellfish | `.crustaceans` + `.molluscs` |
| fish | `.fish` |
| sesame | `.sesameSeeds` |

Allergen families are expanded with the existing `Allergen.parentToChildren`
and `SearchKnowledgeBase.allergenKeywords(for:)` paths.

| `DietPattern` | Existing diet vocabulary |
|---|---|
| omnivore | no restrictive `DietType` |
| vegetarian | `.vegetarian` |
| vegan | `.vegan` |
| pescatarian | `.pescatarian` |
| eggetarian | `.vegetarian`, with the egg allowance retained as a qualitative preference |
| jain_sattvic | `.vegetarian`, with the Jain sattvic qualifier retained as a qualitative preference |

### Food resolution and honest omissions

Every free-text `prefer` or `avoid` term first uses
`FoodConcepts.shared.canonical(alias:)` and then the unchanged MP-3
`PlannerDeterministicFoodResolver`/`resolveFoodConcept` path. A term is never
used as a database key.

- Resolved positive terms enter `includedFoods` using the resolved row name.
- Resolved negative terms enter the existing hard-exclusion input.
- A term below the MP-3 threshold is retained in the unresolved list.
- A negative term already covered by its mapped allergen family is neither
  resolved again nor falsely reported as unresolved.

The single persisted caveat combines unresolved terms, `unmapped` requests,
and sanitizer adjustments into one sentence. It survives job resume and
`AIManager` result merging, and is displayed as wrapping caption text on the
completed generation card.

### Availability and fallback

`SystemLanguageModel.default.availability` is checked before any session is
taken. `.unavailable(reason)` for every reason and `@unknown default` route to
the deterministic `FallbackParser`. A failed available-model response is
counted once and also falls back deterministically.

## Gate ledger

| Gate | Result | Evidence |
|---|---|---|
| MP4-G1 Debug + Release | **PASS** | Final arm64 iOS 26.2 simulator Debug and Release both report `BUILD SUCCEEDED`. The Release log contains the same 45 normalized pre-existing warning messages as INT-1 and no warning originating in new MP-4 code. A dual-architecture generic Release attempt was stopped when simultaneous arm64/x86_64 whole-module optimizers created host memory pressure; the complete arm64 Release rerun is the recorded gate. |
| MP4-G2 full suite | **PASS — 103/103** | Final discovery run: 103 tests in 41.737s. Reconciliation: INT-1's 95 tests + 8 new MP-4 tests = 103. |
| MP4-G3 search goldens | **PASS — 25/25 + 2/2 exact** | All 25 legacy baselines remain byte-exact; `without dairy` and `no allergens` retain both safety assertions. |
| MP4-G4 resolution corpora | **PASS — unchanged** | Training 59/59 expectations: 56 positive + 3 unresolved controls. Held-out 40/48 real-food passes, 8 honest unresolved, zero wrong-confident; 5/5 controls unresolved. |
| MP4-G5 one model call | **PASS — 1/1/1** | Production `MealPlanIntentCoordinator` was driven with 1, 3, and 6 separate prompts. MP-1 telemetry recorded one `mealPlanIntentParse` session, one response, and one interpretation-stage call in every case. Table below. |
| MP4-G6 fallback reference set | **PASS — 10/10** | The exact production `FallbackParser` passed all director cases. Table below. |
| MP4-G7 sanitizer | **PASS — 2/2** | With a 2,000 kcal computed maintenance fixture, 500 kcal was raised to the 1,200 kcal floor and 9,000 kcal capped at 3,200 kcal; both returned user-facing messages. The first prompt remained seven days. |
| MP4-G8 no Apple Intelligence | **PASS** | An arm64 iOS 26.2 simulator gate compiled the production request/coordinator/sanitizer path with `MP4_NO_FOUNDATION_MODELS`; `otool -L` confirmed no FoundationModels linkage. Parse completed as vegan / 3 days / peanuts, `usedFallback=true`, `modelCalls=0`. |
| MP4-G9 fallback determinism | **PASS** | The same prompt produced an equal `ParsedRequest` in 100/100 repeated calls; the no-model simulator also produced equal consecutive coordinator outcomes. |
| Supporting validator | **PASS** | Classical 336 + derived 1,969 + estimated 10,296 = 12,601/12,601 resolved; 714 dravyas and 1,500 recipes; all checks passed against the shipped preseed store. |

### MP4-G5 — MP-1 telemetry call count

The gate uses the production coordinator and production `PlannerTelemetry`
actor. A deterministic model-response closure substitutes for device model
content so the host test measures orchestration rather than model
availability.

| Separate prompt count | `mealPlanIntentParse` sessions | responses | interpretation-stage calls |
|---:|---:|---:|---:|
| 1 | 1 | 1 | 1 |
| 3 | 1 | 1 | 1 |
| 6 | 1 | 1 | 1 |

### MP4-G6 — deterministic fallback table

| # | Prompt | Verified result |
|---:|---|---|
| 1 | `light vegetarian week, no dairy, trying to lose a bit, digestion is sluggish` | PASS — vegetarian, 7 days, weight loss, slow agni, dairy allergen |
| 2 | `3 day plan around 1800 calories, no mushrooms please` | PASS — 3 days, 1,800 kcal, mushrooms avoided |
| 3 | `I'm vegan and allergic to peanuts, make me a week of meals` | PASS — vegan, 7 days, fallback allergen list exactly peanuts; no tree-nut substring false positive |
| 4 | `just tomorrow, two meals, I have acid reflux` | PASS — 1 day, 2 meals, sharp agni |
| 5 | `my pitta is high, cooling food for 5 days, skip chillies` | PASS — 5 days, pitta focus |
| 6 | `gluten free week for muscle gain, 2800 kcal` | PASS — 7 days, 2,800 kcal, muscle gain, gluten allergen |
| 7 | `I love cheese and paneer, vegetarian week please` | PASS — vegetarian, 7 days, allergen list empty; positive dairy mention did not become an allergy |
| 8 | `weekend plan, nothing too heavy, I get bloated easily` | PASS — 2 days, digestion goal; irregular agni also detected |
| 9 | `pescatarian, no shellfish, 4 days` | PASS — pescatarian, 4 days, fallback allergen list exactly shellfish; no fish substring false positive |
| 10 | `kapha imbalance, want lighter meals for a week` | PASS — 7 days, kapha focus |

## Test maintenance

Two inherited static assertions were updated without changing their behavioral
baselines:

1. FC-1 previously asserted that `FoodConcepts.shared` had no consumer. MP-4 is
   its first authorized consumer, so the assertion now requires exactly the
   planner and exactly one canonical-alias call.
2. MP-2/MP-3 model-site counts moved from 18 sessions / 23 responses to exactly
   19 / 24, representing MP-4's one new intent session and one guided response.
   The MP-3 resolution function itself remains model-free.

No golden query, resolver weight, threshold, alias, seed artifact, search
ranking, nutrition path, lifecycle rule, or claims boundary changed.

## Final repository state

The work is committed only on `mp-4-intent-parse`. It is intentionally not
merged and not pushed, per task authorization.
