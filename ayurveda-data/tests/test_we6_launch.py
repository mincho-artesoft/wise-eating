import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ROOT_LAUNCHER = ROOT / "WiseEating" / "Main" / "RootLauncher.swift"
DATABASE_SETUP = ROOT / "WiseEating" / "Main" / "DBSeed" / "DatabaseSetup.swift"
SEARCH_ENGINE = (
    ROOT
    / "WiseEating"
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
        self.assertIn(
            "await SearchIndexStore.shared.ensureLoaded(container: container)",
            source,
        )
        ensure_offset = source.index(
            "await SearchIndexStore.shared.ensureLoaded(container: container)"
        )
        apply_offset = source.index("applyLoadedIndex()", ensure_offset)
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
        self.assertIn('"-we6LaunchProfile"', source)
        self.assertIn("os_signpost(.event", source)


if __name__ == "__main__":
    unittest.main()
