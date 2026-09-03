# MP-6 — Batched meal-plan narration

Date: 2026-07-27
Branch: `ayurveda-app`
Integrated Phase-1 base: `971ec92`
Implementation commits: `6aa0b84`, `0769a40`, `a91a9a0`

## Headline

**The model-available seven-day planner path is now exactly 2 model calls: one
MP-4 intent parse and one MP-6 narration batch.** This replaces the original
static estimate of 135–260 calls and the immediately preceding 10–21
per-title narration calls.

The number is proven with the production coordinators and MP-1 telemetry, but
it remains a **host/static estimate until the outstanding MP-1 physical-device
matrix runs**. It must not be presented as device runtime evidence.

The narrator cannot choose food or calculate plan values. It receives only the
solver's finished day/slot keys, resolved food names, kcal, protein, rasa,
thermal character, and agni. The deterministic template is the complete
shipping fallback when Apple Intelligence is absent or unavailable.

## Implementation

- `MealPlanNarration.swift` is Foundation-only. It defines the finished-fact
  transport, deterministic template narrator, exact day/slot validation,
  wall-clock cutoff, and all-or-nothing fallback.
- `MealPlanNarrator+FoundationModels.swift` isolates Foundation Models behind
  one `@Generable` response containing the complete title array. There is one
  `LanguageModelSession.respond` call for the whole plan.
- `MP5PlannerAdapter` now returns the unchanged solved preview plus narration
  facts derived from the same resolved components and exact solver totals.
- `fillPlanDetails` applies titles only after deterministic assembly and only
  by validated `(day, slotIndex)` keys. A count, duplicate-key, missing-key,
  extra-key, or empty-title mismatch applies templates to the entire plan.
- The prompt forbids invented foods, weights, figures, or properties; disease
  treatment/prevention language; and presenting Ayurveda as medical fact. It
  requires the “Traditionally considered” register and retains
  `qualityState: aiDraft` pending expert review.
- `aiPolishTitle` and `diversifyDescriptiveTitlesIfNeeded` are deleted.

## Model-call topology

Only these two call sites survive on the active planner path:

| Order | Function / source | Role | Calls per plan |
|---:|---|---|---:|
| 1 | `interpretIntent` — `USDAWeeklyMealPlanner.swift:1220` | One typed MP-4 interpretation of all prompts | 1 |
| 2 | `generateTitles` — `MealPlanNarrator+FoundationModels.swift:110` | One indexed title batch for all solved meals | 1 |
| | **Total, seven days** | | **2** |

The dead legacy call sites enumerated in `REPORT-INT2.md` remain unreachable;
MP-6 did not revive them. In particular, the obsolete variant path remains
dead. The MP-1 telemetry harness records:

- 1 day: `mealPlanNarration | 1 session | 1 respond`
- 3 days: `mealPlanNarration | 1 session | 1 respond`
- 7 days: `mealPlanNarration | 1 session | 1 respond`
- 7-day end to end: `mealPlanIntentParse` 1 + `mealPlanNarration` 1 =
  **2 sessions / 2 responds / 0 failed**

## Gate ledger

| Gate | Result |
|---|---|
| MP6-G1 Debug + Release, MP-5 flag on/off | **PASS** — final arm64 iOS 26.2 simulator Debug and optimized Release builds succeeded. Both flag modes share this binary and remain exercised by the solver properties; no new warning originates in MP-6. |
| MP6-G2 full suite | **PASS — 123/123** in 65.934s = 116 integrated baseline + 7 MP-6 tests |
| MP6-G3 search goldens | **PASS — 25/25 legacy + 2/2 safety exact** |
| MP6-G4 MP-5 hard properties | **PASS — 23/23**; Y1 remains non-flat at +0.5209 and P10 still names allergen infeasibility |
| MP6-G5 narration calls | **PASS — exactly 1** at 1, 3, and 7 days by MP-1 telemetry |
| MP6-G6 template fallback | **PASS — 9/9 meals** in the three-day sample below; no empty or malformed copy |
| MP6-G7 fallback linkage | **PASS** — the production Foundation-only template plus harness binary contains no `FoundationModels` import or dynamic linkage (`otool -L`) |
| MP6-G8 title mismatch | **PASS** — one deliberately short response produced 9/9 templates with reason `title count or index mismatch`; no generated title was mis-assigned |
| MP6-G9 determinism | **PASS** — 100 repeated seven-day template runs were byte-for-byte equal |
| MP6-G10 deletions | **PASS** — zero Swift references to `aiPolishTitle` or `diversifyDescriptiveTitlesIfNeeded` |
| MP6-G11 total model calls | **PASS — 2** (one parse + one narration), down from the original 135–260 static estimate; device measurement remains deferred |
| MP6-G12 launch/fresh/size | **PASS** — final median 1.615610s; fresh install zero insert/update and no rebuild; largest tracked file 82,726,160 bytes |
| Validator | **PASS** — 714 dravyas, 1,500 recipes, 12,601/12,601 USDA rows resolved |
| Resolution corpora | **PASS** — training 59/59; held-out 44/48; no wrong-confident movement |

The timeout fixture also passes: a response beyond the budget returns a
complete three-meal template set with reason
`narration exceeded wall-clock budget`.

## Three-day deterministic fallback sample

The title text below is verbatim production-template output:

```text
Day 1 · Breakfast: Oat porridge and Stewed apple — 412 kcal and 15.4 g protein. Tastes present: astringent and sweet. Traditionally considered warming for balanced agni.
Day 1 · Lunch: Mung dal kitchari and Cucumber raita — 638 kcal and 25.8 g protein. Tastes present: astringent, salty, and sweet. Traditionally considered mixed for balanced agni.
Day 1 · Dinner: Pumpkin soup and Whole-wheat flatbread — 521 kcal and 19.6 g protein. Tastes present: pungent and sweet. Traditionally considered cooling for balanced agni.
Day 2 · Breakfast: Oat porridge and Stewed apple — 419 kcal and 15.4 g protein. Tastes present: astringent and sweet. Traditionally considered warming for slow agni.
Day 2 · Lunch: Mung dal kitchari and Cucumber raita — 645 kcal and 25.8 g protein. Tastes present: astringent, salty, and sweet. Traditionally considered mixed for slow agni.
Day 2 · Dinner: Pumpkin soup and Whole-wheat flatbread — 528 kcal and 19.6 g protein. Tastes present: pungent and sweet. Traditionally considered cooling for slow agni.
Day 3 · Breakfast: Oat porridge and Stewed apple — 426 kcal and 15.4 g protein. Tastes present: astringent and sweet. Traditionally considered warming for balanced agni.
Day 3 · Lunch: Mung dal kitchari and Cucumber raita — 652 kcal and 25.8 g protein. Tastes present: astringent, salty, and sweet. Traditionally considered mixed for balanced agni.
Day 3 · Dinner: Pumpkin soup and Whole-wheat flatbread — 535 kcal and 19.6 g protein. Tastes present: pungent and sweet. Traditionally considered cooling for balanced agni.
```

Every number and food name in that copy is supplied by the solved facts; the
template does not derive or invent one.

## Final same-session cold launch

Method matches the accepted INT-2/MP-5 method:

- retained iOS 26.2 simulator
  `AF937668-3BFE-45E8-B42A-A76B914038DD`;
- A = installed INT-2 Phase-1 app (`971ec92`), B = final MP-6 Debug app;
- separate bundle IDs and prepared containers, identical permissions;
- no Xcode/xcodebuild/compiler, Maestro, CI, Spotlight indexing, or Blender;
  Chrome, Claude, and its idle VM were temporarily suspended and immediately
  resumed; Codex and ordinary macOS/CoreSimulator services remained;
- strict AB repeated ten times; every process was terminated before launch;
- host monotonic time immediately before `simctl launch --console-pty` to
  `WE6_PROFILE|first-interactive-frame|...`.

| Pair | A Phase 1 | B MP-6 | B − A |
|---:|---:|---:|---:|
| 1 | 1.881218s | 1.631842s | −0.249377s |
| 2 | 1.691786s | 1.661472s | −0.030314s |
| 3 | 1.583785s | 1.598721s | +0.014936s |
| 4 | 1.592394s | 1.572915s | −0.019479s |
| 5 | 1.619203s | 1.555361s | −0.063841s |
| 6 | 1.490538s | 1.587745s | +0.097207s |
| 7 | 1.640341s | 1.755646s | +0.115305s |
| 8 | 1.942653s | 1.693985s | −0.248668s |
| 9 | 1.609221s | 1.599378s | −0.009842s |
| 10 | 1.626801s | 1.753245s | +0.126444s |

| Series | N | Median | IQR (Q1–Q3) | Min | Max | Population stddev |
|---|---:|---:|---:|---:|---:|---:|
| A Phase 1 | 10 | **1.623002s** | 0.082324s (1.596601–1.678925) | 1.490538s | 1.942653s | 0.131932s |
| B MP-6 | 10 | **1.615610s** | 0.095368s (1.590489–1.685857) | 1.555361s | 1.755646s | 0.068832s |
| Paired delta | 10 | **−0.014661s** | 0.132099s (−0.055460–0.076639) | −0.249377s | +0.126444s | 0.126999s |

Both medians are below the 1.650s profiling-paydown trigger and the 1.700s
hard ceiling. The paired median is smaller than either IQR, so a launch change
is not resolvable from this sample. Both applications logged a version-5
14,484-row index skip on every measured launch.

## Fresh install, artifacts, and source size

Final fresh-install evidence:

- `Ayurveda v5 preseed stamp verified; no inserts or updates.`
- `SearchIndexStore: Index is up-to-date (version: 5, DB: 14484). Skipping rebuild.`

MP-6 changes no seed, rules, concepts, preseed, search, lifecycle, claims, or
ranking artifact. Final SHAs remain:

| Artifact | SHA-256 |
|---|---|
| `ayurveda_seed.json.gz` | `886c6a3908b9661ae85223b13cc353326a93ef2ac552129b6a60e529e481872e` |
| `ayurveda_rules.json` | `e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c` |
| `food_concepts.json.gz` | `fe200fe30b1a25dfd091fef6099fe5c34844d8460262ec0ab87986a6399dd7b1` |
| preseed `part-aa` | `99a977616c554f3e67d683de045b11bf2a2dd6567f41702d71cc5788f42bb817` |
| preseed `part-ab` | `f6b0cd508ccd2a5d2e343ce87b166e6f72df75b3b24f5eda528d08cb1e0b291c` |

The integrated planner file is **3,686 → 3,627 lines (−59)**. The two isolated
narration files are 237 Foundation-only lines and 145 Foundation Models adapter
lines. This keeps the model boundary visible instead of growing the planner
again.

## Deferred evidence

The existing `DEFERRED-VALIDATION.md` device work remains pending. In
particular, the founder-facing 2-call headline must be confirmed by the MP-1
physical-device matrix before it is called a runtime device result. No
additional implementation is authorized by this report.
