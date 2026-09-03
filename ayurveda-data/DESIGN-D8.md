# D8 Design — Ayurveda UI (Director)

*Status: APPROVED FOR DISPATCH · 2026-07-22 · Design authority: PROJECT-HANDBOOK.md §6
D8 founder requirements (2026-07-22) + founder ratification of editability policy
U9 (option A) on 2026-07-22. Implementation: Codex packet `TASK-D8.md`.
Data layer: DESIGN-D6/DESIGN-D34 (unchanged — D8 is a pure consumer of
`AyurvedaResolver`).*

## Objective

First UI for the Ayurveda layer. Every one of the 14,484 FoodItems (12,601 USDA +
383 placeholders + 1,500 recipes) gets an **Ayurveda section in
`FoodItemDetailView`**, styled exactly like the existing nutrition sections:

- Dosha effects as **signed progress-bar rows** (V/P/K, −2…+2, center-zero
  diverging bars) with an **optional derived % view** (handbook decision 6:
  percentages derived in UI, never stored).
- **Tier label always visible** (handbook decision 2).
- Rasa / virya / vipaka / guna **chips**; **viruddha badges** (warn, don't block —
  decision 3); **engineExcluded red warning** (decision 4); aiDraft caption
  (decision 5, no medicinal claims).
- **Editability (founder-ratified policy)**: user-added foods get editable Ayurveda
  attributes in `FoodItemEditorView`, stored as an `AyurvedaProfile` with
  `kind = "user"` → tier label **User**. Catalog foods are read-only — already
  enforced structurally: the edit action only exists for `isUserAdded` items
  (`FoodItemListView.swift` swipe actions), and all seeded items (USDA, placeholders,
  recipes) carry `isUserAdded: false` (`AyurvedaSeeder.swift:38,66`,
  `SeedManager.swift:139`). No override machinery in D8.

Out of scope: recipe/menu editors (RecipeEditor path), copying resolved Ayurveda
into duplicated foods as prefill, deleting a user profile from the editor, seasons-
aware recommendations, dosha assessment, any change to seed/validator/data files,
any change to `FoodItem.swift`.

## UI reality (measured 2026-07-22, branch `ayurveda-app` @ `375f7de`)

| Fact | Where |
|---|---|
| Detail sections are `private var xSection: some View` entries in a `VStack(alignment:.leading, spacing:24)` | `FoodItemDetailView.swift:99-116`; order ends `…macrosSection; phSection; ingredientsSection; …` |
| Section card convention | `SectionView(title:){…}.padding().glassCardStyle(cornerRadius: 20)`; `SectionView` is **fileprivate** (`FoodItemDetailView.swift:676-690`): title `.font(.title2.weight(.semibold))` in `effectManager.currentGlobalAccentColor` |
| Nutrient-bar precedents | `MacroProportionBarView` (segmented capsule, height 12, hardcoded hex `4A86E8/FCC934/34A853`, `legendItem(label:value:color:)`) and `PHScaleView` (scale + marker). **No signed/diverging bar exists — D8 builds it** |
| Chip precedents | fileprivate `StaticTagView` (capsule, `color.opacity(0.2)` bg) + `CustomFlowLayout(horizontalSpacing:verticalSpacing:)`; alert chips: `GlassChipView(isAlert:)` orange `exclamationmark.triangle.fill` |
| Warning text precedent | editor inline `Text("⚠️ …").font(.caption).foregroundStyle(.orange/.red)` (`FoodItemEditorView.swift:525-576`) |
| Editor structure | collapsible sections `basicSection; bannerAdSection; macroSection; …; otherSection` (`FoodItemEditorView.swift:420-430`); `collapsibleHeader(_:isExpanded:)` (line 1002); forms are `@State` value structs (`NutrientForms.swift`); save() creates `FoodItem(id: nextFoodId(), …, isUserAdded: true)` then `try ctx.save()` then `SearchIndexStore.shared.updateItem` |
| Resolver API | `AyurvedaResolver.resolve(for:context:) throws -> AyurvedaResolution` with cases `.classical(AyurvedaProfile)`, `.recipe(AyurvedaProfile)`, `.derived(AyurvedaProfile, via: AyurvedaLink, modifiers: [AppliedModifier], vpk: DoshaVPK)`, `.estimated(EstimatedAyurveda)`, `.none`; `var confidence: Double?` |
| Link tiers in store | `exact` (278) / `near` (58) / `derived` (1,969). Resolver returns `.derived` for **all three**; exact/near carry empty modifiers and undiminished confidence |
| Gunas enum (rules.json, measured) | dense, dry, heavy, light, liquid, oily, rough, sharp, smooth, soft |
| Virya enum | heating, cooling, neutral |
| Localization | raw English literals throughout detail/editor views — D8 follows suit |
| Theming | `@ObservedObject private var effectManager = EffectManager.shared`; `Color(hex:)` for ad-hoc colors; `.glassCardStyle(cornerRadius: 20)` |
| Type-checker budget | §4 handbook rule; detail/editor already use small `private var` sections + fileprivate sub-structs; ObserversHub splits are the pattern |

## Decisions

**U1 — Placement and shell.** `FoodItemDetailView` gains exactly one new entry,
`ayurvedaSection`, inserted **between `phSection` and `ingredientsSection`**
(line 106/107), plus one `private var ayurvedaSection: some View` that is a single
delegation: `AyurvedaSectionView(food: food)`. All real UI lives in new files under
`Ayura/Ayurveda/Views/` so `FoodItemDetailView.swift` changes by ~5 lines.
`AyurvedaSectionView` replicates the `SectionView` header style locally (6 lines —
do **not** de-fileprivate `SectionView`) and wraps content in
`.padding().glassCardStyle(cornerRadius: 20)`.

**U2 — Resolve once, render a value type.** `AyurvedaSectionView` holds
`@Environment(\.modelContext)` and `@State private var display: AyurvedaDisplay?`,
populated in `.task(id: food.id)` via `AyurvedaResolver.resolve` →
`AyurvedaDisplay.make(from:)`. `body` never calls the resolver. On `.none` or a
thrown error the section renders `EmptyView` (matches the app's empty-section
convention; fail-open like the seeder).

**U3 — `AyurvedaDisplay` (value type, one new file).** Flattens all five resolution
cases so subviews never switch on the enum:

```
struct AyurvedaDisplay {                     // Sendable
  let tierLabel: String                      // via AyurvedaDisplayMath (U4)
  let tierDetail: String?                    // U5
  let vata: Int; let pitta: Int; let kapha: Int
  let rasa: [String]; let virya: String?; let vipaka: String?; let gunas: [String]
  let modifierLabels: [String]               // derived tier only
  let viruddha: [String]; let contraindications: [String]
  let engineExcluded: Bool
  let confidence: Double?                    // hidden for tier User
  let qualityCaption: String?                // U8
  let sanskrit: String?
  static func make(from: AyurvedaResolution) -> AyurvedaDisplay?   // nil for .none
}
```

Case mapping: `.classical`/`.recipe`/`.user` read the profile fields directly
(vpk = `doshaVata/Pitta/Kapha`); `.derived` uses the **resolution's adjusted `vpk`**
(not the profile's) and the profile's rasa/virya/vipaka/gunas/viruddha/
contraindications; `.estimated` maps `EstimatedAyurveda` (vpk/virya/gunas/
appliedModifiers → labels; rasa/vipaka/viruddha/contraindications empty,
sanskrit nil).

**U4 — Tier mapping and display math are pure and gate-tested.** New file
`Ayura/Ayurveda/AyurvedaDisplayMath.swift`, **imports Foundation only** (so it
compiles standalone with `swiftc` for gate G2):

```
public enum AyurvedaDisplayMath {
  public enum TierInput { case classical, recipe, derived(linkTier: String), estimated, user }
  public static func tierLabel(_ t: TierInput) -> String
  public static func effectLabel(_ v: Int) -> String     // U6 wording
  public static func valueString(_ v: Int) -> String     // "-2" "+1" "0" (ASCII)
  public static func barFraction(_ v: Int) -> Double     // min(abs(v),2)/2
  public static func percentages(vata: Int, pitta: Int, kapha: Int) -> (v: Int, p: Int, k: Int)
}
```

Tier mapping (normative — this is where link tiers exact/near become "Classical"):

| TierInput | Label |
|---|---|
| .classical | Classical |
| .recipe | Recipe |
| .derived("exact") / .derived("near") | Classical |
| .derived("derived") | Derived |
| .estimated | Estimated |
| .user | User |

Percentage formula (decision 6 — UI-derived only): weights `w = value + 2` per
dosha (range 0…4); if `w_v+w_p+w_k == 0` return `(33,33,34)`; else
`floor(100·w/total)` then distribute the remainder to 100 one point at a time by
largest fractional part, ties broken in order V, P, K. Reference vectors in
§Simulated reference numbers are normative.

**U5 — Tier row.** First row inside the card: a tier chip (StaticTag-style capsule,
`Color(hex:).opacity(0.25)` background — Classical `34A853`, Derived `4A86E8`,
Estimated `FCC934`, Recipe `9C6ADE`, User `999999`) followed by `tierDetail` in
`.caption` secondary style:

- classical/derived: `"from <profile.name>"`, derived additionally
  `" · <n> preparation modifier(s)"` when `modifierLabels` non-empty.
- estimated: `"category rule: <categoryRule.category ?? "default">"`.
- recipe: `"computed from classical ingredients"`. user: `"your entry"`.

Confidence, when non-nil and tier ≠ User, appends `" · confidence 0.60"`
(`String(format: "%.2f")`).

**U6 — Dosha bars (the headline component).** New `DoshaBarsView` +
`DoshaBarRowView` in one file. Row = `HStack { Text(doshaName).frame(width: 56, alignment: .leading); bar; Text(valueString + " " + effectLabel).frame(width: 132, alignment: .trailing).font(.caption) }`.
Bar: capsule track height 12, `accent.opacity(0.12)`, a 1-pt center tick in
`accent.opacity(0.4)`; fill anchored at center extending
`barFraction(v) × trackWidth/2` — **left and green `Color(hex:"34A853")` for
negative (pacifies), right and orange `Color(hex:"E8710A")` for positive
(aggravates)**, nothing at 0. `effectLabel`: −2 "strongly pacifies", −1 "pacifies",
0 "neutral", +1 "aggravates", +2 "strongly aggravates".

A trailing `±`/`%` toggle (two small buttons or `Picker(.segmented)`, local
`@State`, default `±`) switches to the **% view**: a `MacroProportionBarView`-style
segmented capsule using `percentages(…)` with dosha identity colors Vata
`8E7CC3` / Pitta `E06666` / Kapha `6AA84F` and a `legendItem`-style legend
(`Vata 13%` …). Segments with 0% are omitted.

**U7 — Facet chips and warnings.** One file `AyurvedaChipsView.swift`:

- `AyurvedaChipRow(title:values:)` — `.caption` title + `CustomFlowLayout` of
  StaticTag-style capsules (accent `.opacity(0.2)` bg). Rendered only when
  non-empty, for: Rasa (taste), Virya (energy), Vipaka (post-digestive), Gunas
  (qualities), and — derived tier — Preparation modifiers (`modifierLabels`,
  yellow `FCC934.opacity(0.25)` bg to signal they adjusted the bars).
- `AyurvedaWarningsView` — viruddha: title "Viruddha — incompatible combinations",
  one row per entry: `Image(systemName:"exclamationmark.triangle.fill")`
  `.foregroundStyle(.orange)` + `Text(entry).font(.caption).foregroundStyle(.orange)`.
  Contraindications: same layout in `.red`. Display-only; never blocks (decision 3).
- `engineExcluded == true` → red banner at the **top** of the card (above tier row):
  `Text("⚠️ Health warning: traditional sources and modern evidence advise against consuming this. Shown for reference only — never recommended.").font(.caption).foregroundStyle(.red)`.

**U8 — Quality caption (decision 5).** Last line of the card, `.caption2`,
secondary color: qualityState `"aiDraft"` → `"AI-drafted Ayurvedic details, pending
expert review. Informational only — not medical advice."`; tier Estimated →
`"Estimated from food category and preparation — not a classical source."`; tier
User → nil; anything else reviewed → nil.

**U9 — Editability policy (founder-ratified, option A).**

1. **User-added foods: fully editable.** `FoodItemEditorView` gains one collapsible
   section `ayurvedaSection` ("Ayurveda", `@State private var showAyurveda = false`)
   appended **after `otherSection`** (line 430). Because the editor is only ever
   reachable for user foods (list gating) and new/duplicated foods are created
   `isUserAdded: true`, the section renders **unconditionally** — no policy branch
   needed in code.
2. Edits persist as an `AyurvedaProfile` with `id = "user.<foodId>"`,
   `kind = "user"`, `qualityState = "user"`, `provenance = ["user-editor"]`,
   `confidenceAyur = 1.0`, `confidenceSci = nil`, `foodId/name` from the FoodItem,
   `category = food.category?.first?.rawValue ?? ""`, `seedVersion` = current bundle
   seedVersion, everything else empty/nil. Resolver precedence already favors it:
   the by-`foodId` profile fetch runs before link/estimated fallback.
3. `AyurvedaResolver` change (only Swift-layer data change in D8): add
   `case user(AyurvedaProfile)` to `AyurvedaResolution`; in `resolve`, profile
   `kind == "user"` → `.user`; `confidence` for `.user` = `profile.confidenceAyur`.
   `default:` still → `.none`.
4. **Catalog foods: read-only.** No editor path exists for them; their Ayurveda is
   view-only in the detail section. Override-with-provenance is explicitly deferred
   (would need revert UI + resolver precedence rules; revisit post expert review).
5. Seeder safety: user profiles use the `"user."` id prefix and foodIds outside all
   seeded bands, so the seeder's non-empty-profile top-up check and all count gates
   (2,214 profiles / 2,305 links) are unaffected. The seeder never deletes profiles.

**U10 — Editor form.** `AyurvedaForm` value struct (`Sendable`,
`vata/pitta/kapha: Int = 0`, `rasa: Set<String>`, `virya: String?`,
`vipaka: String?`, `gunas: Set<String>`; `var isEmpty: Bool` = all defaults).
UI inside the collapsible card: three `Stepper`s (−2…+2) each showing
`valueString + " " + effectLabel`; Rasa = 6 toggle chips (sweet, sour, salty,
pungent, bitter, astringent); Virya = `Picker` (— / heating / cooling / neutral);
Vipaka = `Picker` (— / sweet / sour / pungent); Gunas = 10 toggle chips (U-reality
enum: dense, dry, heavy, light, liquid, oily, rough, sharp, smooth, soft); footer
caption `"Saved as tier 'User' — shown in the food's Ayurveda section."`.

Prefill: in `.task`, fetch profile `id == "user.<(food ?? dubFood)?.id>"` once and
populate the form (guarded by a `@State` flag). Save semantics (deterministic):
in `save()`, after the item's fields are assigned and before `try ctx.save()`,
call `AyurvedaUserProfileStore.upsert(form:for:context:)` — creates the profile iff
`!form.isEmpty`, updates an existing one always (clearing back to defaults keeps a
zeroed profile; deletion is out of D8 scope). No new validation rules.

**U11 — File plan (type-checker budget, handbook §4).** Every view is a small
struct; every closure handler extracted; no force-unwraps; raw English literals.

| File | Contents | Action |
|---|---|---|
| `Ayura/Ayurveda/AyurvedaDisplayMath.swift` | U4 pure math, Foundation-only | create |
| `Ayura/Ayurveda/Views/AyurvedaDisplay.swift` | U3 struct + `make(from:)` | create |
| `Ayura/Ayurveda/Views/AyurvedaSectionView.swift` | U1/U2/U5/U8 shell, tier row, captions | create |
| `Ayura/Ayurveda/Views/DoshaBarsView.swift` | U6 bars + % view + toggle | create |
| `Ayura/Ayurveda/Views/AyurvedaChipsView.swift` | U7 chips + warnings | create |
| `Ayura/Ayurveda/Views/AyurvedaEditorSection.swift` | U10 card, `AyurvedaForm`, `AyurvedaUserProfileStore` | create |
| `Ayura/Ayurveda/AyurvedaResolver.swift` | U9.3 `.user` case | edit |
| `Ayura/Food/Views/FoodItemDetailView.swift` | U1 (~5 lines) | edit |
| `Ayura/Food/Views/FoodItemEditorView.swift` | U9/U10 hooks (state, section, prefill, save call) | edit |
| `ayurveda-data/tools/d8_math_check.swift` | G2 harness `main` asserting §vectors | create |

**U12 — What D8 must NOT touch.** `FoodItem.swift`, `AyurvedaProfile.swift`,
`AyurvedaRules.swift`, seeder, seed/rules JSON, validator, any `ayurveda-data`
content file. The store and all D34 count gates stay bit-identical.

## Simulated reference numbers (normative for gates)

**Percentage vectors** (input signed V/P/K → output %):

| # | in | out |
|---|---|---|
| 1 | 0,0,0 | 34,33,33 |
| 2 | −1,1,2 | 13,37,50 |
| 3 | 2,0,−1 | 57,29,14 |
| 4 | −2,−2,−2 | 33,33,34 |
| 5 | 1,0,1 | 38,25,37 |
| 6 | 2,−1,2 | 45,11,44 |
| 7 | 0,2,0 | 25,50,25 |
| 8 | 0,1,−1 | 33,50,17 |
| 9 | −2,2,−2 | 0,100,0 |
| 10 | −1,−1,−1 | 34,33,33 |

**Tier vectors** (7): table in U4. **Effect labels** (5): U6 list.
**Value strings** (5): −2→"-2", −1→"-1", 0→"0", 1→"+1", 2→"+2".
**Bar fractions** (4): 0→0.0, 1→0.5, 2→1.0, −2→1.0.
Total **31 assertions** — gate G2 output `D8 MATH CHECK: 31/31 PASS`.

**Runtime spot foods** (VPK values founder-verified in D34 Run 6):

| Food | Expected in UI |
|---|---|
| fdcId 2 (milk) | tier **Classical** (exact link → dravya.milk-cow), rasa/virya/vipaka/guna chips present, no modifier chips |
| fdcId 8641 | tier **Derived**, bars V −1 / P +1 / K +2, modifier chip "fried" |
| fdcId 3623 | tier **Derived**, bars 0 / +1 / −1, modifier chip "dried" |
| fdcId 2655 | tier **Estimated**, bars +2 / 0 / −1, no modifier chips |
| fdcId 6148 | tier **Estimated**, bars 0 / +2 / 0, modifier chip "dry-heat" |
| foodId 900001 "Aam panna" | tier **Classical** (placeholder dravya, direct) |
| any seeded recipe | tier **Recipe** |
| search "betel" | red engineExcluded banner above tier row |
| new user food (G5 script) | tier **User**, edited values round-trip |

% toggle spot check: fdcId 2655 → segments 57/29/14 (vector 3).
