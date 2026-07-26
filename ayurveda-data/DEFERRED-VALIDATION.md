# Deferred physical-device validation

**Created:** 2026-07-26 during INT-1

**Scope:** MP-1 through MP-3 after integration into `ayurveda-app`

The founder authorized integration before the remaining physical-device
measurements. These gates are deferred, not waived. Simulator/host evidence from
INT-1 does not replace any item below.

## MP-1 — meal-planner telemetry

| Deferred evidence | What it proves | Required comparison | Why a physical device is required |
|---|---|---|---|
| Nine-run device matrix: three prompts × 1/3/7 days | Captures real planner stage timing, model-session/respond counts, response latency, resolution counts, and plan-size scaling across the authorized prompt/day matrix. | Run the same matrix at `d0dfc38` with telemetry enabled; use `d393bda` for any baseline counter/timing comparison specified by MP-1. | The planner's Apple on-device model path and its hardware/model availability are not represented by the simulator. |
| G6 plan-identical diff | Proves the telemetry-only MP-1 commit does not alter generated plan content for the same prompts and deterministic setup. | Compare `d393bda` (pre-telemetry) with `d0dfc38` (MP-1 telemetry), preserving prompts, profile, model availability, and run setup. | Both revisions must execute the real on-device generation path; simulator fallback/unavailability cannot establish plan equivalence. |
| G8 device launch | Measures the isolated launch effect of telemetry instrumentation rather than the later integrated stack. | Same-session A/B between `d393bda` and `d0dfc38`. | It is explicitly the physical-device launch gate; simulator INT1-G7 measures the integrated product and is not a substitute. |

The MP-1 G6 measurement window remains open after INT-1: both `d393bda` and
`d0dfc38` remain permanent commits in the merged history. Merging does not
erase or squash either endpoint.

## MP-2 — nutrition truth

| Deferred evidence | What it proves | Required comparison | Why a physical device is required |
|---|---|---|---|
| Twenty-food AI-vs-USDA macro error table | Quantifies the macro error removed when AI-invented meal macros are replaced by resolved FoodItem/USDA values, using actual generated foods and portions. | Compare the MP-1 endpoint `d0dfc38` with MP-2 `161689e` under the same twenty-food input set and device profile. | The “AI” side requires the actual on-device model output; simulator-only fixtures can prove arithmetic but cannot measure model error. |
| G7 runtime telemetry counts | Confirms real-plan resolved/unresolved component counts, USDA nutrient coverage, and adjustment-stage behavior after MP-2. | Measure `161689e`, with `d0dfc38` as the pre-MP-2 behavioral reference where the task calls for a delta. | Counts must come from genuine on-device planner runs; static tests exercise deterministic fixtures only. |

## MP-3 — deterministic food resolution

| Deferred evidence | What it proves | Required comparison | Why a physical device is required |
|---|---|---|---|
| G8 runtime zero-model-call confirmation | Confirms that production food resolution invokes no model session/respond call during genuine meal-plan generation, while the surrounding generation pipeline still operates normally. | Compare MP-2 `161689e` with MP-3 `37552c0`; confirm the final MP-3c endpoint `247dfa8` retains the zero-call behavior. | The simulator/static harness proves the resolver contains no model call, but only physical-device telemetry can observe the complete on-device runtime path. |

## Completion rule

Record raw device logs, hardware/OS/model availability, prompts, profile inputs,
and exact commit endpoints. Update the relevant MP report and this registry when
each item is completed; do not silently convert a deferred item into “passed.”
