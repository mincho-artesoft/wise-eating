import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DISPLAY = ROOT / "Ayura/Ayurveda/Views/AyurvedaDisplay.swift"
SECTION = ROOT / "Ayura/Ayurveda/Views/AyurvedaSectionView.swift"
SCALE = ROOT / "Ayura/Ayurveda/Views/DoshaScaleSelector.swift"
CHIP = ROOT / "Ayura/Ayurveda/Views/AyurvedaChip.swift"
BARS = ROOT / "Ayura/Ayurveda/Views/DoshaBarsView.swift"


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

    def test_read_only_display_reuses_d8_components(self):
        section = SECTION.read_text()
        scale = SCALE.read_text()
        chip = CHIP.read_text()
        bars = BARS.read_text()

        self.assertEqual(section.count("AyurvedaChip("), 1)
        self.assertIn("isReadOnly: true", section)
        self.assertEqual(bars.count("DoshaScaleSelector(readOnlyValue:"), 3)
        self.assertIn("init(readOnlyValue value: Int, name: String)", scale)
        self.assertIn("if isReadOnly", chip)
        self.assertIn("editorChip", chip)

    def test_accessibility_size_has_single_column_and_no_truncating_chips(self):
        section = SECTION.read_text()
        scale = SCALE.read_text()
        chip = CHIP.read_text()

        self.assertIn("dynamicTypeSize.isAccessibilitySize", section)
        self.assertIn("propertyStack(primaryGroups)", section)
        self.assertGreaterEqual(scale.count("ViewThatFits(in: .horizontal)"), 2)
        read_only_chip = chip[chip.index("private var readOnlyChip") :]
        self.assertNotIn(".lineLimit(", read_only_chip)
        self.assertIn(".fixedSize(horizontal: false, vertical: true)", read_only_chip)

    def test_warning_and_disclaimer_surfaces_remain_separate(self):
        section = SECTION.read_text()

        warning_start = section.index("private struct AyurvedaDisplayWarningRow")
        warning_source = section[warning_start:]
        self.assertIn("AyurvedaWarning", warning_source)
        self.assertIn("display.contraindications.enumerated()", section)
        self.assertIn("if let caption = display.qualityCaption", section)
        self.assertLess(
            section.index("if let caption = display.qualityCaption"),
            warning_start,
        )

    def test_ai_draft_profile_renders_not_medical_advice_disclaimer(self):
        display = DISPLAY.read_text()
        section = SECTION.read_text()
        disclaimer = (
            "AI-drafted Ayurvedic details, pending expert review. "
            "Informational only — not medical advice."
        )

        self.assertIn('if profile.qualityState == "aiDraft"', display)
        self.assertIn(disclaimer, display)
        self.assertIn(
            "qualityCaption: qualityCaption(for: profile, tierLabel: tierLabel)",
            display,
        )

        render_start = section.index("if let caption = display.qualityCaption")
        render_source = section[render_start:]
        self.assertIn("Text(caption)", render_source)
        self.assertIn(".accessibilityLabel(caption)", render_source)


if __name__ == "__main__":
    unittest.main()
