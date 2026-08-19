# Catalogue / User Store Separation Report

Date: 2026-08-19  
Branch: `ayurveda-app`

## Outcome

The application now mounts two physical SwiftData stores in one container:

- a versioned, immutable catalogue for bundled food, exercise, yoga, practice,
  Ayurveda, barcode, nutrient-reference, and search-cache content;
- the existing `AyurvedaAsanaYoga.store` path as the writable user store.

Catalogue revisions are streamed from the split gzip archive to a staging
directory, checked against the manifest SHA-256/byte counts, migrated only in
staging, enriched with practice data, row-count validated, SQLite-integrity
checked, finalized with the exact two-configuration persistent model, assigned
a fresh Core Data store UUID, and atomically published. This finalization keeps
SwiftData from attempting a schema migration after the file is mounted
read-only.
The live catalogue is mounted with `allowsSave: false`.
After the replacement catalogue has mounted successfully, obsolete immutable
catalogue version directories are removed; the current catalogue and legacy
recovery backup are not cleanup targets.

The fresh store UUID is required because the bundled archive and an upgraded
legacy user store originate from the same old SQLite file. Without re-keying,
their persistent IDs collide. Simulator testing reproduced that failure and
then verified distinct user/catalogue identifiers and a normal application
launch after the fix.

## User-data preservation

The one-time migration keeps a recovery copy of the legacy store and converts
catalogue relationships to stable UUID references before batch-removing the
duplicated catalogue rows. Covered user-owned data includes:

- profiles, settings, meals, training logs, practice sessions, and measurements;
- user foods, recipes, menus, exercises, and workouts;
- meal plans and training plans;
- ingredient, storage, storage-history, shopping-list, recently-added, and
  meal-log references;
- node-linked foods and exercises;
- priority vitamins/minerals;
- user-authored Ayurveda profiles;
- catalogue food, exercise, and practice favorites through a writable
  `CatalogPreference` overlay.

Editing immutable catalogue foods/exercises/workouts creates a user-owned copy.
Because SwiftData stores configurations in an unordered set, declaration order
is not used for write routing. The combined-store factory tries equivalent
user-store URL representations and accepts a container only after real
insert/save/delete probes prove writable-store routing. A simulator regression
found that explicitly inserting every child did not cover SwiftData's implicit
relationship insertion used by the editors. The gate now reproduces the actual
transaction shapes: a food with eight implicitly discovered nutrition models,
an exercise with an implicit gallery photo, a recipe with photo and ingredient
links, a workout with exercise links, an Ayurveda override, and the search
cache. Every resulting persistent ID must belong to the writable store before
the container can reach the UI. The executable fixture separately verifies the
physical store identifier after saving new food and exercise rows.

## Update behavior

`CatalogMigrationState` is stored in the user database. After the one-time
separation, a catalogue revision update returns before catalogue UUID scans,
relationship conversion, or row deletion. Only the staged catalogue package is
replaced; a user search-cache copy is invalidated when necessary.

The final executable fixture measured the normal revision path at **0.0307 seconds**
with `normalUpdateReseeded=false`. A changed bundled catalogue still has a
one-time archive decompression and validation cost for that release, but it no
longer performs a long record-by-record preseed into the user's database.
A separate warm ordinary launch measured the catalogue/user-state check at
**0.516 seconds** and the first interactive frame at **2.182 seconds**. After
the editor-exact routing gate was added, a normal warm launch measured the
catalogue/user-state check at **0.531 seconds** and the combined-container open
at **0.340 seconds**. No catalogue row preseeding ran.

## Verification

- Actual legacy simulator migration: **642,207** duplicated catalogue rows
  batch-removed in about **17 seconds**, after creating the recovery backup.
- Executable SwiftData fixture creates records before separation and preserves:
  **5 food references**, **3 exercise references**, **3 favorite overlays**,
  profile/plans/storage/shopping/node/practice/nutrient state, and replacement
  catalogue resolution.
- The routing gate saves the exact food/exercise/recipe/workout editor graphs,
  including implicit nutrition and photo children, and rejects any container
  that targets the read-only catalogue. The fixture also inserts and saves a
  new food and exercise and asserts both persistent IDs belong to the user
  store.
- The real Add Food UI regression opens the editor, enters a unique food and
  serving weight, materializes the complete nutrition relationship graph,
  saves successfully without an Error alert, and returns to the food list.
- Clean catalogue install and changed-catalogue replacement both logged
  `Catalog replaced atomically; user store was not reseeded.`
- Warm normal launch logged Yoga/practices/barcodes/foods/Ayurveda as already
  installed and skipped the search-index rebuild.
- Installed catalogue counts: 14,487 foods; 908 exercises; 4,419 yoga
  sequences; 60 practices; 601 practice cues.
- `test_catalog_separation.py` + `test_we2_preseed.py`: **22/22 passed**.
- `testCreateFoodWithNutritionGraph`: **passed** on the iPhone 17 simulator.
- Debug and Release simulator builds: passed.

The repository-wide discovery run executed 210 tests. It had two failures and
two errors in untouched WE-3/MP-5/MP-6 tests, plus one skip; their UI string
expectations and solver/narration fixtures are outside this database change.
They are reported here rather than hidden or modified to force a green result.
