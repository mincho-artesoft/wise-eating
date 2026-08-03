import SwiftData
import SwiftUI

struct AyurvedaSectionView: View {
  @Environment(\.modelContext) private var modelContext
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
        AyurvedaDisplayCard(display: display)
          .padding()
          .glassCardStyle(cornerRadius: 20)
      }
    }
    .task(id: food.id) {
      resolveDisplay()
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

struct AyurvedaDisplayCard: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let display: AyurvedaDisplay

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      title
      if display.engineExcluded {
        AyurvedaDisplayWarningRow(
          title: "Health warning",
          text: display.edible
            ? "Traditional sources and modern evidence advise against consuming this. Shown for reference only — never recommended."
            : "Not available as food. Shown for reference only — no serving or recommendation is provided.",
          tone: .warning
        )
      }
      if display.edible {
        DoshaBarsView(
          vata: display.vata,
          pitta: display.pitta,
          kapha: display.kapha
        )
        if !propertyGroups.isEmpty {
          properties
        }
      }
      warnings
      if let caption = display.qualityCaption {
        Text(caption)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel(caption)
      }
    }
    .transaction { transaction in
      if reduceMotion {
        transaction.animation = nil
      }
    }
  }

  private var title: some View {
    Text("Ayurveda")
      .font(.title2.weight(.semibold))
      .foregroundStyle(.primary)
  }

  private var properties: some View {
    propertyStack(propertyGroups)
  }

  private func propertyStack(
    _ groups: [AyurvedaPropertyGroup]
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(groups) { group in
        AyurvedaPropertyGroupView(group: group)
      }
    }
  }

  private var propertyGroups: [AyurvedaPropertyGroup] {
    if display.tierLabel == "Computed" {
      return group(
        title: "Virya (energy)",
        systemImage: "bolt.fill",
        kind: .virya,
        values: optionalValue(display.virya)
      )
    }

    var groups: [AyurvedaPropertyGroup] = []
    groups += group(
      title: "Rasa (taste)",
      systemImage: "leaf.fill",
      kind: .rasa,
      values: display.rasa
    )
    groups += group(
      title: "Virya (energy)",
      systemImage: "bolt.fill",
      kind: .virya,
      values: optionalValue(display.virya)
    )
    groups += group(
      title: "Vipaka (post-digestive)",
      systemImage: "arrow.triangle.2.circlepath",
      kind: .vipaka,
      values: optionalValue(display.vipaka)
    )
    groups += group(
      title: "Gunas (qualities)",
      systemImage: "circle.grid.2x2.fill",
      kind: .guna,
      values: display.gunas
    )
    groups += group(
      title: "Preparation modifiers",
      systemImage: "slider.horizontal.3",
      kind: .modifier,
      values: display.modifierLabels
    )
    return groups
  }

  private func group(
    title: String,
    systemImage: String,
    kind: AyurvedaPropertyKind,
    values: [String]
  ) -> [AyurvedaPropertyGroup] {
    guard !values.isEmpty else { return [] }
    return [
      AyurvedaPropertyGroup(
        title: title,
        systemImage: systemImage,
        kind: kind,
        values: values
      )
    ]
  }

  private func optionalValue(_ value: String?) -> [String] {
    guard let value, !value.isEmpty else { return [] }
    return [value]
  }

  @ViewBuilder
  private var warnings: some View {
    if !display.viruddha.isEmpty || !display.contraindications.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(display.viruddha.enumerated()), id: \.offset) { _, value in
          AyurvedaDisplayWarningRow(
            title: "Viruddha — incompatible combination",
            text: value,
            tone: .caution
          )
        }
        ForEach(
          Array(display.contraindications.enumerated()),
          id: \.offset
        ) { _, value in
          AyurvedaDisplayWarningRow(
            title: "Contraindication",
            text: value,
            tone: .warning
          )
        }
      }
    }
  }
}

private enum AyurvedaPropertyKind: Equatable {
  case rasa
  case virya
  case vipaka
  case guna
  case modifier
}

private struct AyurvedaPropertyGroup: Identifiable {
  let title: String
  let systemImage: String
  let kind: AyurvedaPropertyKind
  let values: [String]

  var id: String { title }
}

private struct AyurvedaPropertyGroupView: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let group: AyurvedaPropertyGroup

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(group.title, systemImage: group.systemImage)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      ChipGrid {
        ForEach(Array(group.values.enumerated()), id: \.offset) { _, value in
          GlassChipView(
            label: value.capitalized,
            color: tint(for: value),
            systemImage: icon(for: value),
            textColor: effectManager.currentGlobalAccentColor,
            isSelected: true,
            action: nil
          )
        }
      }
    }
  }

  private func icon(for value: String) -> String? {
    let value = value.lowercased()
    switch group.kind {
    case .rasa:
      switch value {
      case "sweet": return "sparkles"
      case "sour": return "drop.fill"
      case "salty": return "water.waves"
      case "pungent": return "flame.fill"
      case "bitter": return "leaf.fill"
      default: return "circle.grid.3x3.fill"
      }
    case .virya:
      switch value {
      case "cooling": return "snowflake"
      case "heating": return "flame.fill"
      default: return "minus.circle.fill"
      }
    case .vipaka:
      switch value {
      case "sweet": return "sparkles"
      case "sour": return "drop.fill"
      case "pungent": return "flame.fill"
      default: return "arrow.triangle.2.circlepath"
      }
    case .guna:
      switch value {
      case "dense": return "circle.grid.3x3.fill"
      case "dry": return "wind"
      case "heavy": return "scalemass.fill"
      case "light": return "leaf"
      case "liquid": return "drop.fill"
      case "oily": return "drop.circle.fill"
      case "penetrating": return "scope"
      case "rough": return "circle.dotted"
      case "sharp": return "bolt.fill"
      case "slimy": return "water.waves"
      case "smooth": return "waveform.path"
      case "soft": return "cloud.fill"
      default: return "circle.fill"
      }
    case .modifier:
      return "wand.and.stars"
    }
  }

  private func tint(for value: String) -> Color {
    switch group.kind {
    case .virya:
      switch value.lowercased() {
      case "cooling":
        return Color("AyurvedaPacify")
      case "heating":
        return Color("AyurvedaAggravate")
      default:
        return Color("AyurvedaNeutral")
      }
    case .guna:
      return Color("AyurvedaPacify")
    case .modifier:
      return Color("AyurvedaAggravate")
    default:
      return Color("AyurvedaChipTint")
    }
  }
}

private enum AyurvedaDisplayWarningTone {
  case caution
  case warning
}

private struct AyurvedaDisplayWarningRow: View {
  @Environment(\.colorScheme) private var colorScheme

  let title: String
  let text: String
  let tone: AyurvedaDisplayWarningTone

  private var color: Color {
    switch tone {
    case .caution:
      return Color("AyurvedaAggravate")
    case .warning:
      return Color("AyurvedaWarning")
    }
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(color)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.caption.weight(.semibold))
        Text(text)
          .font(.caption)
      }
      .foregroundStyle(color)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      color.opacity(colorScheme == .dark ? 0.18 : 0.09),
      in: RoundedRectangle(cornerRadius: 13, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .stroke(color.opacity(colorScheme == .dark ? 0.45 : 0.24), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}
