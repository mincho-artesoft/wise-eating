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
CONSTITUTION_MODEL = ROOT / "Ayura/Ayurveda/AyurvedaConstitution.swift"
SEARCH_CHIPS = ROOT / "Ayura/FoodSearch/AyurvedaSearchChips.swift"
FOOD_ROW = ROOT / "Ayura/Food/Views/FoodItemRowView.swift"
SELECTED_FOOD_ROW = ROOT / "Ayura/Nutrient/Views/SelectedFoodRowView.swift"
PROFILE_EDITOR = ROOT / "Ayura/Profile/Views/ProfileEditorView.swift"
PROFILE_LIST = ROOT / "Ayura/Profile/Views/ProfileListView.swift"
FOOD_LIST_VM = ROOT / "Ayura/Food/ViewModels/FoodListVM.swift"
SETTINGS = ROOT / "Ayura/Settings/SettingsView.swift"
DAILY_AYURVEDA_SUMMARY = (
    ROOT / "Ayura/Nutrient/Views/DailyAyurvedaSummaryView.swift"
)
NUTRITIONS_DETAIL = ROOT / "Ayura/Nutrient/Views/NutritionsDetailView.swift"
RINGS_SUMMARY = ROOT / "Ayura/Nutrient/Views/RingsSummaryRow.swift"


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

    def test_dosha_scales_and_food_chips_follow_active_profile(self):
        scale = SCALE.read_text()
        search_chips = SEARCH_CHIPS.read_text()

        self.assertIn("profileAwareScale(isInteractive: true)", scale)
        self.assertIn("profileAwareScale(isInteractive: false)", scale)
        self.assertIn("LinearGradient(", scale)
        self.assertIn("private var profileWeight: Double?", scale)
        self.assertIn("profileWeight >= (1.0 / 3.0)", scale)
        self.assertIn("activeRecord()?", scale)
        self.assertNotIn("private func segment(", scale)

        self.assertIn(
            "@State private var profileDistribution: "
            "AyurvedaDoshaDistribution?",
            search_chips,
        )
        self.assertIn("profileDistribution?.vata", search_chips)
        self.assertIn("profileDistribution?.pitta", search_chips)
        self.assertIn("profileDistribution?.kapha", search_chips)
        self.assertIn(
            "let isSupportive = prefersPacifying ? value < 0 : value > 0",
            search_chips,
        )
        self.assertIn("activeRecord()?", search_chips)

    def test_percentage_dosha_bar_matches_profile_palette(self):
        bars = BARS.read_text()

        self.assertIn(
            '.init(label: "Vata", value: percentages.v, color: .blue)',
            bars,
        )
        self.assertIn(
            '.init(label: "Pitta", value: percentages.p, color: .orange)',
            bars,
        )
        self.assertIn(
            '.init(label: "Kapha", value: percentages.k, color: .green)',
            bars,
        )
        self.assertNotIn(
            '.init(label: "Vata", value: percentages.v, color: .purple)',
            bars,
        )
        self.assertNotIn(
            '.init(label: "Pitta", value: percentages.p, color: .red)',
            bars,
        )

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
        self.assertIn('Label("Virya (energy)", systemImage: "bolt.fill")', preview_source)
        self.assertIn("computedVirya(computed.virya)", preview_source)
        self.assertIn("action: nil", preview_source)
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

    def test_selected_nutrition_foods_show_the_same_ayurveda_fit_as_search(self):
        food_row = FOOD_ROW.read_text()
        selected_food_row = SELECTED_FOOD_ROW.read_text()
        constitution = CONSTITUTION.read_text()

        self.assertNotIn("AyurvedaPersonalFitBadge", food_row)
        self.assertIn("AyurvedaPersonalFitBadge(display: ayurvedaDisplay)", selected_food_row)
        self.assertIn("AyurvedaDoshaResultChips(", selected_food_row)
        self.assertIn("resolveAyurvedaDisplay()", selected_food_row)
        self.assertIn("init(display: AyurvedaDisplay)", constitution)
        self.assertIn("init(metadata: AyurvedaCanonicalSearchMetadata?)", constitution)

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
        self.assertIn("completesSetupDirectly: true", section)
        self.assertIn('title: String = "Ayurvedic profile"', constitution)
        self.assertIn("Text(title)", constitution)

    def test_profile_editor_ayurveda_setup_finishes_from_header(self):
        constitution = CONSTITUTION.read_text()
        setup = constitution[
            constitution.index("struct AyurvedaConstitutionSetupView") :
            constitution.index("struct AyurvedaConstitutionResultSummary")
        ]

        self.assertIn(
            'trailingTitle: completesDirectly ? "Done" : nil',
            setup,
        )
        self.assertIn("trailingDisabled: directCompletionDisabled", setup)
        self.assertIn("return questionnaireAnswers.contains { $0 == nil }", setup)
        self.assertIn('Button("Next")', setup)
        self.assertIn(
            ".padding(.horizontal, completesDirectly ? 16 : 0)",
            setup,
        )
        self.assertIn("if completesDirectly {\n      finish(draft)", setup)

    def test_settings_does_not_duplicate_ayurveda_profile_editor(self):
        settings = SETTINGS.read_text()

        self.assertNotIn("AyurvedaConstitutionEditorButton", settings)
        self.assertNotIn("userSettings", settings)

    def test_profile_manager_privacy_controls_are_not_rendered(self):
        constitution = CONSTITUTION.read_text()

        self.assertNotIn('Text("Privacy controls")', constitution)
        self.assertNotIn("Delete complete Ayurvedic profile", constitution)
        self.assertNotIn("isShowingDeleteConfirmation", constitution)

    def test_self_declared_result_has_no_chosen_by_you_caption(self):
        constitution_model = CONSTITUTION_MODEL.read_text()
        constitution_view = CONSTITUTION.read_text()

        self.assertNotIn("Chosen by you", constitution_model)
        self.assertIn("case .selfDeclared: nil", constitution_model)
        self.assertIn(
            "if showsContextLabels, let sourceName = source.displayName",
            constitution_view,
        )

    def test_result_summary_has_no_match_caption(self):
        constitution = CONSTITUTION.read_text()

        self.assertNotIn("Your answers most closely match", constitution)

    def test_ayurveda_prompts_keep_shared_wording_with_question_marks(self):
        constitution_model = CONSTITUTION_MODEL.read_text()

        self.assertNotIn("…", constitution_model)
        self.assertIn(
            '"Your natural pace has usually been?"',
            constitution_model,
        )
        self.assertIn(
            '"Over the past week or two, your sleep has felt?"',
            constitution_model,
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

    def test_profile_manager_summary_has_horizontal_insets(self):
        constitution = CONSTITUTION.read_text()
        manager = constitution[
            constitution.index("struct AyurvedaConstitutionManagerView") :
            constitution.index("private struct AyurvedaCheckInView")
        ]

        self.assertIn(
            "EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)",
            manager,
        )
        self.assertNotIn(".listRowInsets(EdgeInsets())", manager)

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

    def test_daily_ayurveda_summary_uses_selected_profile_and_all_meals(self):
        summary = DAILY_AYURVEDA_SUMMARY.read_text()
        nutrition_detail = NUTRITIONS_DETAIL.read_text()

        self.assertIn("struct DailyAyurvedaSummaryRow", summary)
        self.assertIn("AyurvedaFoodFitPresentation.make(", summary)
        self.assertNotIn('Text("Fit for \\(profileName)")', summary)
        self.assertNotIn("Text(fit.explanation)", summary)
        self.assertNotIn("Label(fit.title", summary)
        self.assertIn("fitLabel(fit.direction)", summary)

        self.assertIn(
            "let constitutionRecord = "
            "AyurvedaConstitutionStore.record(for: profile.id)",
            nutrition_detail,
        )
        self.assertIn(
            "dailyAyurvedaTarget = constitutionRecord?.target(at: chosenDate)",
            nutrition_detail,
        )
        self.assertIn(
            "let ingredients: [AyurvedaIngredientAmount] = "
            "allConsumedFoods.compactMap",
            nutrition_detail,
        )
        self.assertIn("AyurvedaResolver.computeIngredients(", nutrition_detail)
        self.assertGreaterEqual(
            nutrition_detail.count(
                "dailyAyurvedaMeals = emptyDailyAyurvedaMealSummaries()"
            ),
            2,
        )
        self.assertIn(
            "private func emptyDailyAyurvedaMealSummaries()",
            nutrition_detail,
        )
        self.assertGreaterEqual(
            nutrition_detail.count("DailyAyurvedaSummaryRow("),
            2,
        )
        self.assertIn("case goals, calories, macros, ayurveda", nutrition_detail)

    def test_daily_ayurveda_summary_is_one_card_and_pin_has_large_hit_target(self):
        summary = DAILY_AYURVEDA_SUMMARY.read_text()
        nutrition_detail = NUTRITIONS_DETAIL.read_text()
        rings = RINGS_SUMMARY.read_text()
        row = summary[
            summary.index("struct DailyAyurvedaSummaryRow") :
            summary.index("struct DailyAyurvedaDetailView")
        ]

        self.assertNotIn('Label("Daily Ayurveda"', row)
        self.assertIn('Text("Fit")', row)
        self.assertIn("HStack(alignment: .center, spacing: 16)", row)
        self.assertIn("VStack(alignment: .center, spacing: 4)", row)
        self.assertIn(".frame(width: 76, alignment: .center)", row)
        self.assertIn("private func doshaScale", row)
        self.assertIn("private func doshaTrack", row)
        self.assertIn("ForEach(1..<4, id: \\.self)", row)
        self.assertIn("private static let scaleValues = [2, 1, 0, -1, -2]", row)
        self.assertIn("private func doshaScaleLabels(", row)
        self.assertIn("trackWidth * CGFloat(index) / 4", row)
        self.assertIn('name: "Vata",\n                            value: computed.vata', row)
        self.assertIn('name: "Pitta",\n                            value: computed.pitta', row)
        self.assertIn('name: "Kapha",\n                            value: computed.kapha', row)
        self.assertIn("let profileDistribution: AyurvedaDoshaDistribution?", row)
        self.assertIn("profileWeight: profileDistribution?.vata ?? 0", row)
        self.assertIn("profileWeight: profileDistribution?.pitta ?? 0", row)
        self.assertIn("profileWeight: profileDistribution?.kapha ?? 0", row)
        self.assertIn("private func prefersPacifyingEffect", row)
        self.assertIn("profileWeight >= (1.0 / 3.0)", row)
        self.assertIn("private func personalizedColor", row)
        self.assertIn("prefersPacifying ? value < 0 : value > 0", row)
        self.assertIn("let gradientColors = prefersPacifying", row)
        self.assertNotIn(".opacity(relevance)", row)
        self.assertGreaterEqual(
            nutrition_detail.count(
                "profileDistribution: dailyAyurvedaProfileResult?.distribution"
            ),
            2,
        )
        self.assertIn("LinearGradient(", row)
        self.assertNotIn('Text("Poor")', row)
        self.assertNotIn('Text("Mixed")', row)
        self.assertNotIn('Text("Good")', row)
        self.assertNotIn("private var scaleLabels", row)
        self.assertNotIn("AyurvedaDoshaResultChips(", row)
        self.assertNotIn("private var fitScale", row)
        self.assertEqual(row.count(".glassCardStyle(cornerRadius: 20)"), 1)
        self.assertNotIn("Divider()", row)
        self.assertIn(".padding(.horizontal, 20)", row)
        self.assertIn(".frame(width: 44, height: 44)", rings)
        self.assertIn(".contentShape(Rectangle())", rings)
        self.assertIn("ZStack(alignment: .topTrailing)", rings)
        self.assertIn(".offset(x: 14, y: -14)", rings)
        self.assertNotIn(".padding(.trailing, 18)", rings)

    def test_daily_ayurveda_detail_switches_one_card_by_meal(self):
        summary = DAILY_AYURVEDA_SUMMARY.read_text()
        nutrition_detail = NUTRITIONS_DETAIL.read_text()
        detail = summary[summary.index("struct DailyAyurvedaDetailView") :]

        self.assertIn("@State private var selectedMealID: UUID?", detail)
        self.assertNotIn("date.formatted", detail)
        self.assertIn("selectedSummaryCard", detail)
        self.assertNotIn('Text("Coverage \\(coveragePercent(for: selected))%")', detail)
        self.assertNotIn("private func coveragePercent(", detail)
        self.assertNotIn("private func viryaIcon(", detail)
        self.assertIn("profileConstitutionCard", detail)
        self.assertIn("AyurvedaConstitutionResultSummary(", detail)
        self.assertIn("let profileResult: AyurvedaConstitutionResult?", detail)
        self.assertIn("if let profileResult", detail)
        self.assertIn("result: profileResult", detail)
        self.assertIn(
            "dailyAyurvedaProfileResult = constitutionRecord?.result",
            nutrition_detail,
        )
        self.assertIn("if !meals.isEmpty {\n                        mealSelector", detail)
        self.assertLess(
            detail.index("profileConstitutionCard"),
            detail.index("mealSelector"),
        )
        self.assertLess(
            detail.index("mealSelector"),
            detail.index("selectedSummaryCard", detail.index("mealSelector")),
        )
        self.assertNotIn('title: "Whole day"', detail)
        self.assertIn('"fork.knife.circle"', detail)
        self.assertIn('"No Foods to Display"', detail)
        self.assertIn(".frame(maxWidth: .infinity, minHeight: 300)", detail)
        self.assertIn("ForEach(meals)", detail)
        self.assertNotIn('systemImage: "fork.knife"', detail)
        self.assertNotIn("systemImage: String", detail)
        self.assertIn("private static let mealPalette", detail)
        self.assertIn("private var mealColors", detail)
        self.assertIn("localizedCaseInsensitiveCompare", detail)
        self.assertIn("color.opacity(isSelected ? 0.8 : 0.3)", detail)
        self.assertIn(".stroke(color, lineWidth: isSelected ? 2 : 0)", detail)
        self.assertIn(
            "selectedMealID = isSelected ? nil : mealID",
            detail,
        )
        self.assertIn("return meal.computation", detail)
        self.assertNotIn("mealBreakdown", detail)
        self.assertNotIn('Text("By Meal")', detail)
        self.assertIn("dailyAyurvedaMeals = dailyMeals.map", nutrition_detail)
        self.assertIn("computation: computation", nutrition_detail)


if __name__ == "__main__":
    unittest.main()
