import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FOOD_SEARCH = ROOT / "Ayura" / "FoodSearch"
BOUNDARY = FOOD_SEARCH / "Constraints" / "ConstraintQueryBoundary.swift"
PH_SEMANTICS = FOOD_SEARCH / "Structs" / "PhSearchSemantics.swift"
CONSTRAINT_VALUE = FOOD_SEARCH / "Structs" / "ConstraintValue.swift"
SEARCH_CONTEXT = FOOD_SEARCH / "Structs" / "SearchContext.swift"
SEARCH_ENGINE = FOOD_SEARCH / "VM" / "SmartFoodSearchEngine.swift"
SEARCH_VIEW = FOOD_SEARCH / "FoodSearchView.swift"


class WE5SearchBorderCaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="we5-search-tests-")
        cls.temporary_root = Path(cls.temporary.name)
        cls.harness_binary = cls.temporary_root / "we5-helper-harness"
        harness = cls.temporary_root / "WE5HelperHarness.swift"
        harness.write_text(
            """
import Foundation

final class SearchKnowledgeBase: @unchecked Sendable {
    static let shared = SearchKnowledgeBase()
    private let subjects: Set<String> = [
        "caffeine", "dairy", "fat", "gluten", "salt", "sodium", "sugar"
    ]

    func isValidSubject(_ raw: String) -> Bool {
        subjects.contains(raw.lowercased())
    }
}

@main
struct WE5HelperHarness {
    static func main() throws {
        let arguments = CommandLine.arguments
        switch arguments[1] {
        case "boundary":
            let query = arguments[2]
            let boundary = ConstraintQueryBoundary(query)
            let payload: [String: Any] = [
                "tokens": boundary.tokens,
                "phCount": boundary.count(of: "ph"),
                "hasNo": boundary.containsToken("no"),
                "hasFreeConstraint": boundary.containsFreeConstraint(),
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            FileHandle.standardOutput.write(data)
        case "ph":
            let value = Double(arguments[2])!
            let constraint: ConstraintValue
            switch arguments[3] {
            case "high": constraint = .high
            case "low": constraint = .low
            case "neutral":
                constraint = .range(
                    PhSearchSemantics.neutralLowerBound,
                    PhSearchSemantics.neutralUpperBound
                )
            case "lowest": constraint = .lowest
            default: fatalError("Unknown pH constraint")
            }
            let payload: [String: Any] = [
                "hasData": PhSearchSemantics.hasData(value),
                "matches": PhSearchSemantics.matches(
                    value,
                    constraint: constraint
                ),
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            FileHandle.standardOutput.write(data)
        default:
            fatalError("Unknown harness mode")
        }
    }
}
""",
            encoding="utf-8",
        )
        subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library",
                str(CONSTRAINT_VALUE),
                str(PH_SEMANTICS),
                str(BOUNDARY),
                str(harness),
                "-o",
                str(cls.harness_binary),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def boundary_result(self, query):
        result = subprocess.run(
            [str(self.harness_binary), "boundary", query],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)

    def ph_result(self, value, constraint):
        result = subprocess.run(
            [
                str(self.harness_binary),
                "ph",
                str(value),
                constraint,
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)

    def test_ph_is_detected_only_as_a_standalone_token(self):
        cases = [
            ("ph", 1),
            ("high ph foods", 1),
            ("high phosphorus", 0),
            ("sulphate water", 0),
            ("phyllo pastry", 0),
        ]
        for query, expected_count in cases:
            with self.subTest(query=query):
                self.assertEqual(
                    self.boundary_result(query)["phCount"],
                    expected_count,
                )

    def test_no_is_detected_as_a_token_including_query_final_position(self):
        cases = [
            ("salt no", True),
            ("no salt", True),
            ("nori", False),
            ("quinoa", False),
        ]
        for query, expected in cases:
            with self.subTest(query=query):
                self.assertEqual(
                    self.boundary_result(query)["hasNo"],
                    expected,
                )

    def test_free_constraints_require_a_known_compound_subject(self):
        cases = [
            ("gluten free bread", True),
            ("fat-free yogurt", True),
            ("free of sodium soup", True),
            ("sugar free", True),
            ("freeze-dried berries", False),
            ("freezer meal", False),
            ("free standing shelf", False),
        ]
        for query, expected in cases:
            with self.subTest(query=query):
                self.assertEqual(
                    self.boundary_result(query)["hasFreeConstraint"],
                    expected,
                )

    def test_directional_ph_boundary_is_exclusive_at_seven(self):
        self.assertFalse(self.ph_result(7.0, "high")["matches"])
        self.assertFalse(self.ph_result(7.0, "low")["matches"])
        self.assertTrue(self.ph_result(7.0, "neutral")["matches"])
        self.assertTrue(self.ph_result(7.01, "high")["matches"])
        self.assertTrue(self.ph_result(6.99, "low")["matches"])

    def test_neutral_ph_range_includes_both_existing_bounds(self):
        self.assertTrue(self.ph_result(6.5, "neutral")["matches"])
        self.assertTrue(self.ph_result(7.5, "neutral")["matches"])
        self.assertFalse(self.ph_result(6.49, "neutral")["matches"])
        self.assertFalse(self.ph_result(7.51, "neutral")["matches"])

    def test_zero_ph_sentinel_is_never_filterable_or_sortable(self):
        for constraint in ("high", "low", "neutral", "lowest"):
            with self.subTest(constraint=constraint):
                result = self.ph_result(0.0, constraint)
                self.assertFalse(result["hasData"])
                self.assertFalse(result["matches"])

    def test_missing_constrained_nutrient_chip_renders_dash_with_no_data_label(self):
        source = SEARCH_VIEW.read_text(encoding="utf-8")
        constrained_start = source.index(
            "if !engine.searchContext.displayNutrients.isEmpty"
        )
        constrained_end = source.index(
            "} else {\n                HStack {",
            constrained_start,
        )
        constrained = source[constrained_start:constrained_end]
        self.assertIn(
            "ForEach(engine.searchContext.displayNutrients",
            constrained,
        )
        self.assertIn('Text("—")', constrained)
        self.assertIn('.accessibilityLabel("no data")', constrained)

    def test_true_zero_and_missing_nutrients_follow_distinct_paths(self):
        source = SEARCH_ENGINE.read_text(encoding="utf-8")
        helper = source[
            source.index("func normalizedAndScaledValue"):
            source.index("// MARK: - Display Batch", source.index(
                "func normalizedAndScaledValue"
            ))
        ]
        self.assertIn(
            "calculatedUnit != nil || abs(totalValue) > 0.000001",
            helper,
        )
        self.assertIn("return (0.0, unit)", helper)

    def test_both_constraint_parsers_feed_ordered_display_nutrients(self):
        source = SEARCH_ENGINE.read_text(encoding="utf-8")
        self.assertIn(
            "parsed.nutrientGoals,\n"
            "                    mappedConstraints.nutrientGoals,\n"
            "                    fallbackGoals,",
            source,
        )
        self.assertIn("orderedDisplayNutrients(", source)
        self.assertIn("activeConstraint: activeConstraint", source)

    def test_numeric_constraints_have_visible_context_text(self):
        source = SEARCH_CONTEXT.read_text(encoding="utf-8")
        for expected in (
            'value = "≥ \\(minimum)"',
            'value = "≤ \\(maximum)"',
            'value = "> \\(minimum)"',
            'value = "< \\(maximum)"',
        ):
            self.assertIn(expected, source)

    def test_ph_sort_only_modes_make_ph_visible(self):
        source = SEARCH_ENGINE.read_text(encoding="utf-8")
        self.assertIn("case .lowToHigh:\n                explicitPhConstraint = .lowest", source)
        self.assertIn("case .highToLow:\n                explicitPhConstraint = .highest", source)
        self.assertIn(
            "isPhActive: forceShowPH || intent.phConstraint != nil",
            source,
        )

    def test_missing_ph_display_uses_dash_and_never_zero(self):
        source = SEARCH_VIEW.read_text(encoding="utf-8")
        ph_row_start = source.index(
            "if engine.searchContext.isPhActive"
        )
        ph_row_end = source.index(
            "// Алергени",
            ph_row_start,
        )
        ph_row = source[ph_row_start:ph_row_end]
        self.assertIn("PhSearchSemantics.hasData(food.ph)", ph_row)
        self.assertIn('Text("—")', ph_row)
        self.assertIn('.accessibilityLabel("no data")', ph_row)

    def test_ph_exclusion_count_is_exposed_in_search_context(self):
        source = SEARCH_CONTEXT.read_text(encoding="utf-8")
        engine = SEARCH_ENGINE.read_text(encoding="utf-8")
        self.assertIn("var foodsWithoutPhExcluded: Int = 0", source)
        self.assertIn(
            '"\\(foodsWithoutPhExcluded) foods without pH data excluded"',
            source,
        )
        self.assertIn("foodsWithoutPhExcluded += 1", engine)

    def test_phosphorus_remains_available_to_the_nutrient_parser(self):
        source = SEARCH_ENGINE.read_text(encoding="utf-8")
        self.assertIn(
            'ConstraintQueryBoundary(trimmedName).containsToken("ph")',
            source,
        )
        self.assertNotIn('trimmedName.contains("ph")', source)
        knowledge_base = (
            FOOD_SEARCH / "SearchKnowledgeBase.swift"
        ).read_text(encoding="utf-8")
        self.assertIn('"phosphorus": .phosphorus', knowledge_base)

    def test_amended_engine_filename_and_recursive_xcuserdata_ignore(self):
        self.assertTrue(SEARCH_ENGINE.is_file())
        self.assertFalse(
            (FOOD_SEARCH / "VM" / "SmartFoodSearch 3.swift").exists()
        )
        ignored = subprocess.run(
            [
                "git",
                "check-ignore",
                "--no-index",
                "--quiet",
                "deeply/nested/xcuserdata/example.xcuserdatad",
            ],
            cwd=ROOT,
            check=False,
        )
        self.assertEqual(ignored.returncode, 0)


if __name__ == "__main__":
    unittest.main()
