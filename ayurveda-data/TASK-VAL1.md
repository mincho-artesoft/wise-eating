# TASK VAL-1 — close the deferred device measurements

Director packet · 2026-07-27 · branch `ayurveda-app`, base = `3a99bee`
Needs a physical device. An iPhone 16 Pro is sufficient for all of it.

---

## Why this is worth doing now

Every speed claim in `STATUS-meal-generation.md` carries the same caveat, and has since rev1: *"measured against a static estimate."* The headline number of this whole workstream — **~135–260 model calls reduced to 2** — is my reading of the source, not anyone's measurement. `DEFERRED-VALIDATION.md` has been open since INT-1 on 2026-07-26.

It is also the last work available that needs neither a vaidya nor an iPhone 15 Pro, so it fits exactly the window while imagery generates.

The full specification already exists in **`ayurveda-data/DEFERRED-VALIDATION.md`** — required comparisons, commit endpoints, and why each item cannot be satisfied by a simulator. Read that; this packet only adds ordering, gates and what the numbers are for.

---

## Order

### VAL-1a — MP-3: zero model calls during resolution

The cheapest and the most load-bearing. Compare `24ac931` → `fc2d835`, confirm `e7e9409` retains it.

**Gate:** during a genuine on-device 7-day generation, food resolution makes **zero** `LanguageModelSession` constructions and **zero** `respond()` calls, while the surrounding pipeline still runs normally. Report both counters, not just the resolution one — zero calls because the whole pipeline failed is not a pass.

### VAL-1b — MP-1: the nine-run device matrix

Three prompts × 1/3/7 days at `4b8307f` with telemetry on, `f46a107` for baseline.

**This produces the number that replaces the estimate.** Report actual session and `respond()` counts per run, stage timing, response latency, and how it scales with plan size.

**Gate:** the measured 7-day call count at the current tip is **exactly 2**. If it is not, that is a finding and everything downstream of it in STATUS is wrong — report and stop.

Also complete the two companion items in the registry: the **G6 plan-identical diff** (`f46a107` vs `4b8307f`, same prompts and profile — telemetry must not change plan content) and the **G8 launch A/B**, same-session, N≥10.

### VAL-1c — MP-2: the twenty-food AI-vs-USDA macro error table

Compare `4b8307f` → `24ac931` over the same twenty-food input set and profile.

This quantifies what was actually wrong with the thing we deleted. `aiFetchNutritionData` asked a 3B model for "typical nutritional values per 100 g" and those invented numbers **mutated gram weights**. We removed it on principle; this measures the error that removal took out. Report per-food AI value, USDA value, absolute and percentage error, and the aggregate.

Also the **G7 runtime telemetry counts**: resolved and unresolved component counts, USDA nutrient coverage, adjustment-stage behaviour.

---

## Rules

**Record the raw evidence**: device logs, hardware and OS, model availability, prompts, profile inputs, exact commit endpoints. The registry says so and it matters more than the summary.

**Never silently convert a deferred item to "passed."** If an item cannot be run, say why and leave it open. A deferred measurement honestly marked open is worth more than a plausible number.

**If a measured number contradicts a claim in STATUS or a REPORT, that is the finding.** Report it and stop rather than reconciling it. I would much rather learn the 2-call figure is wrong from you than from a user.

Update `DEFERRED-VALIDATION.md` and the relevant MP report as each item completes.

---

## Also available, lower priority

### MP-5b — solver tuning, behind a flag that is still off

Two known misses from MP-5, neither blocking:

- **N4, the protein objective** — diagnose and tune without weakening any hard property.
- **Y5, midday distribution** — three profiles produce an evening meal heavier than midday, inverting the intended pattern. Lunch-minus-dinner ranged min −0.100, mean +0.244, max +0.650.

**Constraint:** Y1 must stay within ±0.05 of **+1.550713**, P7/P8 must stay exactly 1,200/3,600 kcal, and all 30 G5 plans must still solve. Tuning that fixes N4 by degrading Y1 is not a fix. Report the before/after for every property you touch, not only the two being tuned.

---

## Not in this packet

**PERF-1** — still needs an iPhone 15 Pro; correctly recorded not-run.
**IMG-2** — separate packet, `TASK-IMG2.md`.
**Vaidya review** — `VAIDYA-REVIEW.md`, needs a practitioner.

---

## Protocol

One commit per sub-task, prefix `VAL-1a:` etc. Branch `ayurveda-app`, no force-push, no GitHub Actions, `main` untouched. Report every gate with its measured number. Stop and report on failure; never fix a gate by loosening it.

Out of scope, leave alone: `ayurveda-data/imagery/`, `ayurveda-data/tools/ref_resolve.py`, `style-reference.png`, and the gitignored `food_archive_1024.mp4`.
