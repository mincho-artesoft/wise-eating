# MP-2 — Nutrition Truth

Date: 2026-07-26
Branch: `mp-2-nutrition-truth`
Starting tip: `d0dfc38050d6cbf2a7012800056593af441b904e`
Status: **IMPLEMENTATION COMPLETE; DEVICE-ONLY EVIDENCE DEFERRED**

## Outcome

Meal-plan macro goals now run after food resolution and use the resolved
`FoodItem` nutrition path. The production adapter reads
`FoodItem.aggregatedNutrition(for:)`, normalizes its protein, fat, and
carbohydrate values by `referenceWeightG`, and obtains energy through
`calories(for:)`. The planner no longer asks the on-device language model to
recall macro values.

The existing meal/day calorie rebalance functions and constants are unchanged.
No FoodSearch source, prompt other than the deleted legacy macro prompt, UI
copy, or resolution behavior changed.

## MP-1 boundary

Before MP-2 work, the unfinished MP-1 telemetry implementation was committed on
`ayurveda-app` as:

`d0dfc38050d6cbf2a7012800056593af441b904e`
`MP-1 telemetry implementation; device matrix, G6 and G8 NOT YET MEASURED — task not complete.`

It was not pushed and neither the handbook nor `PROGRESS.md` was changed.
This branch was created at that commit. MP-1 can therefore compare
`d393bda` with `d0dfc38` without any MP-2 plan-output change.

## Diagnosis

The reported ordering defect is confirmed. The active path adjusted
`ConceptualDay` components before resolution using language-model-recalled
per-100 g macros. It then resolved those adjusted concepts to `FoodItem` rows.
The active flow now runs in this order:

1. resolve every conceptual meal;
2. run the unchanged `rebalanceMealCalories`;
3. count components that still failed resolution;
4. adapt resolved preview items to exact `FoodItem` macro values;
5. apply numerical macro goals; and
6. write adjusted grams and `calories(for:)`-derived kcal back without changing
   IDs, names, meal membership, or ordering.

One detail in the initial analysis was broader than the live call graph:
the old whole-plan validator was dead code; the day-level validator was the
active pre-resolution path. Both used the same AI macro source and both were
removed.

## Implementation details

`PlannerMacroGoalAdjuster` is a pure, device-independent helper. Its input is
resolved items with their raw reference macro values and reference weight,
plus macro targets. It returns adjusted items, before/after totals, and the
unresolved-component count. Tests extract and compile this exact production
helper with `xcrun swiftc`; they do not import Foundation Models or call a
device model.

The former adjustment behavior was preserved:

- a source is adjustable only above 5 g nutrient per 100 g;
- an adjusted portion cannot fall below 20 g;
- `exactly` adjusts outside the existing 10% band;
- `lessThan` and `moreThan` retain their strict boundary semantics; and
- multiple targets remain sequential.

A resolved row with non-positive reference weight or an incomplete macro triplet
is excluded and logged separately. Missing nutrition is never converted to
zero. A conceptual component that remains unresolved is excluded from goal
math and counted in this per-day production log:

`⚠️ MP2 nutrition truth: Day N excludes M unresolved component(s) from goal math.`

## Gate results

| Gate | Result | Evidence |
|---|---|---|
| MP2-G1 Debug + Release | PASS | Both generic-iOS builds succeeded with code signing disabled; zero new warning messages versus the MP-1 Release log. |
| MP2-G2 full suite | PASS | 71/71 in 16.207s: the existing 62 plus 9 MP-2 tests. |
| MP2-G3 search goldens | PASS | 25/25 legacy and 2/2 safety, unchanged. |
| MP2-G4 legacy symbols | PASS | Repository-wide search returned no output. |
| MP2-G5 macro fidelity | PASS | Seven synthetic plan scenarios; exact production helper; tolerance `1e-9`. |
| MP2-G6 unresolved components | PASS | Deliberately unresolved fixture excluded one of two components and preserved count `1`. |
| MP2-G7 telemetry | DEFERRED | Static site is absent. Runtime call counts require an Apple-Intelligence-capable device planner run. |
| MP2-G8 structural integrity | PASS | Two meals and three ordered items remain two meals/three items; all resulting portions are positive. |

The validator also passed all 714 dravyas and 1,500 recipes.

### G1 warning comparison

The Debug build reports the same four pre-existing planner warnings as MP-1:
`mainItems` and `total` are never mutated, `fr` is never mutated, and `head`
is unused. Their line numbers moved because the pure helper was added. The new
nutrition code and DTO deletion add no warnings.

### G4 empty-result command

The symbol names are intentionally assembled in the shell so this report does
not itself recreate a stale textual match:

```sh
legacy_fetch='aiFetch''NutritionData'
legacy_info='AINutrition''Info'
legacy_response='AINutrition''Response'
rg -n "$legacy_fetch|$legacy_info|$legacy_response" .
```

Result: no output, exit status 1 (no matches).

### G5 macro fidelity

The fixed reference-value fixture proves the same normalization used by
`FoodItem`:

| Item | Grams | Reference macros (P/F/C per 100 g) | Contribution (P/F/C) |
|---|---:|---:|---:|
| chicken | 150 | 31 / 3.6 / 0 | 46.5 / 5.4 / 0 |
| rice | 200 | 2.7 / 0.3 / 28 | 5.4 / 0.6 / 56 |
| oil | 10 | 0 / 100 / 0 | 0 / 10 / 0 |
| **Day total** | **360** | — | **51.9 / 16.0 / 56.0 g** |

The helper returned exactly 51.9 g protein, 16.0 g fat, and 56.0 g
carbohydrate within `1e-9`. The seven scenarios are:

| Scenario | Edge covered |
|---|---|
| fixed reference plan | raw reference normalization and exact day sum |
| single item | one adjustable source and kcal recomputation |
| zero grams | zero is finite, contributes nothing, and is not adjustable |
| unresolved | nil component excluded and count `1` retained |
| floor | 1,400 kcal production floor and `moreThan` equality boundary |
| ceiling | 2,100 kcal (105% of a 2,000 kcal target) and `lessThan` equality boundary |
| structure | two meals, three items, stable order/names, positive portions |

The calorie values in the floor/ceiling fixtures are carried through the macro
helper. Actual calorie scaling remains owned by the unchanged rebalance
functions, as required.

### G6 unresolved evidence

The fixture contains one resolved item and one deliberate `nil` resolution.
Only the resolved item's FoodItem-derived protein participates in the
adjustment (10 g before, 20 g after for the fixture target), the output still
contains one item, and `unresolvedComponentCount == 1`. Production additionally
computes and logs the same count per day from conceptual versus resolved item
counts.

### G7 remaining telemetry inventory

No device-capable planner run was available in this session, so runtime counts
are not claimed. Static source inventory after removal contains 20
`LanguageModelSession` construction sites and 25 model `respond` call sites.
The remaining session labels are:

| Session label | Static occurrences |
|---|---:|
| `aiBatchClassifyFoods` | 1 |
| `aiBuildSmartQueries` | 1 |
| `aiChooseBestFoodCandidate` | 1 |
| `aiExtractRequestedFoods` | 1 |
| `aiFixAtomsAndFoods` | 1 |
| `aiGenerateFoodPalette` | 2 |
| `aiGenerateFoodPaletteForCuisine` | 1 |
| `aiGenerateFoodPaletteForHeadword` | 2 |
| `aiGenerateVariantIdeas` | 1 |
| `aiGenerateVariants` | 1 |
| `aiGenerateVariantsOnly` | 1 |
| `aiInferContextTags` | 1 |
| `aiInterpretUserPrompts` | 1 |
| `aiPolishTitle` | 1 |
| `aiSplitSinglePrompt` | 1 |
| `derivePerMealCuisineFocus` | 1 |
| `generateFullPlanWithAI` | 2 |
| **Total** | **20** |

## Twenty-food model-vs-USDA artifact

**PENDING DEVICE CAPTURE — no values were fabricated or estimated.**

The old prompt requires Apple Intelligence and cannot be invoked by the
device-independent MP-2 test harness. On the scheduled device session, capture
20 foods observed in generated plans at the MP-1 checkpoint commit
`d0dfc38`, then pair each returned protein/fat/carbohydrate value with the
exact bound `FoodItem` reference values. For each nutrient the artifact will
record absolute error and percentage error, followed by the mean and worst
case over all 20 foods. Percentage error must explicitly mark a true USDA zero
as undefined rather than divide by zero.

| Food | Model P/F/C | FoodItem P/F/C | Absolute errors | Percentage errors |
|---|---|---|---|---|
| _Pending device capture (20 observed plan foods)_ | — | — | — | — |

## Scope confirmation

Changed production scope is limited to the meal planner plus deletion of the
now-unreferenced meal-plan nutrition DTOs explicitly required by MP-2. The only
other additions are the isolated tests and this report. Search, resolution,
UI, lifecycle/claims, seed artifacts, handbook, and `PROGRESS.md` are
unchanged. This branch is not merged into `ayurveda-app` and is not pushed.
