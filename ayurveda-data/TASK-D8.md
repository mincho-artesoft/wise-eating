# TASK-D8 — Ayurveda UI: detail section, dosha bars, tier labels, user editability (executor packet)

*Dispatched by director per `DESIGN-D8.md` (normative — read it first, follow it
exactly; U1–U12 and the §Simulated reference numbers are binding). Repo:
wise-eating, branch `ayurveda-app`. Do not push. You are on the founder's Mac —
build/simulator gates are yours to run. Touch only the files listed below.
**Stop-and-report rule:** any failed gate, missing anchor, or unexpected state →
capture verbatim, stop, do not improvise, do not tune constants or expected
numbers to force a gate.*

## Deliverables

| # | File | Action |
|---|---|---|
| 1 | `Ayura/Ayurveda/AyurvedaDisplayMath.swift` | create (DESIGN U4 — Foundation-only) |
| 2 | `Ayura/Ayurveda/Views/AyurvedaDisplay.swift` | create (U3) |
| 3 | `Ayura/Ayurveda/Views/AyurvedaSectionView.swift` | create (U1/U2/U5/U8) |
| 4 | `Ayura/Ayurveda/Views/DoshaBarsView.swift` | create (U6) |
| 5 | `Ayura/Ayurveda/Views/AyurvedaChipsView.swift` | create (U7) |
| 6 | `Ayura/Ayurveda/Views/AyurvedaEditorSection.swift` | create (U10) |
| 7 | `Ayura/Ayurveda/AyurvedaResolver.swift` | edit (U9.3 `.user` case only) |
| 8 | `Ayura/Food/Views/FoodItemDetailView.swift` | edit (U1: one section var + one VStack entry) |
| 9 | `Ayura/Food/Views/FoodItemEditorView.swift` | edit (U9/U10: `@State` form + `showAyurveda`, section after `otherSection`, prefill task, one call in `save()`) |
| 10 | `ayurveda-data/tools/d8_math_check.swift` | create (G2 harness) |
| 11 | `ayurveda-data/REPORT-D8.md` | create (format below) |

No other file may change — in particular NOT `FoodItem.swift`,
`AyurvedaProfile.swift`, `AyurvedaRules.swift`, `AyurvedaSeeder.swift`,
`SeedManager.swift`, any JSON/seed/store file, `validate.py`.
`git diff --stat` in the report must show exactly deliverables 1–10 (+11).

## Implementation notes (bindings to DESIGN)

1. **Anchors.** Detail: insert `ayurvedaSection` between `phSection` and
   `ingredientsSection` in the sections VStack. Editor: append `ayurvedaSection`
   after `otherSection` in `mainForm`'s section list; use the existing
   `collapsibleHeader("Ayurveda", isExpanded: $showAyurveda)` +
   `.padding().glassCardStyle(cornerRadius: 20)` card pattern. If an anchor named
   here does not match the file, stop and report.
2. **Style.** Match surrounding code: `effectManager.currentGlobalAccentColor`,
   `Color(hex:)`, `CustomFlowLayout`, raw English string literals, no
   force-unwraps, small sub-views + extracted handlers (handbook §4 type-checker
   budget — if the compiler complains about expression complexity, split views
   mechanically, never inline more).
3. **Resolver edit is additive:** new enum case + one `kind == "user"` branch +
   confidence arm. Do not reorder existing lookup logic.
4. **Save hook:** in `save()`, after item fields are assigned and before
   `try ctx.save()`: `AyurvedaUserProfileStore.upsert(form: ayurForm, for: item, context: ctx)`
   implementing U10 semantics (create iff `!form.isEmpty`, update if exists).
5. **Colors (verbatim):** pacify `34A853`, aggravate `E8710A`; % segments Vata
   `8E7CC3`, Pitta `E06666`, Kapha `6AA84F`; tier chips Classical `34A853`,
   Derived `4A86E8`, Estimated `FCC934`, Recipe `9C6ADE`, User `999999`.

## Gates

**G1 — scope.** `git status` clean except deliverables; `git diff --stat` lists
exactly files 1–11.

**G2 — display math (director-simulated; deviation means your formula differs
from DESIGN U4 — stop and report):**

```
swiftc -o /tmp/d8check Ayura/Ayurveda/AyurvedaDisplayMath.swift ayurveda-data/tools/d8_math_check.swift && /tmp/d8check
```

must print `D8 MATH CHECK: 31/31 PASS` — the 31 assertions are exactly the
§Simulated reference numbers tables (10 percentage vectors, 7 tier labels,
5 effect labels, 5 value strings, 4 bar fractions), hardcoded in the harness.

**G3 — build.** `xcodebuild -project Ayura.xcodeproj -scheme Ayura
-destination 'platform=iOS Simulator,name=iPhone 16' build` succeeds; zero new
warnings vs. a pre-change baseline build (record both warning counts).

**G4 — runtime spot checks (simulator, screenshot each; attach filenames in
report).** For every row of DESIGN §Runtime spot foods: open the food's detail
view and verify tier chip text, bar values (V/P/K signs and magnitudes), and
listed chips/banner. Additionally toggle `%` on fdcId 2655 and verify segments
57/29/14. All nine rows must PASS.

**G5 — editor round-trip.** Create food "D8 Test Ghee Rice" (any serving weight
> 0); set Vata −1 / Pitta 0 / Kapha +1, rasa {sweet}, virya heating, gunas
{oily, heavy}; save. Verify: detail view shows tier **User** with exactly those
bars/chips; re-open editor → form prefilled identically; edit Kapha to +2, save,
detail updates; relaunch app → values persist and
`AyurvedaProfile` count with id prefix `user.` == 1. Total seeded counts
unchanged: profiles 2,214 (+1 user = 2,215 total), links 2,305.

**G6 — data untouched.** `cat Ayura/preseeded_db.store.gz.part-aa
Ayura/preseeded_db.store.gz.part-ab > /tmp/pre.gz && gunzip -f /tmp/pre.gz`
then `python3 ayurveda-data/validate.py --store /tmp/pre` fully green;
`git diff` shows no change under `ayurveda-data/` except `tools/d8_math_check.swift`
and `REPORT-D8.md`, and no change to `Ayura/ayurveda_seed.json.gz` /
`ayurveda_rules.json`.

## REPORT-D8.md format

Sections: Summary · Gate results G1–G6 (each with evidence: command output,
warning counts, spot-check PASS/FAIL table with screenshot filenames, round-trip
log) · Files changed (`git diff --stat`) · Deviations (must be empty or
stop-and-report was triggered) · Open items for founder gate (visual approval of
bar/chip styling on device; dark/light theme sanity; VoiceOver labels smoke test).

Commit message: `D8: Ayurveda UI — detail section (signed dosha bars, tier
labels, chips, viruddha/exclusion warnings) + user-food editability (tier "user")`.
One commit per deliverable group is fine; do not push.
