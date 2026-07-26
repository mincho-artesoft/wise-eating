# FC-1d — artifact-size gate stop

Date: 2026-07-26
Branch: `fc-1c-g12-rulings` at `3778e6d`
Status: **STOPPED BEFORE PART A IMPLEMENTATION**

## Finding

The new founder rule says:

> No shipped artifact file may exceed 100 MB; split at 90 MB.

The current shipping target contains:

| Shipped resource | Bytes | Decimal MB | MiB | Gate |
|---|---:|---:|---:|---|
| `WiseEating/Food/food_archive_1024.mp4` | **285,519,148** | **285.519** | **272.292** | **STOP — exceeds 90 MB and 100 MB** |
| `WiseEating/Food/food_archive_480.mp4` | 82,726,160 | 82.726 | 78.894 | Pass |
| `WiseEating/Food/food_archive_144.mp4` | 37,571,026 | 37.571 | 35.831 | Pass |
| `WiseEating/preseeded_db.store.gz.part-aa` | 73,400,320 | 73.400 | 70.000 | Pass |
| `WiseEating/preseeded_db.store.gz.part-ab` | 19,125,561 | 19.163 | 18.275 | Pass |

The task premise that the preseed parts are the only artifacts near the limit
is therefore false in this working copy. The 1024 archive is more than three
times the split threshold and more than twice the hard ceiling.

## Shipping evidence

This is not merely an unused local file:

1. `WiseEating.xcodeproj/project.pbxproj` declares `WiseEating/` as a
   `PBXFileSystemSynchronizedRootGroup`.
2. The target's only membership exception is `Info.plist`; the video is not
   excluded.
3. The exact 285,519,148-byte file is present in both built products:
   - `Build/Products/Debug-iphonesimulator/WiseEating.app/food_archive_1024.mp4`
   - `Build/Products/Release-iphonesimulator/WiseEating.app/food_archive_1024.mp4`
4. Prior FC-1 launch evidence also explicitly recorded that the ignored local
   285 MB video was copied into the candidate bundle.

The source video is intentionally ignored by Git, but ignore status does not
change synchronized target membership or the resulting app bundle.

## Why no automatic correction was made

Splitting, replacing, removing, or excluding the video changes media packaging
and possibly runtime lookup behavior. FC-1d authorizes ontology matching,
planner wiring, and splitting oversized preseed parts; it does not authorize a
media packaging change. The stop condition is explicit: **any artifact exceeds
90 MB**.

The founder must choose one of these follow-ups:

- supply a split 1024 archive plus the intended runtime lookup contract;
- explicitly exclude the 1024 archive from the shipping target;
- replace it with a compliant resource; or
- amend the standing rule with a precise media exemption.

No option was inferred.

## Director inputs preserved

The founder-written inputs were parsed and retained byte-for-byte:

| Input | SHA-256 | Parsed state |
|---|---|---|
| `ayurveda-data/rules/food-concepts.json` | `e9ab96625bf0abcec1015a633dd1b2adb59dfabfb53d8b9612103df3d4e29913` | rev4, 25 concepts, 75 aliases, 8 concepts with `vetoTokens` |
| `ayurveda-data/tests/exclusion-goldens.json` | `db0c331132001543fd4baf18ab83abcd28b5b109b5a66be53a47b19ca8240ec8` | rev3, 81 must-exclude, 36 must-not-exclude, 7 contested |

They were not edited by the executor.

## Work and gates not run

The stop was detected during the required shipped-artifact inventory, before
Part A code changes:

- `vetoTokens` matching was not implemented.
- FC-1 gates were not rerun against rev4.
- FC-2 planner wiring was not started.
- Resolver aliases were not wired.
- Generated seed, concept, preseed, and search artifacts were not rebuilt.
- Build, test, validator, resolution, search, fresh-install, determinism, and
  cold-launch gates were not run.
- The handbook was not advanced to claim an unenforced standing gate.
- The ignored 1024 archive and unrelated untracked status note were not
  modified.

Resume FC-1d only after the oversized shipped resource has a founder-authorized
disposition.
