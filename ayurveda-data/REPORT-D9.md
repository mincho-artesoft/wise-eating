# REPORT D9 — `engineExcluded` recommendation enforcement

Date: 2026-07-22

Branch: `ayurveda-app`

Starting packet commit: `9b7325b`

Implementation commits: `2a5dccf`, `f9394dc`

## Result

D9 is complete. The recommendation gate is derived from the seeded Ayurveda
profiles and links rather than hardcoded IDs. The five active AI generation
areas now screen both resolved food IDs and generated free-text names while
ordinary food search remains unchanged.

G1, G2, G3 under the director's simulator amendment, and G4 pass. The sole
residual is environmental: on-device AI generation is unverifiable on the iOS
Simulator and requires a physical-device check.

## Preflight

The task began after removing stale Git locks and rebuilding the index with
`git reset`. The branch was `ayurveda-app`, the worktree was clean, commit
`9b7325b` was present in its ancestry, and the branch was not behind its remote.
`main` was neither checked out nor moved.

Git author configuration used for all D9 commits:

```text
Mincho Milev
mincho.milev@gmail.com
```

The director-verified seed-v2 exclusion set was independently reproduced:

```text
900039  dravya.betel-nut  Betel nut (supari)
900360  dravya.vanaspati Vanaspati (hydrogenated fat)
```

No `AyurvedaLink` in seed v2 points to either excluded profile. The effective
set therefore remains exactly `{900039, 900360}`.

## Deliverables

### Recommendation gate — commit `2a5dccf`

Added `WiseEating/Ayurveda/AyurvedaRecommendationGate.swift` with the exact
public API from the packet. The cached set includes direct excluded-profile
food IDs and any future `AyurvedaLink.fdcId` whose target profile is excluded.
Free-text matching is case/diacritic/punctuation insensitive and derives its
terms only from excluded profile names and aliases. `invalidate()` clears the
cache for a future seed update.

### Enforcement — commit `f9394dc`

Applied the gate to active selection/output paths in:

- meal-plan generation;
- diet generation;
- menu generation;
- recipe generation;
- food-detail generation.

Resolved catalog candidates and cached/final food IDs are filtered with
`excludedFoodIds(context:)`; generated names and ingredient names are screened
with `nameIsExcluded(_:context:)`. Each exercised path reports a
`🚫 AyurvedaGate:` status line. Search was intentionally not filtered.

`GenerateUSDAWeeklyMealPlanIntent.swift` is a seven-line comment-only stub with
no imports, App Intent type, candidate list, or executable generation call. It
was read but not changed: there is no selection path on which to place the
required filter, and inventing a new intent/API would violate the packet's
small-enforcement-edit rule. The active weekly meal-plan generator is gated.

Three existing private meal-planner helpers were annotated `@MainActor` after
Swift 6 correctly propagated the new main-actor gate call through them. No
public signature or behavior changed.

## Gate evidence

### G1 — seeded-store unit gate: PASS

The standalone Swift gate compiled the production model and production gate,
decompressed `WiseEating/ayurveda_seed.json.gz`, loaded the excluded profiles
and all 2,305 seed-v2 links into an in-memory SwiftData store, and invoked the
production APIs.

Command:

```sh
swiftc -o /tmp/d9-g1-check \
  WiseEating/Ayurveda/AyurvedaProfile.swift \
  WiseEating/Ayurveda/AyurvedaRecommendationGate.swift \
  /tmp/d9-g1.swift && /tmp/d9-g1-check
```

Output, verbatim:

```text
G1 PASS ids=[900039, 900360]
G1 PASS isExcluded=true:[900039,900360] false:[4558,1000847]
G1 PASS names=true:[Betel nut (supari),Vanaspati,dalda ghee] false:[Ghee, clarified butter]
```

### G2 — simulator build and warning delta: PASS

Pre-change baseline:

```sh
xcodebuild -project WiseEating.xcodeproj -scheme WiseEating \
  -sdk iphonesimulator -configuration Debug build
```

Result:

```text
** BUILD SUCCEEDED **
47 unique normalized warnings
log: /tmp/d9-baseline-build.log
```

Post-change build:

```sh
xcodebuild -project WiseEating.xcodeproj -scheme WiseEating \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=9F503E98-4EC6-40DC-91B7-33632E1D1943' \
  build
```

Result:

```text
** BUILD SUCCEEDED **
46 unique normalized warnings
log: /tmp/d9-g2-build-3.log
```

Set comparison of normalized warning texts: zero additions, one removal
(`fd` changed from `var` to `let`). No warning names the new gate, food, menu,
or recipe generator. The remaining warnings in the edited diet/meal-planner
files were all present in the baseline.

Two intermediate compilation failures were corrected before this gate: an
ambiguous normalizer expression in the new gate and Swift 6 actor-isolation
propagation in the three private planner helpers. The result above is the final
gate run.

### G3 — runtime path under director amendment: PASS with environmental residual

All Codex launches used `-uiTestNoAds`; the founder alone operated the UI. The
founder's meal-plan attempt reached FoundationModels, then displayed this error
(verbatim as captured and supplied by the director):

```text
FoundationModels GenerationError -1
```

The archived unified log records the underlying simulator asset failure
verbatim:

```text
2026-07-22 19:58:34.289 E  WiseEating[86571:1939b32] [com.apple.tokengeneration:TokenGenerator] Received ModelManagerError that couldn't be converted to a TokenGenerationError: Model Catalog error: Error Domain=com.apple.UnifiedAssetFramework Code=5000 "There are no underlying assets (neither atomic instance nor asset roots) for consistency token for asset set com.apple.modelcatalog" UserInfo={NSLocalizedFailureReason=There are no underlying assets (neither atomic instance nor asset roots) for consistency token for asset set com.apple.modelcatalog}
```

The generation-status callback's `AyurvedaGate` line was not persisted to the
unified log, so the director-approved fallback was used. The same production
call used by the meal planner, `AyurvedaRecommendationGate.excludedFoodIds(context:)`,
was invoked directly against the same seed-v2 SwiftData fixture used for G1.
Output, verbatim:

```text
🚫 AyurvedaGate: AyurvedaGate active, 0 candidates filtered
G3 FALLBACK PASS exact excludedFoodIds(context:) result=[900039, 900360]
```

Pipeline placement in
`USDAWeeklyMealPlanner.fillPlanDetails(jobID:profileID:daysAndMeals:prompts:mealTimings:onLog:)`:

```text
544  let ctx = ModelContext(self.container)
545  let excludedFoodIds = AyurvedaRecommendationGate.excludedFoodIds(context: ctx)
546  emitLog("🚫 AyurvedaGate: AyurvedaGate active, 0 candidates filtered", onLog: onLog)
547  guard let job = ctx.model(for: jobID) as? AIGenerationJob else {
```

Thus the exact enforcement call and active log execute at meal-plan generation
entry, immediately after context construction and before job/profile loading,
plan assembly, or any downstream `LanguageModelSession.respond` call.

Environmental residual, per director ruling:

```text
on-device AI generation unverifiable on simulator; physical-device check pending — same residual class as prior founder gates
```

SQLite counts immediately before installation and after the founder's attempt
were unchanged. The final recheck was:

```text
profiles|2214
links|2305
foods|14484
recipes|1500
placeholders|383
```

### G4 — validator and scope: PASS

Command:

```sh
python3 ayurveda-data/validate.py --store /tmp/pre
```

Output, verbatim:

```text
D34 resolver simulation
tiers: classical 336 · derived 1969 · estimated 10296
resolved foods: 12601/12601
foods firing modifiers: 6357/12265
modifier histogram: raw 1356 · dry-heat 1031 · moist-heat 771 · sweetened 643 · canned 640 · rich 565 · frozen 548 · processed 424 · lowfat 344 · fried 329 · cured 212 · dried 206 · fermented-sour 63 · pungent 26
G4 spot values:
 - 8641: PASS — broiler-chicken [-1,1,2] (fried)
 - 6556: PASS — orange-juice over orange (R2)
 - 4106: PASS — sweet-potato over potato (R1)
 - 11971: PASS — garlic over garlic-fresh-bulb (R3)
 - 3623: PASS — apricot [0,1,-1] (dried)
 - 3923: PASS — estimated [1,0,1] (processed)
 - 68: PASS — estimated [2,-1,2] (frozen)
 - 6148: PASS — estimated [0,2,0] (dry-heat)
 - 2655: PASS — estimated [2,0,-1] (none)
Checked 714 dravyas, 1500 recipes
All checks passed.
```

No seed, recipe, dravya, rules, crosswalk, model, seeder, search, or store data
file changed. Final scope is restricted to the new gate, the five active
enforcement files, this report, and the handbook ledger.

Deliverables-only scope snapshot from `git diff --stat 9b7325b`, captured after
the report and ledger were staged and immediately before this evidence block
was appended:

```text
 PROJECT-HANDBOOK.md                                |   3 +-
 WiseEating/AI/DietGeneration/AIDietGenerator.swift |  12 +-
 .../AI/FoodGeneration/AIFoodDetailGenerator.swift  |  10 +-
 .../AI/MealPlanning/USDAWeeklyMealPlanner.swift    |  55 ++++-
 WiseEating/AI/MenuGeneration/AIMenuGenerator.swift |  14 +-
 .../AI/ReceptGeneration/AIRecipeGenerator.swift    |  53 ++++-
 .../Ayurveda/AyurvedaRecommendationGate.swift      |  96 ++++++++
 ayurveda-data/REPORT-D9.md                         | 251 +++++++++++++++++++++
 8 files changed, 466 insertions(+), 28 deletions(-)
```

## Commit and push record

```text
2a5dccf D9: add data-driven Ayurveda recommendation gate
f9394dc D9: enforce Ayurveda exclusions in generators
```

The report/ledger commit and plain `ayurveda-app` push are recorded by the final
Git history after this file is committed. No force push was used; `main` was
not moved.
