# Practices implementation report

## Completion

- Functional implementation: **100%** for the assets that were supplied.
- Whole brief including media still not supplied: **92%**.
- Clean simulator build: **passed** with Xcode 26.1.1.
- Simulator runtime smoke test: **passed** for library, entry card, player,
  device TTS startup, and bundled ambience startup.

The remaining 8% is recorded narration, measured narration timing, and final
scene artwork. None of those assets were present in the handoff. Device TTS,
authored timing, and an intentionally restrained gradient scene fallback are
active today.

## App tab and navigation

`AppTab.practices` was appended after `nodes`; no existing raw value moved. A
twelfth stable ID was appended and the runtime now preconditions that
`stableIDs.count == AppTab.allCases.count`.

The repository contains the canonical UUIDv5 namespace in
`ayurveda-data/stable_ids.py`:

- root namespace: `uuid5(NAMESPACE_URL, "https://ayura.app/seed-identities/v1")`
- exact new input: `app-tab:practices`
- resulting UUID: `F4728EEB-7771-57B2-8B06-48CA4A4A654C`

The older `AppTab` IDs cannot be reproduced from the current generator and no
older AppTab derivation script exists in the repository history. The new value
therefore follows the repository's documented canonical namespace without
changing any shipped ID.

The tab is wired through `RootView.tabContent` and uses the existing liquid tab
bar. Its visible position is immediately after Training and before Calendar.
The former Training lotus/meditation asset is now the Practices template icon.
Training has a newly generated monoline Tree Pose (`Vrksasana`) figure based on
the supplied visual reference, retaining the same open circular frame and
transparent template treatment as the rest of the tab icon set.
Practices participates in the same global search flow as Food List. Search
matches titles, Sanskrit names, descriptions, kinds, techniques, traditions,
metadata, themes, goals, contraindications, and cue text, and combines with the
local kind filters. Search visibility is centralized in
`selectedTabAllowsGlobalSearch`; 16 editor-dismiss reset sites use it.

Favorites follow the existing Food and Exercise convention: a yellow star is
available on both library rows and the entry card, the value persists in
SwiftData, and a counted Favorites chip combines with global search. Favorite
IDs are preserved if a future seed version refreshes the practice catalogue.

## Data and seeding

The original `practices.json` was copied byte-for-byte. Its SHA-256 is
`9b31d68fd65c7d6df1746889a38540c9316681e16deac4b847cd2c0fbe42e2db` in
both the handoff and the bundled copy.

`Practice` and `PracticeCue` are SwiftData models and are part of the main
schema. `PracticeSeeder` runs immediately after `YogaSeeder` and validates the
catalog before inserting it.

- Practices: **60**
- Cues: **601**
- Validation failures: **0**
- Unresolved `seatAsanaId` references: **0**
- `supersedesAsanaSlug` rows modified: **0**
- Timing mode: **authored**

Validation covers positive total duration, ambience volume in `0...1`, sorted
cue times, cue bounds, non-empty text, non-negative holds, unique IDs/slugs/
catalog numbers, exact catalogue range, and yoga seat references. The seeder
also supports a future `practice_timing_manifest.json`; if bundled, it switches
to measured timing after verifying cue counts.

## Screens

### Library

![Practices library](../../TestReports/Practices/library.png)

Includes the time-aware Right now recommendation, counted filters, all 60 rows,
and Exercise List-style cards with an 80-point circular kind thumbnail and a
segmented vata/pitta/kapha pacification ring.

### Entry card

![Practice entry card](../../TestReports/Practices/entry.png)

Includes metadata, tradition, contraindications before length whenever present,
runtime-safe duration options, device/no-voice guidance, all 36 bundled sounds,
and Begin.

### Player

![Practice player](../../TestReports/Practices/player.png)

The player shows one centred cue, fades to darkness for holds, has no clock or
progress UI, gives one haptic per cue, supports tap-anywhere advance, and leaves
the close button as the only small target. Visualisations receive a scene layer
that fades to 7%; meditations have no scene layer.

## Audio

All **36 MP3 files** from `meditaions music` were copied into
`Ayura/Practices/Ambience`. Xcode currently flattens synchronized resource
folders in the product bundle, so the resolver supports both the intended
`Practices/Ambience` path and the product root. Bundle verification found all
36 tracks.

Every sound is available in the entry picker and every sound is also assigned
as the automatic default of at least one practice. The 36 resources are grouped
under the 12 logical ambience IDs and rotate deterministically by catalogue
order. The seed gate verifies that there are 36 unique mappings, that all are
assigned across the 60 practices, and that every mapped bundle URL resolves.

The source and bundled directories both contain 36 MP3 files (133 MB), with no
filename differences and no SHA-256 differences.

No recorded narration asset was supplied (`audioAssetName` is null for all 60
practices), so the default remains device TTS. Recorded narration automatically
falls back to device TTS when its URL is missing.

No new individual file exceeds 90 MB and no commit was created.
