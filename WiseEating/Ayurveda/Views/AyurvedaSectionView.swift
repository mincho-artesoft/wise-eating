import SwiftData
import SwiftUI

struct AyurvedaSectionView: View {
  @Environment(\.modelContext) private var modelContext
  @ObservedObject private var effectManager = EffectManager.shared
  @State private var display: AyurvedaDisplay?
  @State private var debugFailure: String?

  let food: FoodItem

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Guaranteed render node: an empty Group collapses to EmptyView, which has
      // no representation, so .task/.onAppear never fire and resolution never
      // runs (the D8 "invisible section" bug). Color.clear always exists.
      Color.clear.frame(height: 0)
      #if DEBUG
      if display == nil, let debugFailure {
        Text("Ayurveda debug: \(debugFailure)")
          .font(.caption2)
          .foregroundStyle(.red)
      }
      #endif
      if let display {
        VStack(alignment: .leading, spacing: 12) {
          Text("Ayurveda")
            .font(.title2.weight(.semibold))
            .foregroundStyle(effectManager.currentGlobalAccentColor)
          content(display)
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
      }
    }
    .task(id: food.id) {
      resolveDisplay()
    }
  }

  private func content(_ display: AyurvedaDisplay) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if display.engineExcluded {
        Text("⚠️ Health warning: traditional sources and modern evidence advise against consuming this. Shown for reference only — never recommended.")
          .font(.caption)
          .foregroundStyle(.red)
      }
      tierRow(display)
      DoshaBarsView(vata: display.vata, pitta: display.pitta, kapha: display.kapha)
      AyurvedaChipRow(title: "Rasa (taste)", values: display.rasa)
      AyurvedaChipRow(title: "Virya (energy)", values: optionalValue(display.virya))
      AyurvedaChipRow(title: "Vipaka (post-digestive)", values: optionalValue(display.vipaka))
      AyurvedaChipRow(title: "Gunas (qualities)", values: display.gunas)
      AyurvedaChipRow(
        title: "Preparation modifiers",
        values: display.modifierLabels,
        color: Color(hex: "FCC934")
      )
      AyurvedaWarningsView(
        viruddha: display.viruddha,
        contraindications: display.contraindications
      )
      if let caption = display.qualityCaption {
        Text(caption)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func tierRow(_ display: AyurvedaDisplay) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(display.tierLabel)
        .font(.caption.weight(.semibold))
        .foregroundStyle(tierColor(display.tierLabel))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tierColor(display.tierLabel).opacity(0.25), in: Capsule())
      if let detail = detailText(display) {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func detailText(_ display: AyurvedaDisplay) -> String? {
    var parts: [String] = []
    if let detail = display.tierDetail {
      parts.append(detail)
    }
    if display.tierLabel != "User", let confidence = display.confidence {
      parts.append("confidence \(String(format: "%.2f", confidence))")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private func optionalValue(_ value: String?) -> [String] {
    guard let value, !value.isEmpty else {
      return []
    }
    return [value]
  }

  private func tierColor(_ label: String) -> Color {
    switch label {
    case "Classical":
      return Color(hex: "34A853")
    case "Derived":
      return Color(hex: "4A86E8")
    case "Estimated":
      return Color(hex: "FCC934")
    case "Recipe":
      return Color(hex: "9C6ADE")
    default:
      return Color(hex: "999999")
    }
  }

  private func resolveDisplay() {
    do {
      let resolution = try AyurvedaResolver.resolve(for: food, context: modelContext)
      display = AyurvedaDisplay.make(from: resolution)
      #if DEBUG
      if display == nil {
        debugFailure = "resolution mapped to nil: \(resolution)"
      }
      print("🕉️ Ayurveda resolve foodId=\(food.id): \(display == nil ? "NIL (\(resolution))" : "ok")")
      #endif
    } catch {
      display = nil
      #if DEBUG
      debugFailure = "resolver error: \(error)"
      print("🕉️ Ayurveda resolver FAILED foodId=\(food.id): \(error)")
      #endif
    }
  }
}
