# D6 Design — Ayurveda Schema + Seeder (Director)

*Status: APPROVED FOR DISPATCH · 2026-07-21 · Design authority: RESTART-PLAN.md D6,
ayurveda-data/README.md "Seeding strategy". Implementation: Codex packet `TASK-D6.md`.*

## Objective

Make the completed content layer — **714 dravyas + 1,500 recipes, validator green** —
live in the app database, additively, without touching any existing model or store row.

Out of scope: all UI (D8), the D3 generic crosswalk and D4 category rules (schema here
is forward-compatible with both), expert review promotion.

## Data reality (measured 2026-07-21)

| Fact | Value |
|---|---|
| Preseeded store | 12,601 foods, `ZID` 1–12,601, 0 recipes |
| Dravyas | 714; **381 USDA-bound** (287 primary `exact`, 94 primary `near`), **333 unbound** |
| Distinct bound fdcIds | 336; **40 contested** by >1 dravya (e.g. 10962 ← mung-bean/mung-whole/mung-dal-split) |
| Recipe ingredients | 9,366 `dravyaId` refs + 1,205 `fdcId` refs — all resolve |
| A3 simulated (director) | 331 primary foods · **383 placeholders** (333 unbound + 50 contested losers) · 336 links |
| Engine exclusions | `dravya.betel-nut`, `dravya.vanaspati` (flagged in `reviewNote` prose only — must become a structured flag) |
| User-added id scheme | `nextFoodId() = max(id)+1` → existing users occupy 12,602+ |
| Xcode project | objectVersion 77, fileSystemSynchronized — new files under `Ayura/` join the target automatically |
| Recipe instructions | live in `FoodItem.itemDescription` (no structured steps field) |
| Search index | `SearchIndexStore.rebuildIndexIfNeeded` auto-rebuilds when food count drifts >5 |

## Decisions

**A1 — One additive model, FK by Int, zero changes to FoodItem.**
`AyurvedaProfile` is a new `@Model` holding all Ayurvedic facets for both dravyas and
recipes (`kind` discriminator). It references its `FoodItem` by `foodId: Int` — **no
`@Relationship` and no new property on `FoodItem`** — so the existing store migrates
with zero risk and the preseeded copy path is untouched.

**A2 — `AyurvedaLink` carries the fdcId → dravya map.**
One row per bound fdcId (336 now): `fdcId` (unique), `dravyaProfileId`, `tier`
(`exact`/`near`). This is the derived-tier lookup table; D3's crosswalk.csv later
appends rows with tier `derived` through the same model, no schema change. D4 rules
stay bundle-side (computed at lookup, nothing stored for 12.6k rows).

**A3 — Primary food assignment.**
Each dravya needs exactly one `foodId`:
1. Per contested fdcId, the winner is the best-tier claimant (`exact` > `near`);
   ties (two `exact` claimants, e.g. fdcId 6686 garlic) go to the lexicographically
   smaller dravya id. Each dravya then takes its first binding (exact before near)
   that it actually won — losers fall back to their next free binding.
2. Dravyas with no won binding and the 333 unbound dravyas get a **placeholder
   FoodItem** (band below),
   `isUserAdded=false, isRecipe=false`, no nutrition (panels show empty — correct,
   these are items like shilajit/ushira with no USDA analogue).
All 40 contested fdcIds and every placeholder are listed in the build report.

**A4 — ID bands (collision-proof by construction).**
- Dravya placeholders: `900000 + ordinal` (dravyas sorted by id; only those needing one).
- Recipes: `1000000 + ordinal` (recipes sorted by id; 1000001–1001500).
- Upgraded installs have user ids at 12,602+ (max+1 scheme) — reaching 900,000 would
  require ~887k user-created foods; the seeder still **verifies the bands are free**
  and aborts with a report rather than overwrite. After seeding, `nextFoodId()`
  continues from 1,001,501 — harmless (Int).

**A5 — Seed bundle.**
`ayurveda-data/build_seed.py` packs everything into one deterministic artifact,
`Ayura/ayurveda_seed.json.gz` (auto-included as a bundle resource by the
synchronized project):

```json
{
  "seedVersion": 1,
  "generatedAt": "…",
  "counts": {"dravyas": 714, "recipes": 1500, "links": 336, "placeholders": N},
  "dravyas":  [ { …batch item fields…, "foodId": 4558, "foodIsPlaceholder": false,
                  "engineExcluded": false, "qualityState": "aiDraft" } ],
  "recipes":  [ { …batch item fields…, "foodId": 1000001,
                  "ingredients": [{"foodId": 6372, "grams": 180, "name": "…"}] } ],
  "links":    [ {"fdcId": 4558, "dravyaId": "dravya.ghee", "tier": "exact"} ]
}
```
The script performs A3/A4 resolution at build time so the Swift seeder does **no
matching logic** — it only inserts what it reads. Engine exclusion is set from an
explicit id list in the script (`dravya.betel-nut`, `dravya.vanaspati`).

**A6 — Seeder: one-time, versioned, ordered after foods.**
`SeedManager.seedAyurvedaIfNeeded(context:)` called from `seedIfNeeded` immediately
after `seedFoodsIfNeeded`. Guards, in order: `AyurvedaProfile` table empty **and**
`UserDefaults "ayurvedaSeedVersion" < bundle seedVersion` (the key enables future
content updates as re-seeds). Loads the gz with the existing `ZlibGzip.decompress`,
inserts in batched transactions (~200 rows) with autosave already disabled by
`seedIfNeeded`. On success writes the version key; on any thrown error rolls back,
does **not** write the key, logs, and leaves the app fully functional without
Ayurveda data (fail-open).

**A7 — Recipes ride the existing machinery.**
Per recipe: `FoodItem(id: band, name:, isRecipe: true, isUserAdded: false)`,
`prepTimeMinutes = prep + cook`, `itemDescription` = numbered steps + blank line +
guidance (the app's only instruction surface today; structured `steps` are also kept
on the profile for D8). One `IngredientLink(food:, grams:)` per ingredient —
`dravyaId` → that dravya's `foodId` (placeholder included: contributes zero nutrition
by existing `aggregatedNutrition` semantics, correctly), `fdcId` → itself. Nutrition,
calories, and search all work unmodified; the +2,214 food count change triggers the
index rebuild automatically.

**A8 — Warn, don't block** (approved decision 3): `viruddha`/`viruddhaFlags` and
`engineExcluded` are seeded as data; enforcement is D8 UI + engine work. Nothing is
hidden or dropped.

**A9 — Read API for D8.** A small `AyurvedaResolver` ships with D6 so D8 has one entry
point: `resolve(for foodItem)` → `.classical(profile)` (profile by foodId, kind
dravya) / `.recipe(profile)` / `.derived(profile, via: link)` (AyurvedaLink by fdcId)
/ `.estimated` (stub returning nil until D4) / `nil`. Includes the fetch-descriptor
indexes to make these lookups cheap.

## Model definitions (normative)

```swift
@Model public final class AyurvedaProfile {
    #Index<AyurvedaProfile>([\.foodId], [\.kind])
    @Attribute(.unique) public var id: String   // "dravya.ghee" | "recipe.classic-mung-kitchari"
    public var kind: String                     // "dravya" | "recipe"
    public var foodId: Int                      // FoodItem.id (FK by value, A1)
    public var foodIsPlaceholder: Bool = false
    public var name: String
    public var category: String                 // dravya category | recipe category
    // Shared facets
    public var doshaVata: Int; public var doshaPitta: Int; public var doshaKapha: Int
    public var seasons: [String]; public var timeOfDay: [String]
    public var viruddha: [String]               // recipes: viruddhaFlags
    public var provenance: [String]
    public var confidenceAyur: Double; public var confidenceSci: Double?
    public var qualityState: String = "aiDraft"
    public var reviewNote: String?
    public var engineExcluded: Bool = false
    public var seedVersion: Int
    // Dravya-only (nil/empty for recipes)
    public var sanskrit: String?; public var aliases: [String] = []
    public var rasa: [String] = []; public var virya: String?; public var vipaka: String?
    public var gunas: [String] = []; public var prabhava: String?
    public var agniEffect: Int?; public var digestibility: Int?
    public var combinations: [String] = []; public var contraindications: [String] = []
    public var preparation: String?
    public var servingsJSON: String?            // [{label, grams}] encoded; no new model needed
    // Recipe-only
    public var meal: String?; public var servingsCount: Int?
    public var prepMinutes: Int?; public var cookMinutes: Int?
    public var steps: [String] = []; public var guidance: String?
    // init: memberwise, all fields
}

@Model public final class AyurvedaLink {
    #Index<AyurvedaLink>([\.fdcId])
    @Attribute(.unique) public var fdcId: Int
    public var dravyaProfileId: String
    public var tier: String                     // "exact" | "near" | (D3: "derived")
    // init
}
```

Both types are appended to `mainTypes` in `DatabaseSetup.createContainer()` — the only
edit to an existing file besides `SeedManager`. Additive ⇒ lightweight migration.

## Acceptance gates (all must pass before report)

1. `build_seed.py` deterministic: two runs → byte-identical gz (fixed key order, no
   timestamps inside item records); counts match the table above; 0 unresolved
   ingredients; exactly 2 `engineExcluded`.
2. Swift: profiles inserted = 2,214 (714 + 1,500); links = 336; recipe FoodItems =
   1,500 with ≥1 IngredientLink each and every `link.food != nil`; placeholder count
   matches build report.
3. Idempotence: second call of `seedAyurvedaIfNeeded` inserts 0 rows.
4. Spot values (director will verify): kitchari (recipe.classic-mung-kitchari)
   aggregated kcal in 1,400–2,100 for the whole recipe; ghee profile vata −2/pitta −2/
   kapha +1; betel nut & vanaspati `engineExcluded == true`.
5. `validate.py --store` still green (content untouched).
6. Founder gate (Mac, outside sandbox): clean build, fresh-install boot seeds within
   acceptable first-launch time, upgrade-simulated boot (existing default.store) seeds
   without duplicating foods; existing app flows unaffected.

## Risks

- **First-launch cost**: ~2.2k profiles + 1.5k FoodItems + ~10.5k links in one pass;
  batched transactions keep memory flat; measured on Mac at founder gate. Fallback:
  move seeding behind an async splash task (already the SeedManager pattern).
- **SwiftData `#Index` on new models** with existing store: additive index creation is
  lightweight-safe; verified at founder gate.
- **Contested fdcIds** (40): resolution rule is deterministic but semantically curated
  only by tier + name order; expert review pass may re-point primaries — that's a
  content update via seedVersion bump, not a code change.
- **Placeholder foods in search**: 333 nutrition-less items become searchable. Accepted
  (they're real catalog items); D8 badges them. If founder objects, a
  `foodIsPlaceholder` filter in search ranking is a one-line D8 tweak.
