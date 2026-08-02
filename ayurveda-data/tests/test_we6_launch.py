import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ROOT_LAUNCHER = ROOT / "Ayura" / "Main" / "RootLauncher.swift"
DATABASE_SETUP = ROOT / "Ayura" / "Main" / "DBSeed" / "DatabaseSetup.swift"
SEARCH_ENGINE = (
    ROOT
    / "Ayura"
    / "FoodSearch"
    / "VM"
    / "SmartFoodSearchEngine.swift"
)


class WE6LaunchTests(unittest.TestCase):
    def test_root_launch_does_not_eagerly_decode_search_index(self):
        source = ROOT_LAUNCHER.read_text(encoding="utf-8")
        self.assertNotIn(
            "SearchIndexStore.shared.ensureLoaded(container: container)",
            source,
        )
        self.assertIn('event("search-index-load-deferred")', source)

    def test_programmatic_search_awaits_the_lazy_index_load(self):
        source = SEARCH_ENGINE.read_text(encoding="utf-8")
        self.assertEqual(source.count("await loadDataAndWait()"), 3)
        load_and_wait = source[
            source.index("private func loadDataAndWait()") :
            source.index("private func applyLoadedIndex()")
        ]
        self.assertIn("await prepareForSearch()", load_and_wait)

        prepare = source[
            source.index("func prepareForSearch()") :
            source.index("private func loadDataAndWait()")
        ]
        self.assertIn("await store.ensureLoaded(container: container)", prepare)
        ensure_offset = prepare.index(
            "await store.ensureLoaded(container: container)"
        )
        apply_offset = prepare.index("applyLoadedIndex()", ensure_offset)
        self.assertLess(ensure_offset, apply_offset)

    def test_view_load_wrapper_remains_nonblocking(self):
        source = SEARCH_ENGINE.read_text(encoding="utf-8")
        wrapper = source[
            source.index("func loadData()"):
            source.index("private func loadDataAndWait()")
        ]
        self.assertIn("Task { await loadDataAndWait() }", wrapper)

    def test_launch_probe_is_opt_in(self):
        source = DATABASE_SETUP.read_text(encoding="utf-8")
        self.assertIn('arguments.contains(', source)
        self.assertIn('"-ayuraLaunchProfile"', source)
        self.assertIn("os_signpost(.event", source)

    def test_warm_ayurveda_version_check_avoids_full_seed_decode(self):
        source = (
            ROOT
            / "Ayura"
            / "Main"
            / "DBSeed"
            / "AyurvedaSeeder.swift"
        ).read_text(encoding="utf-8")
        version_check = source.split(
            "static func bundleSeedVersion() throws -> Int {", 1
        )[1].split("\n  }", 1)[0]
        self.assertIn("AyurvedaSeedVersionDTO.self", version_check)
        self.assertIn("loadSeedData()", version_check)
        self.assertNotIn("loadSeed()", version_check)


if __name__ == "__main__":
    unittest.main()
