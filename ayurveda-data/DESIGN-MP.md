# DESIGN-MP — Meal planner rearchitecture

Director design · rev2, 2026-07-26 · branch `ayurveda-app`
Supersedes the original DESIGN-WE8.md, which used a WE-8…WE-13 numbering now withdrawn (it collided with WE-8 derived safety metadata). Tasks are MP-1…MP-6.

---

## 1. Why this workstream exists

`USDAWeeklyMealPlanner.swift` was 4,160 lines making an estimated **135–260 on-device model calls per 7-day plan**. Static analysis at `f46a107` found 21 `LanguageModelSession` constructions and 26 `respond()` sites, several inside per-prompt, per-component or per-meal loops.

Two complaints, one root cause each:

**Slow.** A 7-day plan emitted as model output is ~2,745 tokens. Parsed as constraints it is ~58. At on-device decode rates that is roughly 90 seconds versus 2 — a 47× difference that no prompt tuning can reach, because the cost is proportional to output length and the output *is* the plan.

**Inaccurate.** `aiFetchNutritionData` asked the model for "typical nutritional values per 100g" and fed those invented numbers into `adjustDayForGoal`, which **mutated gram weights**. The app owned 12,601 USDA foods with analysed macros and was resizing portions from a 3B model's recollection.

A third problem nobody had named: the Ayurveda layer — 714 dravyas, 1,500 recipes, signed −2…+2 VPK across all 12,601 foods — was used **only** as a two-food exclusion gate. Nothing in the planner used it to *choose* food.

---

## 2. Target architecture

```
prompt
 ├─ 1 call   parse intent → @Generable PlanRequest        MP-4 ✅
 ├─ 0 calls  solve → constraint solver, dosha-scored      MP-5 ← THIS TASK
 ├─ 0 calls  resolve → deterministic scorer + aliases     MP-3 ✅ / FC-2 ✅
 ├─ 0 calls  nutrition → USDA FoodItem values             MP-2 ✅
 └─ 1 call   narrate → all titles batched                 MP-6
                                                  ────────
                                            target: 2 calls
```

**The invariant:** no model output is ever a food, a gram weight, a calorie figure, or a database ID. Intent returns as a bounded struct; foods come from the database; numbers come from USDA.

---

## 3. Status

| Task | State |
|---|---|
| MP-1 telemetry | implemented; device matrix deferred (see DEFERRED-VALIDATION.md) |
| MP-2 nutrition truth | ✅ `aiFetchNutritionData` deleted; goal adjustment moved after resolution; macro fidelity proven to 1e-9 |
| MP-3 deterministic resolution | ✅ zero model calls; held-out 44/48, **zero wrong-confident**; controls 5/5 |
| MP-4 single-call parse | ✅ exactly 1 call at 1/3/6 prompts; fallback 10/10; works with no Apple Intelligence |
| FC-1 / FC-2 concept ontology | ✅ 25 concepts, 75 aliases, hierarchy + ingredient propagation + vetoTokens; wired into the planner; G12 1,217 → 77 |
| **MP-5 solver** | **not started — this document** |
| MP-6 batched narration | not started |

Calls are down from ~135–260 to roughly 12–24. MP-5 removes most of the remainder.

---

## 4. MP-5 — the solver

### 4.1 What it replaces

`generateFullPlanWithAI` assembles mandatory placements, negative constraints, four core directives, a no-fusion rule, headword-association rules, palettes of up to 25 items each, three variety rules and an anti-example warning — then asks a 3B model for a complete 7-day structure with 3–5 components per meal.

Constraint-following degrades with constraint count, which is why the code needs two retries plus `isPlanStructureValid`, `normalizeMealsToRequestedOrder`, `remapDuplicateDays`, `trimToRequestedDaysAndMeals`, `ensureIncludedFoodsPlaced` and `removeBannedCuisineKeywords`. **Roughly a fifth of the file exists to repair a step that cannot reliably do its job.** A solver produces correct structure by construction, so that scaffolding becomes dead code.

### 4.2 Shape

Greedy construction plus bounded iterated local search over per-slot candidate pools, with a seeded deterministic RNG. Reference implementation validated across six profiles × three horizons plus thirteen edge cases.

**Hard constraints** — never violated, checked before emit:
allergens and diet via `FoodConcepts` set operations (hierarchy rollup *and* ingredient propagation), excluded/disliked ids, `AyurvedaRecommendationGate`, authored-provenance `minAgeMonths` floors, hard viruddha pairs, structural placements.

**Soft objectives** — scored, tuned:
macro targets; dosha pacification against vikriti using the signed −2…+2 dravya effects; agni-appropriate heaviness and portion multiplier; rasa coverage over a rolling window; season bias; no-repeat window; midday-heaviest distribution.

### 4.3 Ayurvedic modelling — three things that change the code

**Precedence is not negotiable.** Classical ordering is **rasa < vipaka < virya < prabhava** (A.H.Su.9/24–25). Virya overrules rasa and vipaka in conflict; prabhava overrules all three. Whatever weights are chosen must preserve that ordering, asserted at construction. Weights that invert it contradict the texts the dravya data was built from.

**Rasa coverage is habitual, not per-plate.** "Every meal must contain all six tastes" has no classical verse. Ca.Su.25/40 is *sarva-rasa-abhyasa* — habitual intake. Coverage belongs on a rolling multi-day window. A per-meal assertion would be unsourced and would badly over-constrain the solver.

**Vikriti is a soft objective, never a hard gate.** Inter-rater reliability for prakriti assessment *between qualified Ayurvedic physicians* is 0.20–0.40. A constitution reading is far too noisy to exclude foods on. Only allergens, dislikes and hard viruddha exclude.

### 4.4 Two failure modes found in reference testing

**Fixed dish counts make extreme calorie targets silently unreachable.** With a fixed count, per-dish portion clamps bottomed a 1200 kcal target at 1436 and topped a 4000 kcal target at ~2400 — and the plan looked entirely correct. The fix is an adaptive dish count solving for how many dishes can span the target given the clamp range and agni multiplier, plus a repair pass. Profiles P7 and P8 in the acceptance suite exist to catch exactly this.

**Structural placements must stay structured.** Today `specificVariantPlacements` builds strings like `"On Day 3, the Breakfast MUST contain exactly: 'oat porridge'."`, pushes them into the prompt, and recovers them with `parseMustContainRules` regex. A constraint that originated as structured data is serialised to English and parsed back, losing fidelity at each hop. `MustContainRule` becomes a solver constraint directly.

### 4.5 Acceptance

`ayurveda-data/tests/plan-validity-properties.json` — 36 properties, 23 hard invariants, 10 profiles. Property-based rather than output goldens, deliberately: a golden plan breaks on every weight change and tells us nothing, while these hold regardless of which foods get picked. No device required.

**Y1 is the property that matters most.** It runs the solver twice — once with a dosha imbalance set, once cleared — and asserts the first is measurably more pacifying. A solver that ignores the dravya data passes every other property and shows zero delta here. That delta is the whole reason MP-5 exists.

**F1/F2** require an infeasible request to be *reported*, naming the failing constraint. Emitting a partial plan, or quietly relaxing an allergen to find a solution, is the worst available behaviour.

### 4.6 Constraints on implementation

Extract the solver to its **own file**. `USDAWeeklyMealPlanner.swift` was 4,160 lines and the handbook flags this codebase as near the Swift type-checker budget; MP-2 and MP-3 shrank it and MP-5 must not regrow it.

Ships **behind a feature flag, off by default**, until the vaidya review completes — MP-5 makes dosha scoring user-visible for the first time while content is still `qualityState: aiDraft`.

---

## 5. MP-6 — batched narration

One model call generating all descriptive titles for a plan, given resolved dish names. Template fallback when the model is unavailable. Deletes `aiPolishTitle` and `diversifyDescriptiveTitlesIfNeeded`.

The narrator never chooses food, never computes a number, and never sees the catalogue — it receives finished facts and writes sentences. That is what makes a weak model safe here: it can phrase things badly, but it cannot make the plan wrong.

---

## 6. Risks

**Y1 coming back flat** is the outcome to watch. It would mean a well-engineered constraint solver that knows nothing about Ayurveda, leaving 714 dravyas unused.

**Tier composition** (property Y6, report-only): if the solver selects overwhelmingly estimated-tier foods, the Ayurvedic scoring is running on the weakest third of the data.

**Deferred device validation** still stands — MP-1's matrix, MP-2's twenty-food error table, MP-3's runtime counts. Every call-count claim in this document is measured against a static estimate until that lands.
