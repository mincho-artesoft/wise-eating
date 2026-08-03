import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DISPLAY = ROOT / "Ayura/Ayurveda/Views/AyurvedaDisplay.swift"
SECTION = ROOT / "Ayura/Ayurveda/Views/AyurvedaSectionView.swift"
SCALE = ROOT / "Ayura/Ayurveda/Views/DoshaScaleSelector.swift"
CHIP_GRID = ROOT / "Ayura/Ayurveda/Views/ChipGrid.swift"
GLASS_CHIP = ROOT / "Ayura/Food/Views/ChipScrollView.swift"
BARS = ROOT / "Ayura/Ayurveda/Views/DoshaBarsView.swift"
EDITOR = ROOT / "Ayura/Ayurveda/Views/AyurvedaEditorSection.swift"
CONSTITUTION = ROOT / "Ayura/Ayurveda/AyurvedaConstitutionViews.swift"
SEARCH_CHIPS = ROOT / "Ayura/FoodSearch/AyurvedaSearchChips.swift"
FOOD_ROW = ROOT / "Ayura/Food/Views/FoodItemRowView.swift"
PROFILE_EDITOR = ROOT / "Ayura/Profile/Views/ProfileEditorView.swift"
PROFILE_LIST = ROOT / "Ayura/Profile/Views/ProfileListView.swift"
FOOD_LIST_VM = ROOT / "Ayura/Food/ViewModels/FoodListVM.swift"


class WE3DisplayTests(unittest.TestCase):
    def test_minus_two_zero_plus_two_presentations(self):
        source = DISPLAY.read_text()
        start = source.index("enum AyurvedaDoshaTone")
        end = source.index("struct AyurvedaDisplay: Sendable")
        presentation_source = source[start:end]

        harness = f"""
import Foundation

{presentation_source}

for (name, value) in [("Vata", -2), ("Pitta", 0), ("Kapha", 2)] {{
  let item = AyurvedaDoshaEffectPresentation(value: value)
  print(
    item.primaryText + "|" + item.systemImage + "|"
      + item.accessibilityLabel(dosha: name)
  )
}}
"""

        with tempfile.TemporaryDirectory(prefix="we3-presentation-") as tmp:
            source_path = Path(tmp) / "main.swift"
            binary_path = Path(tmp) / "we3-presentation"
            source_path.write_text(harness)
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    str(source_path),
                    "-o",
                    str(binary_path),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(binary_path)],
                check=True,
                capture_output=True,
                text=True,
            )

        self.assertEqual(
            result.stdout.strip().splitlines(),
            [
                "Strongly pacifies −2|leaf.fill|"
                "Vata: strongly pacifies, minus two of two",
                "Neutral 0|minus.circle.fill|Pitta: neutral, zero of two",
                "Strongly aggravates +2|sun.max.fill|"
                "Kapha: strongly aggravates, plus two of two",
            ],
        )

    def test_read_only_display_uses_noninteractive_glass_chips(self):
        section = SECTION.read_text()
        scale = SCALE.read_text()
        glass_chip = GLASS_CHIP.read_text()
        bars = BARS.read_text()

        self.assertEqual(section.count("GlassChipView("), 1)
        self.assertIn("action: nil", section)
        glass_body = glass_chip[
            glass_chip.index("struct GlassChipView") :
        ]
        self.assertIn("if let action", glass_body)
        self.assertIn("Button(action: action)", glass_body)
        self.assertIn("} else {\n            chipContent", glass_body)
        self.assertEqual(bars.count("DoshaScaleSelector(readOnlyValue:"), 3)
        self.assertIn("init(readOnlyValue value: Int, name: String)", scale)

    def test_accessibility_size_has_single_column_and_no_truncating_chips(self):
        section = SECTION.read_text()
        scale = SCALE.read_text()
        chip_grid = CHIP_GRID.read_text()
        glass_chip = GLASS_CHIP.read_text()

        self.assertIn("propertyStack(propertyGroups)", section)
        self.assertNotIn("dynamicTypeSize", section)
        self.assertIn("CustomFlowLayout", chip_grid)
        self.assertGreaterEqual(scale.count("ViewThatFits(in: .horizontal)"), 2)
        glass_body = glass_chip[glass_chip.index("struct GlassChipView") :]
        self.assertNotIn(".lineLimit(", glass_body)

    def test_detail_fields_match_creation_fields(self):
        editor = EDITOR.read_text()
        display = DISPLAY.read_text()
        section = SECTION.read_text()

        for title in (
            "Rasa (taste)",
            "Virya (energy)",
            "Vipaka (post-digestive)",
            "Gunas (qualities)",
        ):
            self.assertIn(title, editor)
            self.assertIn(title, section)

        self.assertIn("DoshaScaleSelector(", editor)
        self.assertIn("DoshaBarsView(", section)
        for mapping in (
            "rasa: profile.rasa",
            "virya: profile.virya",
            "vipaka: profile.vipaka",
            "gunas: profile.gunas",
        ):
            self.assertIn(mapping, display)

        for display_only_field in (
            "Preparation modifiers",
            "Health warning",
            "Viruddha — incompatible combination",
            "Contraindication",
        ):
            self.assertNotIn(display_only_field, section)

    def test_ai_draft_disclaimer_is_not_rendered(self):
        display = DISPLAY.read_text()
        section = SECTION.read_text()
        disclaimer = (
            "AI-drafted Ayurvedic details, pending expert review. "
            "Informational only — not medical advice."
        )

        self.assertNotIn(disclaimer, display)
        self.assertNotIn("qualityCaption", display)
        self.assertNotIn("qualityCaption", section)

    def test_prabhava_section_is_not_rendered(self):
        display = DISPLAY.read_text()
        section = SECTION.read_text()

        self.assertNotIn("Prabhava (specific effect)", section)
        self.assertNotIn("display.prabhava", section)
        self.assertNotIn("let prabhava", display)

    def test_computed_tier_preview_renders_provenance_cue(self):
        editor = EDITOR.read_text()
        preview_start = editor.index("private struct AyurvedaAutomaticPreview")
        preview_source = editor[preview_start:]

        self.assertIn(
            'Text("Computed from your ingredients — updates automatically")',
            preview_source,
        )
        self.assertIn("if !computation.hasIngredients", preview_source)
        self.assertLess(
            preview_source.index(
                'Text("Computed from your ingredients — updates automatically")'
            ),
            preview_source.index("if let computed = computation.computed"),
        )

    def test_catalogue_profiles_do_not_render_estimated_labels(self):
        visible_sources = "\n".join(
            path.read_text()
            for path in (DISPLAY, CONSTITUTION, SEARCH_CHIPS, FOOD_ROW)
        )

        self.assertNotIn("Estimated profile", visible_sources)
        self.assertNotIn("Estimated Ayurveda", visible_sources)
        self.assertNotIn('== "Estimated"', visible_sources)

    def test_profile_editor_ayurveda_control_matches_section_style(self):
        profile_editor = PROFILE_EDITOR.read_text()
        constitution = CONSTITUTION.read_text()
        section = profile_editor[
            profile_editor.index("private var constitutionSection") :
            profile_editor.index("private var settingsSection")
        ]

        self.assertIn("VStack(alignment: .leading, spacing: 8)", section)
        self.assertIn('Text("Ayurvedic Profile")', section)
        self.assertIn(".font(.headline)", section)
        self.assertIn(
            ".foregroundStyle(effectManager.currentGlobalAccentColor)",
            section,
        )
        self.assertIn('title: "Constitution"', section)
        self.assertIn('title: String = "Ayurvedic profile"', constitution)
        self.assertIn("Text(title)", constitution)

    def test_profile_manager_privacy_controls_are_not_rendered(self):
        constitution = CONSTITUTION.read_text()

        self.assertNotIn('Text("Privacy controls")', constitution)
        self.assertNotIn("Delete complete Ayurvedic profile", constitution)
        self.assertNotIn("isShowingDeleteConfirmation", constitution)

    def test_self_declared_result_has_no_chosen_by_you_caption(self):
        constitution_model = (
            ROOT / "Ayura/Ayurveda/AyurvedaConstitution.swift"
        ).read_text()
        constitution_view = CONSTITUTION.read_text()

        self.assertNotIn("Chosen by you", constitution_model)
        self.assertIn("case .selfDeclared: nil", constitution_model)
        self.assertIn(
            "if showsContextLabels, let sourceName = source.displayName",
            constitution_view,
        )

    def test_profile_manager_does_not_render_current_pattern_section(self):
        constitution = CONSTITUTION.read_text()
        manager = constitution[
            constitution.index("struct AyurvedaConstitutionManagerView") :
            constitution.index("private struct AyurvedaCheckInView")
        ]

        self.assertNotIn('Text("Current pattern")', manager)
        self.assertNotIn("No recent check-in", manager)
        self.assertNotIn("Check in for the past week or two", manager)
        self.assertNotIn("isShowingCheckIn", manager)

    def test_main_profile_deletion_removes_ayurveda_data(self):
        profile_list = PROFILE_LIST.read_text()
        deletion = profile_list[
            profile_list.index("private func performDeletion") :
            profile_list.index("private func handleSingleSelection")
        ]

        ayurveda_delete = (
            "AyurvedaConstitutionStore.delete(profileID: profileIDToDelete)"
        )
        self.assertIn(ayurveda_delete, deletion)
        self.assertIn("modelContext.delete(profileToDeleteInContext)", deletion)
        self.assertLess(
            deletion.index(ayurveda_delete),
            deletion.index("modelContext.delete(profileToDeleteInContext)"),
        )

    def test_user_food_deletion_removes_ayurveda_profile_first(self):
        food_list_vm = FOOD_LIST_VM.read_text()
        deletion = food_list_vm[
            food_list_vm.index("func delete(_ item: FoodItem)") :
            food_list_vm.index("func pruneFavoritesAfterToggle")
        ]

        ayurveda_delete = (
            "AyurvedaUserProfileStore.remove(foodId: foodID, context: ctx)"
        )
        self.assertIn(ayurveda_delete, deletion)
        self.assertIn("ctx.delete(item)", deletion)
        self.assertLess(
            deletion.index(ayurveda_delete),
            deletion.index("ctx.delete(item)"),
        )


if __name__ == "__main__":
    unittest.main()
