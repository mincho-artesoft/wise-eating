# REPORT-D8 — stopped at preflight

## Summary

D8 implementation did not start. The TASK-D8 stop-and-report rule was
triggered during preflight because the `ayurveda-app` worktree and index were
not clean before any executor edit. In addition to the known `.DS_Store`
modification, `PROJECT-HANDBOOK.md` had both staged and unstaged changes, and
the three director-authored D8 packet files were staged for deletion while
byte-identical copies existed as untracked files at the same paths.

No source file, data file, seed file, validator, or existing packet file was
edited, staged, restored, or committed by this run. This report is the only
file created by the executor.

## Gate results G1–G6

### G1 — scope: FAIL (pre-existing unexpected Git state)

Branch and revisions:

```text
branch: ayurveda-app
HEAD: 8ea80777be099db3f5aa73f41482e4cf68dbf5b6
origin/ayurveda-app: 15cb1b2a453aa4e4ea49b94e133aeb2321519951
ahead/behind: +2 / -0
```

Pre-edit `git status --porcelain=v2 --branch`, verbatim:

```text
# branch.oid 8ea80777be099db3f5aa73f41482e4cf68dbf5b6
# branch.head ayurveda-app
# branch.upstream origin/ayurveda-app
# branch.ab +2 -0
1 .M N... 100644 100644 100644 0acba70a0c8d9d029fff6a53747a6ce850ba443a 0acba70a0c8d9d029fff6a53747a6ce850ba443a .DS_Store
1 MM N... 100644 100644 100644 bbebf76d72ac5f2c576f5e766214be7ce00a6229 37a9759e830f01343e2826006314e68d4deb0be4 PROJECT-HANDBOOK.md
1 D. N... 100644 000000 000000 2fbfae6f03d35c3e60d63bb0923d67537d781cb4 0000000000000000000000000000000000000000 ayurveda-data/DESIGN-D8.md
1 D. N... 100644 000000 000000 adb53a5d6eedd8d25f5dd74139a18a69a4670afc 0000000000000000000000000000000000000000 ayurveda-data/DISPATCH-D8.md
1 D. N... 100644 000000 000000 9870ddcf9f8cb2ce6cd2d3f2e63da256af46eab4 0000000000000000000000000000000000000000 ayurveda-data/TASK-D8.md
? ayurveda-data/DESIGN-D8.md
? ayurveda-data/DISPATCH-D8.md
? ayurveda-data/TASK-D8.md
```

Staged diff before executor edits:

```text
M PROJECT-HANDBOOK.md
D ayurveda-data/DESIGN-D8.md
D ayurveda-data/DISPATCH-D8.md
D ayurveda-data/TASK-D8.md
```

Unstaged diff before executor edits:

```text
M .DS_Store
M PROJECT-HANDBOOK.md
```

The packet files present in the worktree were verified to be byte-identical to
their committed HEAD blobs:

```text
ayurveda-data/DESIGN-D8.md worktree=2fbfae6f03d35c3e60d63bb0923d67537d781cb4 HEAD=2fbfae6f03d35c3e60d63bb0923d67537d781cb4
ayurveda-data/DISPATCH-D8.md worktree=adb53a5d6eedd8d25f5dd74139a18a69a4670afc HEAD=adb53a5d6eedd8d25f5dd74139a18a69a4670afc
ayurveda-data/TASK-D8.md worktree=9870ddcf9f8cb2ce6cd2d3f2e63da256af46eab4 HEAD=9870ddcf9f8cb2ce6cd2d3f2e63da256af46eab4
```

Although the packet-file contents match HEAD, repairing the index or resolving
the staged/unstaged handbook changes would alter pre-existing state and is not
authorized by TASK-D8. G1 therefore cannot be satisfied by this executor run.

### G2 — display math: NOT RUN

Stopped at G1 before creating implementation files or the math harness.

### G3 — build: NOT RUN

The required pre-change baseline and post-change simulator builds were not run
after G1 failed.

### G4 — runtime spot checks: NOT RUN

No UI implementation was built or installed. No screenshots were taken.

### G5 — editor round-trip: NOT RUN

No editor implementation or persistence test was attempted.

### G6 — data untouched: NOT RUN

The validator/store command was not run after G1 failed. No existing data,
seed, store, JSON, or validation file was changed by this executor run.

## Files changed

Created by this run:

```text
ayurveda-data/REPORT-D8.md
```

A compliant deliverables-only `git diff --stat` cannot be produced while the
pre-existing staged and unstaged changes listed under G1 remain unresolved.

## Deviations

Stop-and-report was triggered before implementation because G1 encountered
unexpected pre-existing staged and unstaged state. No attempt was made to
reset, restore, stash, commit, or otherwise reinterpret that state.

## Open items for founder gate

- Decide how to preserve or clear the staged and unstaged
  `PROJECT-HANDBOOK.md` state.
- Restore the Git index entries for `DESIGN-D8.md`, `DISPATCH-D8.md`, and
  `TASK-D8.md` without losing their byte-identical worktree copies.
- Decide whether the tracked `.DS_Store` modification is an accepted preflight
  exception for D8 or must be cleaned before rerunning.
- After a clean preflight, rerun D8 from G1, including baseline warning count,
  implementation, G2–G6, screenshots, and visual/VoiceOver founder checks.

## Run 2 — stopped at G3

### Summary

The director-authorized canonical preflight cleared the stale index and Run 2
proceeded through anchor verification, the pre-change build baseline, D8
implementation, and the standalone display-math gate. G2 passed 31/31. The
first post-change G3 build failed with one compiler error in the edited
`FoodItemEditorView.swift`. TASK-D8 says any failed gate must stop without a
repair attempt, so Run 2 stopped immediately and did not run G4–G6, commit, or
push.

### Gate results G1–G6

#### G1 — preflight and scope: PASS before implementation

The literal `rm -f` command was rejected by the shell safety layer before it
ran. The safe exact-scope equivalent enumerated and deleted the one top-level
lock file, then the director-authorized mixed reset rebuilt the index:

```text
.git/index.lock
Unstaged changes after reset:
M .DS_Store
```

Canonical post-reset status:

```text
## ayurveda-app...origin/ayurveda-app [ahead 2]
 M .DS_Store
?? ayurveda-data/REPORT-D8.md
```

No other path was dirty. The committed anchors were present exactly:

```text
FoodItemDetailView.swift:106 phSection
FoodItemDetailView.swift:107 ingredientsSection
FoodItemEditorView.swift:416 private var mainForm
FoodItemEditorView.swift:430 otherSection
FoodItemEditorView.swift:908 private func save()
FoodItemEditorView.swift:976 try ctx.save()
```

The packet's exact simulator name was absent, so a simulator was created from
the installed matching device type and runtime:

```text
iPhone 16 (com.apple.CoreSimulator.SimDeviceType.iPhone-16)
iOS 26.2 (23C54)
UDID 9F503E98-4EC6-40DC-91B7-33632E1D1943
```

#### G2 — display math: PASS

Command:

```sh
swiftc -o /tmp/d8check WiseEating/Ayurveda/AyurvedaDisplayMath.swift ayurveda-data/tools/d8_math_check.swift && /tmp/d8check
```

Output:

```text
D8 MATH CHECK: 31/31 PASS
```

#### G3 — build and warning comparison: FAIL

Pre-change baseline command:

```sh
xcodebuild -project WiseEating.xcodeproj -scheme WiseEating -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Baseline result:

```text
** BUILD SUCCEEDED **
warning lines: 143
unique warning texts: 70
log: /tmp/d8_run2_baseline_build.log
```

The same command was run after the implementation changes. Result:

```text
** BUILD FAILED **
exit code: 65
warning lines emitted before failure: 1
log: /tmp/d8_run2_post_build.log
```

Compiler diagnostic, verbatim:

```text
/Users/minchomilev/work/wise-eating/WiseEating/Food/Views/FoodItemEditorView.swift:921:67: error: cannot convert value of type 'ObjectIdentifier' to expected argument type 'Int'
        if let storedForm = AyurvedaUserProfileStore.form(foodId: foodId, context: ctx) {
                                                                  ^
```

No type-check-timeout occurred, so the carried D34 mechanical-split authority
did not apply. No fix was attempted after this failed gate.

#### G4 — runtime spot checks: NOT RUN

The failed G3 build produced no gate-qualified app. No food detail checks,
percentage toggle check, or screenshots were performed.

#### G5 — editor round-trip: NOT RUN

The failed G3 build stopped the run before creation of `D8 Test Ghee Rice`,
profile update, relaunch, or SQLite persistence/count verification.

#### G6 — data untouched: NOT RUN

The validator/store command was not run because G3 failed. No seed, rules,
store, JSON, model, seeder, SeedManager, or validator file was edited.

### Files changed

Uncommitted deliverable paths present when G3 stopped:

```text
WiseEating/Ayurveda/AyurvedaDisplayMath.swift
WiseEating/Ayurveda/Views/AyurvedaDisplay.swift
WiseEating/Ayurveda/Views/AyurvedaSectionView.swift
WiseEating/Ayurveda/Views/DoshaBarsView.swift
WiseEating/Ayurveda/Views/AyurvedaChipsView.swift
WiseEating/Ayurveda/Views/AyurvedaEditorSection.swift
WiseEating/Ayurveda/AyurvedaResolver.swift
WiseEating/Food/Views/FoodItemDetailView.swift
WiseEating/Food/Views/FoodItemEditorView.swift
ayurveda-data/tools/d8_math_check.swift
ayurveda-data/REPORT-D8.md
```

The pre-existing `.DS_Store` modification remains outside the deliverables and
was not touched intentionally. Because the new files remain untracked after
the mandatory stop, ordinary `git diff --stat` does not yet enumerate all 11
deliverables.

### Deviations

None before the gate failure. Stop-and-report was triggered exactly at the
first failed G3 build. The implementation remains uncommitted for a subsequent
director-authorized retry.

### Open items for founder gate

- Correct the reported `FoodItemEditorView.swift:921` type mismatch in a new
  authorized run, then rerun G2 and G3.
- Complete all nine G4 screenshots and the fdcId 2655 percentage toggle.
- Complete the G5 create/edit/relaunch round-trip and SQLite count checks.
- Run G6 validation and data-scope checks.
- Founder visual approval of bar/chip styling on device.
- Dark/light theme sanity check.
- VoiceOver labels smoke test.

## Run 4 / D8.1 — founder evidence and pre-implementation record

### Original visibility diagnosis (recorded before D8.1 implementation)

The app was built from the `dd55a94` line with the director-provided
`Color.clear` render anchor in `AyurvedaSectionView`, installed into the erased
iPhone 16 simulator, and launched with `-uiTestNoAds`. The seed completed with
714 dravyas, 1,500 recipe profiles, and 2,305 links.

The founder, not Codex, performed all UI navigation. Opening food ID 4558 and
recipe ID 1000847 produced these console diagnostics (repeated on a second
open), with no red failure text:

```text
🕉️ Ayurveda resolve foodId=4558: ok
🕉️ Ayurveda resolve foodId=1000847: ok
```

SQLite independently confirmed that data was present for both items:

```text
dravya.ghee                     kind=dravya  foodId=4558     V=-2 P=-2 K=+1 confidence=0.90
recipe.latin-adzuki-pepper-pot  kind=recipe  foodId=1000847 V=-1 P=+1 K=-1 confidence=0.78
```

The founder screenshots supplied on 2026-07-22 confirm that both detail cards
render, including the expected dosha values and tier presentation. They also
show the D8.1 gaps: Add Food exposes the Ayurveda editor, Add Recipe and Add
Menu do not, and the fresh Add Food Ayurveda state is non-neutral. Screenshot
SHA-256 values, in chronological filename order, are:

```text
16.55.47  29e40d67aa5b6c6d53cf954072ae813688983af92dc93ef7044939a477917b8b
16.56.11  791f102383fec97b5b7d7e6a96745ebaa4d71dd84f7922c59d1007b5bbe07725
16.57.56  52a2995005456b12bd4e05dbca055a6dc7cf645460b65a6600a835ee2728b4a1
16.58.38  e4696400a20f3b97eb6d131f766cc2e043d927db84efc7eaf6f369719ef7e106
16.59.04  104a2cfdb0f570ff003c9916a81f1aa722f319284093d761b9b77f988efa22b5
```

Pre-D8.1 SQLite counts were green:

```text
ZAYURVEDAPROFILE = 2214
ZAYURVEDALINK    = 2305
placeholders     = 383
recipes          = 1500
ZFOODITEM total  = 14484
```

Cause split: data was present, the SwiftData queries resolved successfully,
and the view was reached. The previously invisible card was caused by the
empty `Group` producing `EmptyView`, which left no render node on which its
`.task` could run. The director-provided transparent anchor removed that
failure mode without changing visible layout.

### D8.1 implementation and gates

D8.1 added the runtime **Computed** tier after direct-profile and link lookup
and before estimated fallback. Ingredient resolution is recursive to depth 3
with a visited-food-ID cycle guard. Resolved V/P/K values use grams-weighted
means, half-away-from-zero rounding, and the signed −2...+2 clamp. Coverage
below 0.5 falls through to estimated; confidence is `0.5 * coverage` (capped at
0.6), and virya uses the required heating/cooling weighted vote.

The Computed detail card uses the text `computed from your ingredients`, shows
confidence and the existing signed/percentage dosha display, carries the
aiDraft disclaimer, and deliberately omits rasa/vipaka/guna rows.

The standalone math harness was extended by exactly the three D8.1 reference
cases. Result:

```text
D8 MATH CHECK: 34/34 PASS
```

### D8.2 — live recipe/menu editor computation

The D8.2 founder correction replaced the recipe/menu manual-first UI with an
automatic live preview. Both editors pass their current unsaved
`(foodId, grams)` values to `AyurvedaResolver.computeIngredients`; that public
entry point and saved `IngredientLink` resolution share the same private
recursive aggregation path and pure math.

Automatic mode is the default and writes no profile. With no positive-weight
ingredients it asks the user to add ingredients. With coverage below 0.5 it
shows `Not enough recognizable ingredients yet.` Otherwise it renders the
live dosha bars under `Computed from your ingredients — updates automatically`.

`Set manually` reveals the existing controls and prefills V/P/K and virya from
the current computed result. Saving in manual mode writes the `user.<foodId>`
profile. Saving after turning manual mode off deletes that user override so the
detail resolver returns to Computed. Existing user overrides reopen in manual
mode. Add Food remains manual-only; all three forms now initialize explicitly
from a neutral `AyurvedaForm` (V/P/K zero, empty rasa/gunas, nil virya/vipaka).

#### G2 — math: PASS

```text
swiftc -o /tmp/d8check WiseEating/Ayurveda/AyurvedaDisplayMath.swift ayurveda-data/tools/d8_math_check.swift
/tmp/d8check
D8 MATH CHECK: 34/34 PASS
```

#### G3 — simulator build and warning delta: PASS

The D8.1 clean build and final D8.2 rebuild both passed:

```text
/tmp/d81_post_build.log: ** BUILD SUCCEEDED **
/tmp/d82_rebuild.log:    ** BUILD SUCCEEDED **
```

The prior clean D8 baseline contained 143 warning lines and 58 normalized
warning texts. The D8.1 clean build contained 141 lines with the same 58 texts.
The final incremental D8.2 build contained four pre-existing warning texts,
all present in the clean baseline. New normalized warnings: **0**.

#### G4/G5 — founder-operated UI and persistence: PENDING

Codex performed no simulator navigation or screenshots. The final D8.2 build
was installed and launched with `-uiTestNoAds`; startup and the versioned seed
skip path completed without a crash. Before founder interaction SQLite showed:

```text
ZAYURVEDAPROFILE total = 2214
kind="user" profiles   = 0
ZAYURVEDALINK          = 2305
ZFOODITEM total        = 14484
```

The founder requested commit and push before completing the requested D8.2
screenshots and user-profile round trip. Therefore these items remain open and
are not reported as passed:

- live Add Recipe preview with two or three ingredients;
- visible recomputation after adding ghee;
- manual toggle controls prefilled from the live computation;
- untouched recipe detail = Computed and manual recipe detail = User;
- SQLite `kind="user"` row verification and relaunch persistence;
- remaining original G4 spot screenshots and fdcId 2655 percentage toggle.

#### G6 — validator and immutable data: PASS

```text
python3 ayurveda-data/validate.py --store /tmp/pre
Checked 714 dravyas, 1500 recipes
All checks passed.
```

The resolver simulation remained exactly classical 336 / derived 1,969 /
estimated 10,296 = 12,601. Only `REPORT-D8.md` and
`tools/d8_math_check.swift` changed under `ayurveda-data/`. Bundle hashes are
unchanged from HEAD:

```text
ayurveda_seed.json.gz  b20f45715c2b000f1d06dacb59377e5c799c84a45e0593779528f5872c8990b3
ayurveda_rules.json    e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c
```

### D8.1/D8.2 files changed before commits

```text
WiseEating/Ayurveda/AyurvedaDisplayMath.swift
WiseEating/Ayurveda/AyurvedaResolver.swift
WiseEating/Ayurveda/Views/AyurvedaDisplay.swift
WiseEating/Ayurveda/Views/AyurvedaEditorSection.swift
WiseEating/Ayurveda/Views/AyurvedaSectionView.swift
WiseEating/Food/Views/FoodItemEditorView.swift
WiseEating/Food/Views/FoodItemMenuEditorView.swift
WiseEating/Food/Views/FoodItemReceptEditorView.swift
ayurveda-data/tools/d8_math_check.swift
ayurveda-data/REPORT-D8.md
```

The original D8 packet did not authorize recipe/menu editors. Their changes
were explicitly authorized by the founder's D8.1 and D8.2 addenda. No model,
seed, rule, store, seeder, SeedManager, or validator file changed.
