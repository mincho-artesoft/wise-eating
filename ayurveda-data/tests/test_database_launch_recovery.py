import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
AYURA = ROOT / "Ayura"
DATABASE_SETUP = AYURA / "Main" / "DBSeed" / "DatabaseSetup.swift"
APP_ENTRY = AYURA / "Main" / "AyurvedaAsanaYogaApp.swift"
STORE_FACTORY = AYURA / "Main" / "DBSeed" / "CombinedStoreFactory.swift"
REFERENCE_RESOLVER = (
    AYURA / "Main" / "DBSeed" / "CatalogReferenceResolver.swift"
)


class DatabaseLaunchRecoveryTests(unittest.TestCase):
    def test_database_startup_never_uses_a_fatal_error(self):
        source = DATABASE_SETUP.read_text(encoding="utf-8")
        self.assertNotIn("fatalError", source)
        self.assertIn("DatabaseLaunchState", source)
        self.assertIn("static func unavailable", source)

    def test_primary_failure_falls_back_to_a_distinct_writable_store(self):
        source = DATABASE_SETUP.read_text(encoding="utf-8")
        primary_failure = source.index("Primary database startup failed")
        recovery_open = source.index(
            "makeRecoveryContainer(", primary_failure
        )
        recovery_marker = source.index(
            "UserDefaults.standard.set(", recovery_open
        )
        self.assertLess(primary_failure, recovery_open)
        self.assertLess(recovery_open, recovery_marker)
        self.assertIn('"AyurvedaAsanaYogaRecovery.store"', source)
        self.assertIn("PreseedLoader.preparePreseededStore", source)
        self.assertIn("allowsSave: true", source)

    def test_recovery_mode_does_not_delete_the_primary_user_store(self):
        source = DATABASE_SETUP.read_text(encoding="utf-8")
        recovery = source[
            source.index("private static func makeRecoveryContainer") :
            source.index("private static func unavailableState")
        ]
        self.assertNotIn('"AyurvedaAsanaYoga.store"', recovery)
        self.assertNotIn("removeItem(at: userStoreURL)", recovery)

    def test_app_can_render_when_all_database_modes_fail(self):
        source = APP_ENTRY.read_text(encoding="utf-8")
        self.assertIn("if let container = database.container", source)
        self.assertIn("DatabaseUnavailableView", source)
        self.assertIn("Your existing data has not been deleted", source)

    def test_single_store_recovery_supports_user_write_contexts(self):
        factory = STORE_FACTORY.read_text(encoding="utf-8")
        resolver = REFERENCE_RESOLVER.read_text(encoding="utf-8")
        self.assertIn("configurations.count == 1", factory)
        self.assertIn("static func reset()", resolver)
        self.assertIn("CatalogReferenceResolver.reset()", DATABASE_SETUP.read_text())


if __name__ == "__main__":
    unittest.main()
