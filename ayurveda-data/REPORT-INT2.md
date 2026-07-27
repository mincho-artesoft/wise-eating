# REPORT-INT2 — MP-4 + FC-1e/FC-2 + MP-5 integration

Date: 2026-07-27
Branch: `ayurveda-app`
Status: **PHASE 1 COMPLETE — all authorized host/simulator gates green**

## Outcome

The histories were merged in the founder-specified order without rebasing or
squashing:

1. `mp-5-solver` at `f87e46b`, producing merge commit `94cafc6`;
2. `mp-4-intent-parse` at `81dc2f6`, producing merge commit `cde5fbe`.

The merged planner performs MP-4's single typed interpretation call and then
passes the interpreted constraints, resolved inclusions, hard exclusions, and
structured placements into MP-5's deterministic solver. The MP-4 caveat is
copied onto the final MP-5 preview. Neither behavior was weakened.

## Conflict resolution

| File | Conflict | Resolution |
|---|---|---|
| `USDAWeeklyMealPlanner.swift` | Both branches changed `fillPlanDetails` | Kept MP-4 Checkpoint 1 (`interpretIntent`, cache, fallback, caveat), kept MP-5 Checkpoint 2 (`makePlannerExclusions`, structured placements, `MP5PlannerAdapter.solve`), and copied the MP-4 caveat onto the assembled preview. MP-5's 14 deleted repair/assembly functions stayed deleted. |
| `test_fc1_concepts.py` | MP-4 introduced the first planner consumer while FC-2 added other concept consumers | Reconciled the exact expected consumers: planner, adapter, and recipe generator; the planner retains exactly one canonical-alias lookup. |
| `test_mp2_nutrition.py` | Static Foundation Models site counts differed | Rebased the assertion on the merged source and preserved the nutrition-truth checks. |
| `test_mp3_resolution.py` | Static model-site and checkpoint boundaries differed | Preserved the model-free resolver assertions and moved the assembly boundary to MP-5's deterministic checkpoint. |

`build_seed.py` had no merge conflict. The seed and preseed artifacts did not
change because MP-4 and MP-5 add no seed projection.

## Test-count reconciliation

The merged suite is **116/116**.

| Lineage | Total | Reconciliation |
|---|---:|---|
| FC-1e integrated base | 98 | Shared base for both feature branches |
| MP-5 | 108 | 98 shared + 10 MP-5 |
| MP-4 | 103 | 95 earlier integrated base + 8 MP-4; those 95 contain the same 98-lineage tests before the later FC additions were merged |
| INT-2 combined | **116** | 98 shared + 10 MP-5 + 8 MP-4 |

The branch totals are intentionally not summed: they contain overlapping base
tests.

## Remaining model-call sites after the merge

This is the complete static list in the merged
`USDAWeeklyMealPlanner.swift`. “Dead” means the owning private function has
zero callers from the live planner.

| Session line / response line | Owning function | Purpose | Reachability and disposition |
|---|---|---|---|
| 985 / 1220 | `makeIntentSession` → `interpretIntent` | MP-4 typed whole-request interpretation | **LIVE; survives.** Exactly one call on an uncached generation. |
| 1352 / 1369 | nested `aiSplitSinglePrompt` in `aiSplitIntoAtomicPrompts` | Former per-prompt splitting | **DEAD after MP-4; no caller.** Not counted at runtime; deletion candidate outside INT-2 integration. |
| 1430 / 1458 | `aiExtractRequestedFoods` | Former separate food extraction | **DEAD after MP-4; no caller.** |
| 1546 / 1566 | `aiFixAtomsAndFoods` | Former reconciliation pass | **DEAD after MP-4; no caller.** |
| 1914 / 1986 | `aiInterpretUserPrompts` | Former per-atom interpretation | **DEAD after MP-4; no caller.** |
| 3052 / 3060 | `aiPolishTitle` | Former per-meal title polish | Runtime-dead through the obsolete polish pipeline; **must be deleted by MP-6**. |
| 3151 / 3176 | `aiGenerateVariantIdeas` | “Different types of X” name brainstorming | **DEAD; zero callers.** It is not an unexplained runtime call. Source cleanup is a separate follow-up. |
| — | `validateAndSelectBestVariants` at line 3214 | Database validation of generated variant names | **DEAD; zero callers and no model session of its own.** It cannot invoke `aiGenerateVariantIdeas`. |
| 3292 / 3312 | `aiGenerateVariants` | Former duplicate-meal repair | Called only from dead `polishConceptualPlan`; **runtime-dead**. |
| 3495 / 3530 | `aiBatchClassifyFoods` | Former AI portion-category classification | Called only by `aiApplyPortionClamping`, itself called only from dead `polishConceptualPlan`; **runtime-dead**. |

Before MP-6, the live end-to-end path therefore has one model call:
`mealPlanIntentParse`. The remaining runtime call expected to survive MP-6 is
that interpretation call; MP-6 adds one batched narrator call.

## Gate ledger

| Gate | Result |
|---|---|
| INT2-P1-G1 Debug + Release, flag on/off | **PASS** — generic arm64 iOS 26.2 simulator Debug and Release builds succeeded. The MP-5 flag-on/off paths are exercised by the property harness; no warning originates in the conflict resolution. |
| INT2-P1-G2 full suite | **PASS — 116/116** in 77.246s |
| INT2-P1-G3 search goldens | **PASS — 25/25 legacy + 2/2 safety exact** |
| INT2-P1-G4 validator | **PASS** — 714 dravyas, 1,500 recipes, 12,601/12,601 USDA resolution |
| INT2-P1-G5 resolution | **PASS** — training 59/59; held-out 44/48; zero wrong-confident matches; controls unresolved |
| INT2-P1-G6 MP-5 properties | **PASS — 23/23 hard**; Y1 remains +0.5209 and P10 names the allergen constraint |
| INT2-P1-G7 MP-4 interpretation | **PASS — one call at 1/3/6 prompts; fallback 10/10** |
| INT2-P1-G8 no-Apple-Intelligence fallback | **PASS** — simulator result: unavailable model, zero calls, deterministic vegan/3-day/peanut parse |
| INT2-P1-G9 determinism | **PASS** — two seed builds and two preseed builds are byte-identical; MP-5 D1/D2 also pass |
| INT2-P1-G10 fresh install | **PASS** — zero Ayurveda inserts/updates and no search-index rebuild |
| INT2-P1-G11 cold launch | **PASS — 1.437053s candidate median**, below both 1.650s paydown trigger and 1.700s ceiling |
| INT2-P1-G12 tracked files | **PASS — 1,004 tracked files; maximum 82,726,160 bytes**, below 90 MB split point |

## Deterministic artifacts

Two independent builds reproduced these exact shipped files:

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `ayurveda_seed.json.gz` | 1,438,588 | `886c6a3908b9661ae85223b13cc353326a93ef2ac552129b6a60e529e481872e` |
| `ayurveda_rules.json` | 21,151 | `e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c` |
| `food_concepts.json.gz` | 31,165 | `fe200fe30b1a25dfd091fef6099fe5c34844d8460262ec0ab87986a6399dd7b1` |
| preseed part `aa` | 73,400,320 | `99a977616c554f3e67d683de045b11bf2a2dd6567f41702d71cc5788f42bb817` |
| preseed part `ab` | 19,162,561 | `f6b0cd508ccd2a5d2e343ce87b166e6f72df75b3b24f5eda528d08cb1e0b291c` |

Both preseed builds audited 14,484 foods, 2,214 Ayurveda profiles, 2,305
Ayurveda links, 10,571 IngredientLinks owned by all 1,500 recipes, and a
version-5 14,484-row search cache.

Fresh-install evidence:

- `Ayurveda v5 preseed stamp verified; no inserts or updates.`
- `SearchIndexStore: Index is up-to-date (version: 5, DB: 14484). Skipping rebuild.`

## Same-session launch comparison

Method:

- retained iOS 26.2 simulator `WiseEating-WE2-Baseline`
  (`AF937668-3BFE-45E8-B42A-A76B914038DD`);
- A = `95da00f`; B = integrated Phase 1;
- separate bundle IDs and fresh containers, followed by untimed setup/warm
  launches;
- identical arm64 Debug settings, resources, and permissions;
- Blender had finished; Xcode/xcodebuild/compiler, Maestro, CI, and indexing
  were absent; Chrome and Claude were temporarily suspended and resumed after
  the series; Codex, CoreSimulator, WindowServer, and ordinary macOS services
  remained;
- strict AB repeated ten times; each process was terminated before launch;
- host monotonic time immediately before `simctl launch --console-pty` to the
  `WE6_PROFILE|first-interactive-frame|...` marker.

| Pair | A `95da00f` | B integrated | B − A |
|---:|---:|---:|---:|
| 1 | 1.468608s | 1.431701s | −0.036907s |
| 2 | 1.435928s | 1.454919s | +0.018992s |
| 3 | 1.434407s | 1.431851s | −0.002556s |
| 4 | 1.417243s | 1.442255s | +0.025012s |
| 5 | 1.424619s | 1.419099s | −0.005520s |
| 6 | 1.430323s | 1.427587s | −0.002735s |
| 7 | 1.433330s | 1.425772s | −0.007558s |
| 8 | 1.431096s | 1.472774s | +0.041678s |
| 9 | 1.474030s | 1.480676s | +0.006645s |
| 10 | 1.449919s | 1.468763s | +0.018843s |

| Series | N | Median | IQR (Q1–Q3) | Min | Max | Population stddev |
|---|---:|---:|---:|---:|---:|---:|
| A | 10 | **1.433869s** | 0.015905s (1.430516–1.446421) | 1.417243s | 1.474030s | 0.017591s |
| B | 10 | **1.437053s** | 0.036686s (1.428616–1.465302) | 1.419099s | 1.480676s | 0.020989s |
| Paired delta | 10 | **+0.002045s** | 0.023778s (−0.004824–0.018955) | −0.036907s | +0.041678s | 0.020673s |

The paired median is smaller than either series' IQR, so a regression is not
resolvable from this data.

Phase 2 proceeds with MP-6 on this green integrated base.
