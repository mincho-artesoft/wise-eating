# TASK D6-VERIFY — Mac-side execution: git hygiene, push, build & boot gates
(executor: Codex on the founder's Mac; requires Xcode + iOS Simulator)

The director verified everything sandbox-verifiable (determinism, counts, model
conformance, seeder logic). Your job is the Mac-only remainder. You EXECUTE and
RECORD; you do not fix. Any failure → capture verbatim output in the report and
STOP that phase. Never modify source files. Never force-push anything.

## Phase 0 — Git hygiene and branch layout (do first)

1. `rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock 2>/dev/null; find .git/objects -name "tmp_obj_*" -delete 2>/dev/null; git reset`
2. Verify layout and record output of `git branch -v` and `git log --oneline -3 ayurveda-app`:
   - `main` must be at the same commit as `origin/main` (3801eee (pre-REPO-1 local-only commit, never on origin; preserved at ayurveda-data/archive/pre-repo1-orphans/04-3801eee-dravyas.patch))
   - `ayurveda-app` must contain e9a3a95 (pre-REPO-1 local-only commit, never on origin; preserved at ayurveda-data/archive/pre-repo1-orphans/01-e9a3a95-d6-design.patch) and e8d1b3e (pre-REPO-1 local-only commit, never on origin; preserved at ayurveda-data/archive/pre-repo1-orphans/02-e8d1b3e-d6-schema-seeder.patch) on top of it
   - HEAD must be on `ayurveda-app`
   If layout differs, STOP and report — do not "fix" branches.
3. `git push -u origin ayurveda-app` (plain push; abort and report if git proposes force).
4. Confirm `git status` is clean apart from .DS_Store noise.

## Phase 1 — Build gate (branch: ayurveda-app)

1. `xcodebuild -list -project WiseEating.xcodeproj` — record schemes.
2. Build for simulator with the app scheme:
   `xcodebuild -project WiseEating.xcodeproj -scheme <APP_SCHEME> -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build`
   (pick an available device from `xcrun simctl list devices available` if iPhone 16 is absent).
3. Record: exit code, and on failure the LAST 100 lines verbatim. A failed build
   stops Phases 2–4; still do Phase 5 report.

## Phase 2 — Fresh-install seeding gate

1. Boot a fresh simulator (`xcrun simctl erase` an available device first, then boot).
2. Install and launch the Debug app; capture console via
   `xcrun simctl launch --console-pty <UDID> <BUNDLE_ID> | tee /tmp/d6_fresh.log` (or `simctl spawn log stream --predicate 'processImagePath contains "WiseEating"'`).
3. PASS criteria (all must appear / hold):
   - log contains the Ayurveda seeding path: "Checking for Ayurveda data" and NO "seeding failed"
   - app does not crash within 60s of first launch
4. Data spot-checks (record method + output). Preferred: query the app's store —
   find the sqlite under the simulator container and run:
   `sqlite3 <store> "select count(*) from ZAYURVEDAPROFILE"` → expect 2214
   `sqlite3 <store> "select count(*) from ZAYURVEDALINK"` → expect 336
   `sqlite3 <store> "select count(*) from ZFOODITEM where ZID between 900001 and 900383"` → expect 383
   `sqlite3 <store> "select count(*) from ZFOODITEM where ZISRECIPE=1"` → expect 1500

## Phase 3 — Idempotency gate

Terminate and relaunch the app twice. Each launch log must show the skip path
("already seeded" / "already applied") and the sqlite counts from Phase 2 must be
unchanged. Record both launch logs' relevant lines.

## Phase 4 — Upgrade-path gate

1. `git checkout main` → build the ORIGINAL app (same scheme) → install & launch
   on the same simulator (do NOT erase). Add a little user data if scriptable
   (optional; skippable).
2. `git checkout ayurveda-app` → build → install OVER the existing app → launch.
3. PASS: no crash, no migration error in logs, seeding fires exactly once
   (Phase 2 criteria), pre-existing store content intact (ZFOODITEM count =
   12601 + 383 + 1500 = 14484 total).
4. Return the checkout to `ayurveda-app` when done.

## Phase 5 — Report, then STOP

Write `ayurveda-data/REPORT-D6-VERIFY.md`: per-phase PASS/FAIL, every command
run, verbatim key outputs (build tail on failure, seeding log lines, sqlite
counts), simulator/Xcode versions, and an honest "not done" list for anything
skipped. Commit it on ayurveda-app ("D6-VERIFY: Mac execution report") and push
the branch. Do not touch main. Do not fix any failure — the director triages.
