# TASK D9 — Engine enforcement of engineExcluded (design + packet)
Executor: Codex on the founder's Mac. Protocol: founder is the hands for any UI
step; you never navigate the simulator. Stop-and-report on anything ambiguous.
Never force-push; never touch main. Update PROJECT-HANDBOOK.md ledger at the end.

## Why
Fixed decision #4: betel nut and vanaspati are displayed with warnings but must
NEVER be recommended. Today `engineExcluded` exists only as data + a display
banner; no generation path consults it. Director-verified current exclusion set
from seed v2: **foodIds {900039 (dravya.betel-nut), 900360 (dravya.vanaspati)}**
— both placeholders; no AyurvedaLink points to them; no recipes are excluded.
The gate must be set-driven (not hardcoded ids) so future exclusions inherit
enforcement automatically.

## Design (normative)

New file `Ayura/Ayurveda/AyurvedaRecommendationGate.swift`:

```swift
@MainActor
public enum AyurvedaRecommendationGate {
    /// All foodIds that must never be recommended: direct profiles with
    /// engineExcluded == true, plus any fdcIds whose AyurvedaLink resolves to
    /// an excluded dravya profile. Cached after first computation; call
    /// invalidate() if profiles change (user edits cannot set engineExcluded,
    /// so seeding is the only writer).
    public static func excludedFoodIds(context: ModelContext) -> Set<Int>
    public static func isExcluded(foodId: Int, context: ModelContext) -> Bool
    public static func invalidate()
    /// Case-insensitive name screen for AI-generated free text (ingredient
    /// names that don't map to a foodId): matches the excluded profiles'
    /// names + aliases ("betel nut", "areca nut", "supari", "vanaspati",
    /// "dalda", "vegetable ghee"). Built from profile data, not literals.
    public static func nameIsExcluded(_ name: String, context: ModelContext) -> Bool
}
```

Enforcement points (every place the app selects, generates, or proposes foods):
1. `Ayura/AI/MealPlanning/*` — filter candidate FoodItems through
   `excludedFoodIds` before plan assembly.
2. `Ayura/AI/DietGeneration/*`, `MenuGeneration/*`, `ReceptGeneration/*`,
   `FoodGeneration/*` — (a) filter any catalog candidates by foodId; (b) for
   AI free-text output, screen generated ingredient/food names with
   `nameIsExcluded` — drop the item and log `🚫 AyurvedaGate:` line.
3. `GenerateUSDAWeeklyMealPlanIntent.swift` — same foodId filter.
4. Search is NOT filtered (decision 3: UI never hides; users may always find
   and view these foods — only proactive recommendation is blocked).

Implementation rules: small helpers, no signature changes to existing public
APIs where avoidable; each enforcement point is a 1–3 line filter call, not a
redesign. Type-checker budget rules apply.

## Gates
- G1 (unit, swiftc or test target): excludedFoodIds == {900039, 900360} against
  the seeded store; isExcluded true for both, false for 4558 (ghee) and
  1000847; nameIsExcluded true for "Betel nut (supari)", "Vanaspati", "dalda
  ghee", false for "Ghee, clarified butter".
- G2: build PASS, zero new warnings vs baseline.
- G3 (runtime, founder hands if UI needed): trigger one AI meal-plan/menu
  generation; verify via the 🚫 log (absence of exclusions is fine — the gate
  line "AyurvedaGate active, N candidates filtered" must appear at least once
  per generation path exercised). SQLite untouched (no data changes in D9).
- G4: validator green; git diff proves only authorized files changed
  (new gate file + the enforcement-point files + report + handbook).

## Deliverables
Gate file, enforcement edits, REPORT-D9.md (per-gate evidence, verbatim logs,
diff stat), PROJECT-HANDBOOK.md ledger row update, commit per deliverable
group, push ayurveda-app.
