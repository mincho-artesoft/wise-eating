import hashlib
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
AYURA = ROOT / "Ayura"


class CatalogManifestTests(unittest.TestCase):
    def test_manifest_matches_every_bundled_archive_part(self):
        manifest = json.loads((AYURA / "catalog_manifest.json").read_text())
        self.assertEqual(manifest["formatVersion"], 1)
        self.assertGreater(manifest["catalogVersion"], 0)
        self.assertTrue(manifest["contentRevision"])

        manifest_names = {part["resource"] for part in manifest["parts"]}
        disk_names = {
            path.name for path in AYURA.glob("preseeded_db.store.gz.part-*")
        }
        self.assertEqual(manifest_names, disk_names)

        for part in manifest["parts"]:
            path = AYURA / part["resource"]
            digest = hashlib.sha256()
            size = 0
            with path.open("rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    size += len(chunk)
                    digest.update(chunk)
            self.assertEqual(size, part["byteCount"])
            self.assertEqual(digest.hexdigest(), part["sha256"])

    def test_manifest_covers_all_catalog_domains(self):
        expected = json.loads(
            (AYURA / "catalog_manifest.json").read_text()
        )["expected"]
        self.assertGreater(expected["foods"], 10_000)
        self.assertGreater(expected["exercises"], 800)
        self.assertGreater(expected["yogaSequences"], 4_000)
        self.assertGreater(expected["practices"], 50)
        self.assertGreater(expected["practiceCues"], 500)
        self.assertGreater(expected["ayurvedaProfiles"], 2_000)
        self.assertGreater(expected["ayurvedaLinks"], 2_000)


class CatalogSeparationWiringTests(unittest.TestCase):
    def test_two_physical_stores_and_read_only_catalog_are_wired(self):
        setup = (AYURA / "Main/DBSeed/DatabaseSetup.swift").read_text()
        self.assertIn("CombinedStoreFactory.makeContainer", setup)

        router = (
            AYURA / "Main/DBSeed/CombinedStoreFactory.swift"
        ).read_text()
        self.assertIn("allowsSave: false", router)
        self.assertIn("verifyWritableRouting", router)
        self.assertIn('"../../../\\(userStoreURL.lastPathComponent)"', router)
        for routed_model in [
            "MacronutrientsData",
            "LipidsData",
            "VitaminsData",
            "MineralsData",
            "OtherCompoundsData",
            "AminoAcidsData",
            "CarbDetailsData",
            "SterolsData",
            "FoodPhoto",
            "ExercisePhoto",
            "AyurvedaProfile",
            "SearchIndexCache",
        ]:
            self.assertIn(routed_model, router)
        self.assertIn("persistentModelID.storeIdentifier", router)
        self.assertIn("Match FoodItemEditorView exactly", router)
        self.assertIn("food.macronutrients = macronutrients", router)
        self.assertIn("exercise.gallery = [exercisePhoto]", router)
        self.assertIn("recipe.gallery = [foodPhoto]", router)

    def test_normal_update_returns_before_row_migration(self):
        separator = (
            AYURA / "Main/DBSeed/LegacyStoreSeparator.swift"
        ).read_text()
        state_guard = separator.index("state.separationVersion >= separationVersion")
        catalog_id_scan = separator.index("let catalogFoodIDs")
        self.assertLess(state_guard, catalog_id_scan)
        self.assertIn("performedMigration: false", separator[state_guard:catalog_id_scan])

    def test_user_references_cover_food_exercise_plans_and_profiles(self):
        separator = (
            AYURA / "Main/DBSeed/LegacyStoreSeparator.swift"
        ).read_text()
        required_models = [
            "IngredientLink",
            "MealPlanEntry",
            "ShoppingListItem",
            "RecentlyAddedFood",
            "StorageItem",
            "StorageTransaction",
            "MealLogStorageLink",
            "ExerciseLink",
            "TrainingPlanExercise",
            "Node",
            "Profile",
            "Practice",
            "YogaSequence",
        ]
        for model in required_models:
            with self.subTest(model=model):
                self.assertIn(f"FetchDescriptor<{model}>", separator)

    def test_catalog_install_is_staged_validated_and_atomic(self):
        manager = (AYURA / "Main/DBSeed/CatalogStoreManager.swift").read_text()
        self.assertIn("validateBundledParts", manager)
        self.assertIn("migrateAndValidateStore", manager)
        self.assertIn("finalizeForCombinedMount", manager)
        self.assertIn("checkpointAndValidateSQLite", manager)
        self.assertIn("replaceItemAt", manager)
        self.assertIn("installedNewCatalog: false", manager)

        loader = (AYURA / "Main/DBSeed/PreseedLoader.swift").read_text()
        self.assertIn("ZlibGzip.decompressFile", loader)

    def test_catalog_store_is_rekeyed_before_mounting(self):
        manager = (AYURA / "Main/DBSeed/CatalogStoreManager.swift").read_text()
        rekey = manager.index("assignFreshStoreIdentifier")
        publish = manager.index("let incomingDirectory")
        self.assertLess(rekey, publish)
        self.assertIn("UPDATE Z_METADATA SET Z_UUID = ?", manager)
        self.assertIn("NSStoreUUIDKey", manager)

    def test_obsolete_catalogs_are_removed_only_after_combined_store_opens(self):
        setup = (AYURA / "Main/DBSeed/DatabaseSetup.swift").read_text()
        container_open = setup.index(
            "let container = try CombinedStoreFactory.makeContainer"
        )
        cleanup = setup.index("removeObsoleteVersions")
        self.assertLess(container_open, cleanup)

        manager = (AYURA / "Main/DBSeed/CatalogStoreManager.swift").read_text()
        self.assertIn("candidate.standardizedFileURL != currentDirectory", manager)
        self.assertIn('candidate.lastPathComponent.hasPrefix("v")', manager)

    def test_executable_smoke_test_creates_records_before_separation(self):
        smoke = (
            AYURA / "Main/DBSeed/CatalogSeparationSmokeTestRunner.swift"
        ).read_text()
        for marker in [
            "Migration User",
            "User Food",
            "User Recipe",
            "User Exercise",
            "User Workout",
            "User Meal Plan",
            "User Training Plan",
            "new food/exercise writes were not routed to the user store",
            "normalUpdateReseeded=false",
        ]:
            with self.subTest(marker=marker):
                self.assertIn(marker, smoke)


if __name__ == "__main__":
    unittest.main()
