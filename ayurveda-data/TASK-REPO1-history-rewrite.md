# TASK REPO-1 — strip derived artefacts from history

Director packet · 2026-07-28 · branch `ayurveda-app`, remote `origin`

**This is the only destructive task in the project.** It rewrites every commit on
every branch and requires a force-push, which suspends the standing no-force-push
rule for this task and this task only. Read the whole packet before running
anything.

---

## 1. What and why

`.git` is 1.4 GB. Measured composition, all revisions summed:

| path | total | commits | kind |
|---|---:|---:|---|
| `WiseEating/preseeded_db.store.gz.part-aa` | 490.0 MB | 7 | derived |
| `…/xcuserdata/…/UserInterfaceState.xcuserstate` | 294.7 MB | 103 | noise |
| `WiseEating/preseeded_db.store.gz.part-ab` | 139.4 MB | 7 | derived |
| `WiseEating/Food/food_archive_480.mp4` | 78.9 MB | 1 | derived |
| `WiseEating/Legacy/foods.json` | 65.6 MB | 1 | **source** |
| `WiseEating/Legacy/product_buckets.json` | 62.6 MB | 1 | **source** |
| `WiseEating/Food/food_archive_144.mp4` | 35.8 MB | 1 | derived |
| `WiseEating/Legacy/vocabulary.json` | 12.8 MB | 1 | **source** |

**The rule is strip derived, keep source.** Everything removed here is
reproducible from something that stays: the database from the Legacy JSONs via
`SeedManager`, the video archives from `extra_images.zip`, and the Xcode UI state
from nothing at all because it is not data.

The Legacy JSONs stay tracked. They are 141 MB but committed **once each** and
never re-committed, and they are the only source the food database has —
`foods_names_with_id.csv` carries id and name with no nutrition, so it cannot
replace `foods.json`. Stripping them would make the database unbuildable from a
clone, which is the opposite of the goal.

Expected result: **1.4 GB → roughly 360 MB**, with every commit, message, author
and date preserved.

---

## 2. Order — do not reorder these

### Phase A — get everything committed first

REPO-1 cannot start with a dirty tree, and a generation loop is currently writing
into `ayurveda-data/imagery/`. Complete the untracked-work commit and push
first (imagery pipeline with its `.gitignore`, `tests/val1_device_driver/`,
`evidence/`, `TASK-VAL1.md`, `VAIDYA-REVIEW.md`, `tools/style-reference.png`,
modified `tools/ref_resolve.py`). Nothing below runs until `git status` is clean.

**Stop the generation loop before Phase C** and restart it after Phase E.

### Phase B — back up, and prove the backup

    git clone --mirror <origin-url> ~/wise-eating-BACKUP-<date>.git
    git -C ~/wise-eating-BACKUP-<date>.git rev-list --all --count

Record that count. Also copy the current working versions of every file about to
be stripped somewhere outside the repo — `~/wise-eating-assets/` — because
filter-repo removes a path from **all** commits including HEAD, so these
disappear from the working tree too:

    WiseEating/preseeded_db.store.gz.part-aa
    WiseEating/preseeded_db.store.gz.part-ab
    WiseEating/Food/food_archive_480.mp4
    WiseEating/Food/food_archive_144.mp4

Verify each copy's sha256 against the original before continuing. **Do not
proceed until the mirror exists and the four checksums match.**

### Phase C — rewrite

Run `git filter-repo` on a **fresh clone**, not on the working repo:

    --path WiseEating/preseeded_db.store.gz.part-aa \
    --path WiseEating/preseeded_db.store.gz.part-ab \
    --path WiseEating/Food/food_archive_480.mp4 \
    --path WiseEating/Food/food_archive_144.mp4 \
    --path-glob '*.xcuserstate' \
    --path-glob '*/xcuserdata/*' \
    --invert-paths

**Preserve `.git/filter-repo/commit-map`.** Copy it to
`ayurveda-data/REPO1-commit-map.txt` and commit it. Phase D depends on it and it
is not regenerable once the intermediate clone is gone.

### Phase D — repair what the rewrite breaks

**D1 — commit references in the docs.** Every SHA changes. These files anchor
measurements to specific commits and become wrong the moment the rewrite lands:

- `ayurveda-data/STATUS-meal-generation.md`
- `ayurveda-data/DEFERRED-VALIDATION.md`
- `ayurveda-data/TASK-VAL1.md` — `d0dfc38`, `161689e`, `37552c0`, `247dfa8`,
  `d393bda`, `5af9b91`
- `ayurveda-data/TASK-IMG2.md` — base `5af9b91`
- any MP report referencing a commit

Grep the whole repo for 7-hex-digit strings, map each through
`REPO1-commit-map.txt`, rewrite it. **Report the count of references rewritten
and any that had no mapping** — an unmapped SHA means a measurement lost its
anchor and that is a finding, not a nit.

**D2 — restore the assets locally.** Copy the four files from
`~/wise-eating-assets/` back to their original paths. They are now untracked.
Add to `.gitignore`:

    WiseEating/Food/food_archive*.mp4
    WiseEating/preseeded_db.store.gz.part-*
    .DS_Store

**D3 — make their absence loud.** The project uses
`PBXFileSystemSynchronizedRootGroup`, so a missing archive produces **no build
error** — it produces an app that launches with no food imagery and no seeded
database. Add:

- `WiseEating/Food/assets-manifest.json`, tracked, listing filename, sha256, byte
  size, frame count and producing commit for each archive and each db part;
- `tools/check-assets.sh`, verifying every manifest entry exists and matches, exit
  non-zero listing what is missing;
- that script as a Run Script build phase **before** Copy Bundle Resources.

Without D3 this task converts a loud problem into a silent one.

### Phase E — publish

    git push --force --all
    git push --force --tags

Then delete every existing local clone and re-clone. A stale clone still holding
old objects will push them straight back on the next merge and undo the whole
task.

---

## 3. Gates

| Gate | Requirement |
|---|---|
| **R1** | mirror backup exists, `rev-list --all --count` matches pre-rewrite |
| **R2** | commit count identical before and after; only blobs removed, never commits |
| **R3** | `git ls-files \| xargs ls -l \| awk '$5>90000000'` prints nothing |
| **R4** | `.git` under 400 MB after `git gc --prune=now --aggressive` |
| **R5** | every doc SHA reference resolves in the rewritten history; report unmapped count (expect 0) |
| **R6** | `tools/check-assets.sh` passes with assets present, and **fails** with one removed — test both directions |
| **R7** | app builds and launches with seeded database and working food imagery |
| **R8** | 150/150 tests, Debug and Release |
| **R9** | Legacy JSONs still tracked and intact — `git ls-files WiseEating/Legacy` returns all five |

Stop and report on R2 or R5. R2 failing means commits were lost. R5 failing means
the measurement record lost its anchors — both are worse than a large repo.

---

## 4. After this — the database rebuild

Decision recorded: **commit the database only at milestones**, split into
sub-100 MB parts, no LFS. Day-to-day rebuilds stay local and gitignored.

The rebuild path is `Legacy/*.json` → `SeedManager` (first launch) → store →
`ayurveda-data/build_preseeded_store.py --source-store …`. Note that
`build_preseeded_store.py` compresses and splits an existing store; it does not
build one from CSV. Rebuilding "from fresh source" means re-seeding from the
Legacy JSONs, not from `foods_names_with_id.csv`.

Each milestone commit adds ~89 MB permanently. At roughly two per year that is
sustainable; at one per week it is not, and the answer then is Release assets
rather than a second rewrite.

---

## 5. Protocol

One commit per phase, prefix `REPO-1a:` etc. Report every gate with its measured
number. Stop and report on failure; never fix a gate by loosening it.

**Do not start Phase C until Phase A is pushed, the loop is stopped, and Phase B's
checksums match.** Everything before Phase C is reversible. Nothing after it is,
except from the backup.

---

## 6. AMENDMENT — 2026-07-28, after R5 stopped the run

R5 failed with 229 mappable references and 8 occurrences of 4 unique SHAs that
`commit-map` could not map. Codex stopped correctly and asked for direction.

### What was actually wrong

The four commits — `e9a3a95`, `e8d1b3e`, `3ba69eb`, `3801eee` — were **never
pushed to origin**. They lived only in one local clone's reflog, unreachable from
any branch. So they were absent from the mirror and from the rewrite because they
had never been part of the canonical history at all.

Which means **the rewrite did not break those four references. They were already
unresolvable from any clone of origin, before REPO-1 ran.** R5 surfaced a
pre-existing documentation defect and attributed it to the rewrite.

Every file touched by all four is present in current HEAD — verified file by
file, zero absent. A rebase carried the work forward and orphaned the commit
objects. The work was never at risk; only the four SHAs were.

### Two defects in this packet, now fixed

**Phase B backed up the wrong thing.** `git clone --mirror <origin-url>` captures
origin, not the local clone. The four commits existed *only* in the local clone,
so R1 passed with a backup that did not contain them.

**Gate R4 would have destroyed them.** `git gc --prune=now --aggressive` deletes
unreachable objects immediately. Running R4 before noticing these would have
removed all four permanently, and the R1 backup would not have helped.

Both are now moot: the four commits are preserved as self-contained patches in
`ayurveda-data/archive/pre-repo1-orphans/` (3.8 MB, committed), with a README
explaining what they are. R4 is safe to run once that directory is committed.

### R5, restated

R5 stays absolute for the 229 mappable references: **every one must resolve in
the rewritten history, unmapped count 0.** That is unchanged and non-negotiable.

The four orphans are removed from R5's scope and handled as their own defect,
because they were never in the canonical history R5 is about. This is a
correction to a gate whose premise was wrong, not a relaxation of a gate that
proved inconvenient — the test being that the fix makes the documentation *more*
accurate than it was before REPO-1 started, not less.

**Do not** import the orphans into the rewritten history to make them resolve.
They were deliberately never pushed, and rewriting would change their SHAs anyway,
so it would not satisfy R5 even at the cost of polluting the history.

### D1, amended

For the 229 mappable references: map through `REPO1-commit-map.txt` as specified.

For the 8 occurrences of the 4 orphans, in `REPORT-D6-VERIFY.md:61` and
`TASK-D6-VERIFY.md:13`, replace the bare SHA with an annotation naming it as a
pre-REPO-1 local-only commit and pointing at the preserved patch, e.g.

    e8d1b3e (pre-REPO-1 local-only commit, never on origin; preserved at
    ayurveda-data/archive/pre-repo1-orphans/02-e8d1b3e-d6-schema-seeder.patch)

Report the two counts separately: mappable rewritten, and orphans annotated.

### New gate

| Gate | Requirement |
|---|---|
| **R10** | `ayurveda-data/archive/pre-repo1-orphans/` committed with 4 patches and README before any `git gc --prune` runs; each patch's Subject matches its filename |
