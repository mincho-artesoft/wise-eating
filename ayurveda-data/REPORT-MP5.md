# REPORT-MP5 — Deterministic plan assembly

Date: 2026-07-26
Branch: `mp-5-solver` from `003bed7`
Status: **COMPLETE ON FEATURE BRANCH — not merged, not pushed**

## Outcome

The planner now assembles plans with a deterministic greedy solver plus bounded
iterated local search. Food IDs, portions, calories, macros, safety decisions,
and structural placements come from typed catalogue data and constraints, not
model output. The solver validates every hard invariant before returning a
plan and throws a named infeasibility instead of weakening a constraint.

The feature flag is **`MP5AyurvedicSolverEnabled`**, with launch argument
`-mp5AyurvedicSolver`. It is **off by default**. The flag gates the aiDraft
Ayurvedic selection objective; the deterministic structural/safety/nutrition
assembler is common to both modes. This boundary preserves the founder's
vaidya-review hold on user-visible dosha scoring while allowing the obsolete
LLM assembly/repair pipeline to remain deleted.

Both modes use the same compiled binary and passed the acceptance harness:
flag-on runs exercise dosha scoring and flag-off comparison runs exercise the
same hard constraints without Ayurveda influencing selection.

## Implementation

- `DeterministicMealPlanSolver.swift` contains only `Foundation`; it has no
  `FoundationModels`, `LanguageModelSession`, or model-response dependency.
- A deterministic SplitMix64 generator drives greedy tie-breaking and bounded
  local-search mutations. No system random generator is used.
- Hard candidate filtering uses canonical FoodConcept membership, ingredient
  propagation, diet/allergen sets, explicit disliked IDs,
  `AyurvedaRecommendationGate`, authored age floors, and hard viruddha checks.
- `MP5MustContainRule` remains structured from interpretation through solve.
  No English serialization/regex round-trip remains.
- Dish count adapts from 2 through 6; proportional portion fit remains within
  per-food clamps and is repaired against the exact USDA-derived energy sum.
- Rasa is scored over the plan window, vikriti remains a soft objective, and
  construction asserts the classical precedence:
  **rasa 1 < vipaka 2 < virya 4 < prabhava 8**.
- The planner's assembly checkpoint contains **0**
  `LanguageModelSession`/`.respond` sites. The enclosing pre-MP-4 branch still
  has 8/8 model sites outside assembly for prompt interpretation and later
  work; MP-5 did not claim to remove those.

## Acceptance corpus

The director corpus contains 10 profiles, 36 properties, 23 hard invariants,
and 13 measured soft objectives. The harness ran 45 feasible
profile/horizon/seed combinations plus three expected P10 infeasible runs.

### All 23 hard properties

| ID | Invariant | Actual |
|---|---|---|
| S1 | Requested day count | **PASS**, 45 runs |
| S2 | Exact requested meals per day | **PASS**, 195 day checks |
| S3 | No empty meal | **PASS**, 585 meal checks |
| S4 | Every component has positive grams | **PASS**, 585 meal checks |
| S5 | Every component has a real catalogue FoodItem ID | **PASS**, 585 meal checks |
| N1 | Daily kcal within ±18% | **PASS**, 195 day checks; measured error effectively 0 |
| N2 | Daily kcal equals exact component/FoodItem sum | **PASS**, 195 day checks; max floating error `4.55e-13` kcal |
| N3 | Daily macros equal exact component/FoodItem sums | **PASS**, 195 day checks; max floating error `1.14e-13` |
| A1 | No excluded-allergen concept member | **PASS**, 2,218 component checks |
| A2 | No excluded/disliked FoodItem ID | **PASS**, 2,218 component checks |
| A3 | No AyurvedaRecommendationGate exclusion | **PASS**, 2,218 component checks |
| A4 | Vegan concept exclusions | **PASS**, 236 applicable checks |
| A5 | Vegetarian concept exclusions | **PASS**, 741 applicable checks |
| A6 | Jain sattvic/allium exclusions | **PASS**, 127 applicable checks |
| A7 | No authored age floor above profile age | **PASS**, 2,218 component checks |
| A8 | No hard viruddha pair | **PASS**, 585 meal checks |
| V1 | No repeat inside two-day window | **PASS**, 195 day checks |
| D1 | Same inputs/seed are byte-identical in-session and after relaunch | **PASS**, 45 runs |
| D2 | Different seeds produce different plans | **PASS**, 45 runs |
| F1 | P10 reports infeasible and emits no partial plan | **PASS**, 4 applicable checks |
| F2 | Infeasibility names its blocking constraint | **PASS**, 4 applicable checks |
| P_2 | Zero model calls during assembly | **PASS**, 45 runs; static checkpoint also 0/0 |
| P_3 | Solver has no FoundationModels linkage | **PASS**, core and adapter |

P10's actual error was:

> Meal plan is infeasible: allergen exclusions leave no safe candidate
> (dairy, egg, fish, gluten, peanut, sesame, shellfish, soy, tree_nuts)

### All 13 soft properties

Soft misses are reported, not tuned into apparent passes.

| ID | Objective | Measured result |
|---|---|---|
| S6 | 2–6 components per meal | **Met**; min 2, mean 3.791, max 6 |
| N4 | Protein within ±25% target | **Miss / tuning finding**; relative error min 0.004, mean 0.613, max 1.788 |
| N5 | Fibre floor | **Met**; daily fibre min 45.630, mean 81.991, max 179.997 g |
| A9 | Report soft viruddha pairs | **Met**; 0 in all 45 generated plans |
| V2 | Slot-to-slot sets differ by ≥2 components | **Met**; difference min 4, mean 7.611, max 12 |
| V3 | ≥25 distinct IDs in seven days | **Met**; min 34, mean 45, max 58 |
| Y1 | Imbalance produces more pacifying selection | **Met**; imbalanced mean −1.6565, cleared mean −1.1355, pacifying delta **+0.5209**; per-run delta min 0.0933, max 0.7553 |
| Y2 | Slow agni selects less heaviness | **Met**; 0.3059 vs 0.5588, improvement 0.2529 |
| Y3 | Slow agni selects smaller portions | **Met**; 69.146 g vs 83.168 g, reduction 14.022 g |
| Y4 | Rolling rasa coverage ≥5 tastes | **Met**; 6/6 in all 18 applicable seven-day runs |
| Y5 | Midday heavier than evening | **Miss / tuning finding**; lunch-minus-dinner min −0.100, mean +0.244, max +0.650 |
| Y6 | Tier composition | **Reported**; classical 17.18%, derived 20.51%, estimated 62.31% |
| P_1 | Seven-day solve under 2 seconds | **Met**; min 4.193 ms, mean 17.639 ms, max **50.028 ms** |

Y1 is non-flat and moves in the correct direction. The dosha effect is
therefore reaching selection. Y6 also shows that 62.31% of selected components
use the weakest estimated Ayurveda tier; this is a review/tuning concern, not a
hard-validity failure.

## Calorie edge profiles

| Profile | Requested | Actual range across seeds |
|---|---:|---:|
| P7 low edge | 1,200 kcal/day | **1,200.000000–1,200.000000 kcal/day** |
| P8 high edge | 3,600 kcal/day | **3,600.000000–3,600.000000 kcal/day** |

Adaptive dish count closes both silent-unreachability defects from reference
testing; no plan merely looks plausible while missing its energy target.

## Required deletion audit

All 14 director-listed targets were deleted; there were no refusals.

| Target | Result |
|---|---|
| `generateFullPlanWithAI` | Deleted |
| `AIConceptualPlanResponse1D` through `7D` | Deleted |
| `aiGenerateFoodPaletteForCuisine` | Deleted |
| `aiGenerateFoodPaletteForHeadword` | Deleted |
| `aiGenerateFoodPalette` | Deleted |
| `aiGenerateVariantsOnly` | Deleted |
| `aiInferContextTags` | Deleted |
| `isPlanStructureValid` retry loop | Deleted |
| `remapDuplicateDays` | Deleted |
| `ensureIncludedFoodsPlaced` | Deleted |
| `removeBannedCuisineKeywords` | Deleted |
| `trimToRequestedDaysAndMeals` | Deleted |
| `normalizeMealsToRequestedOrder` | Deleted |
| `specializeStructuralRequestsWithHeadwords` | Deleted |

A final static search over `WiseEating/AI/MealPlanning/` found none of these
function/type declarations.

`USDAWeeklyMealPlanner.swift` changed from **5,374 to 3,348 lines**:
**−2,026 lines (−37.7%)**. The new solver is isolated in its own source file,
with a separate WiseEating/SwiftData adapter.

## Gate ledger

| Gate | Result |
|---|---|
| G1 Debug + Release, flag ON/OFF | **PASS** — generic arm64 simulator Debug and Release builds succeeded; both flag modes are in the same binary and exercised by tests; no new warnings |
| G2 full suite | **PASS — 108/108** in 49.948s = 98 baseline + 10 MP-5 |
| G3 search goldens | **PASS — 25/25 legacy + 2/2 safety exact** |
| G4 resolution corpora | **PASS — training 59/59; held-out 44/48; zero wrong-confident; controls 5/5 unresolved** |
| G5 hard properties | **PASS — 23/23** |
| G6 soft properties | **13/13 measured**; N4 and Y5 reported misses |
| G7 assembly model calls | **PASS — zero** by telemetry property and static checkpoint |
| G8 FoundationModels solver linkage | **PASS — zero** |
| G9 determinism | **PASS — D1 and D2** |
| G10 cold launch | **PASS — 1.401303s median**, below 1.650s trigger / 1.700s ceiling |
| G11 fresh install | **PASS — zero Ayurveda inserts/updates; no search-index rebuild** |
| G12 tracked files | **PASS — 999 checked; maximum 82,726,160 bytes, below 90 MB split point** |
| G13 planner line count | **PASS — 5,374 → 3,348 (−37.7%)** |
| Validator | **PASS — 714 dravyas, 1,500 recipes, 12,601/12,601 USDA resolution** |

No seed, rule, concept, preseed, lifecycle, claim, ranking, or UI-copy artifact
was changed. Existing shipped artifact SHAs remain:

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `ayurveda_seed.json.gz` | 1,438,588 | `886c6a3908b9661ae85223b13cc353326a93ef2ac552129b6a60e529e481872e` |
| `ayurveda_rules.json` | 21,151 | `e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c` |
| `food_concepts.json.gz` | 31,165 | `fe200fe30b1a25dfd091fef6099fe5c34844d8460262ec0ab87986a6399dd7b1` |
| preseed part `aa` | 73,400,320 | `99a977616c554f3e67d683de045b11bf2a2dd6567f41702d71cc5788f42bb817` |
| preseed part `ab` | 19,162,561 | `f6b0cd508ccd2a5d2e343ce87b166e6f72df75b3b24f5eda528d08cb1e0b291c` |

Fresh-install log evidence:

- `Ayurveda v5 preseed stamp verified; no inserts or updates.`
- `SearchIndexStore: Index is up-to-date (version: 5, DB: 14484). Skipping rebuild.`

## Same-session cold launch

Method:

- retained iOS 26.2 simulator `WiseEating-WE2-Baseline`
  (`AF937668-3BFE-45E8-B42A-A76B914038DD`), the only booted simulator;
- A = branch point `003bed7`; B = final MP-5;
- separate temporary bundle IDs/containers, arm64 Debug, identical build
  settings, package checkout, preseed resources, and ignored 1024 video;
- both received untimed fresh/warm setup and calendar/reminder permission;
- Xcode, xcodebuild, Swift compiler, Chrome, Claude, Maestro, and CI were absent
  during the accepted series; Codex, CoreSimulator, WindowServer, and ordinary
  macOS background services remained;
- host `time.monotonic()` immediately before
  `simctl launch --console-pty`; terminal marker
  `WE6_PROFILE|first-interactive-frame|<uptime>`;
- strict AB repeated ten times, terminating the process before every launch.

| Pair | A `003bed7` | B MP-5 | B − A |
|---:|---:|---:|---:|
| 1 | 1.411544s | 1.407295s | −0.004249s |
| 2 | 1.391933s | 1.398020s | +0.006086s |
| 3 | 1.407490s | 1.404431s | −0.003060s |
| 4 | 1.398954s | 1.391940s | −0.007015s |
| 5 | 1.406692s | 1.396202s | −0.010490s |
| 6 | 1.396149s | 1.398256s | +0.002107s |
| 7 | 1.392781s | 1.394009s | +0.001228s |
| 8 | 1.423194s | 1.404349s | −0.018845s |
| 9 | 1.397296s | 1.411804s | +0.014508s |
| 10 | 1.427237s | 1.408351s | −0.018885s |

| Series | N | Median | IQR (Q1–Q3) | Min | Max | Population stddev |
|---|---:|---:|---:|---:|---:|---:|
| A | 10 | **1.402823s** | 0.014095s (1.396436–1.410531) | 1.391933s | 1.427237s | 0.011707s |
| B | 10 | **1.401303s** | 0.009923s (1.396656–1.406579) | 1.391940s | 1.411804s | 0.006337s |
| Paired delta | 10 | **−0.003654s** | 0.011508s (−0.009621–0.001887) | −0.018885s | +0.014508s | 0.010014s |

The paired median delta is smaller than both A and B IQRs, so a launch change
is not resolvable from this sample.

## Follow-up candidates

1. Diagnose/tune protein objective N4 without weakening any hard property.
2. Improve Y5's three inverted lunch/evening cases while preserving Y1 and
   calorie reachability.
3. Review the 62.31% estimated-tier composition with the vaidya before
   enabling `MP5AyurvedicSolverEnabled` by default.

No follow-up was started. Work remains committed only on `mp-5-solver`; it was
not merged and not pushed.
