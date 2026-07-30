import Foundation
import SwiftData
import SwiftUI

struct RecipeNutritionPanelView: View {
  @Environment(\.modelContext) private var modelContext
  @ObservedObject private var effectManager = EffectManager.shared
  @State private var display: RecipeNutritionDisplay?
  @State private var basis = RecipeNutritionBasis.perServing

  let food: FoodItem

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Color.clear.frame(height: 0)
      if let display {
        VStack(alignment: .leading, spacing: 14) {
          Text("Recipe Nutrition")
            .font(.title2.weight(.semibold))
            .foregroundStyle(effectManager.currentGlobalAccentColor)

          Picker("Nutrition basis", selection: $basis) {
            ForEach(RecipeNutritionBasis.allCases) { basis in
              Text(basis.title).tag(basis)
            }
          }
          .pickerStyle(.segmented)

          coverageSummary(display)

          if display.status != "none" {
            nutrientSection(
              "Energy & Macronutrients",
              definitions: RecipeNutrientDefinition.macronutrients,
              display: display,
              tint: Color(hex: "4A86E8")
            )
            nutrientSection(
              "Vitamins",
              definitions: RecipeNutrientDefinition.vitamins,
              display: display,
              tint: Color(hex: "FCC934")
            )
            nutrientSection(
              "Minerals",
              definitions: RecipeNutrientDefinition.minerals,
              display: display,
              tint: Color(hex: "34A853")
            )
          }
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
      }
    }
    .task(id: food.id) {
      resolveDisplay()
    }
  }

  private func coverageSummary(_ display: RecipeNutritionDisplay) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        Text(display.statusLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(display.statusColor)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(display.statusColor.opacity(0.22), in: Capsule())

        Text(display.servingSummary)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(display.explanation)
        .font(.caption)
        .foregroundStyle(.secondary)

      if !display.missingIngredients.isEmpty {
        Text("Missing nutrition: " + display.missingIngredients.joined(separator: ", "))
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func nutrientSection(
    _ title: String,
    definitions: [RecipeNutrientDefinition],
    display: RecipeNutritionDisplay,
    tint: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(effectManager.currentGlobalAccentColor)

      ChipGrid {
        ForEach(definitions) { definition in
          RecipeNutrientValueChip(
            definition: definition,
            value: display.values(for: basis)[definition.key],
            unit: display.units[definition.key] ?? definition.defaultUnit,
            tint: tint
          )
        }
      }
    }
  }

  private func resolveDisplay() {
    guard food.isRecipe else {
      display = nil
      return
    }
    do {
      let foodID = food.id
      var descriptor = FetchDescriptor<AyurvedaProfile>(
        predicate: #Predicate<AyurvedaProfile> { profile in
          profile.foodId == foodID
        }
      )
      descriptor.fetchLimit = 1
      display = try contextDisplay(from: modelContext.fetch(descriptor).first)
    } catch {
      display = nil
      #if DEBUG
      print("Recipe nutrition resolve FAILED foodId=\(food.id): \(error)")
      #endif
    }
  }

  private func contextDisplay(from profile: AyurvedaProfile?) throws -> RecipeNutritionDisplay? {
    guard let profile, profile.kind == "recipe", let status = profile.nutritionStatus else {
      return nil
    }
    return RecipeNutritionDisplay(
      status: status,
      missingIngredients: profile.nutritionMissingIngredients,
      totalWeightG: profile.nutritionTotalWeightG ?? 0,
      servings: profile.servingsCount ?? 1,
      perServing: try decode([String: Double].self, profile.nutritionPerServingJSON),
      per100g: try decode([String: Double].self, profile.nutritionPer100gJSON),
      units: try decode([String: String].self, profile.nutritionUnitsJSON)
    )
  }

  private func decode<Value: Decodable>(
    _ type: Value.Type,
    _ json: String?
  ) throws -> Value {
    guard let json, let data = json.data(using: .utf8) else {
      throw RecipeNutritionPanelError.missingPayload
    }
    return try JSONDecoder().decode(type, from: data)
  }
}

private enum RecipeNutritionPanelError: Error {
  case missingPayload
}

private enum RecipeNutritionBasis: String, CaseIterable, Identifiable {
  case perServing
  case per100g

  var id: String { rawValue }

  var title: String {
    switch self {
    case .perServing:
      return "Per serving"
    case .per100g:
      return "Per 100 g"
    }
  }
}

private struct RecipeNutritionDisplay {
  let status: String
  let missingIngredients: [String]
  let totalWeightG: Double
  let servings: Int
  let perServing: [String: Double]
  let per100g: [String: Double]
  let units: [String: String]

  var statusLabel: String {
    switch status {
    case "full":
      return "Full ingredient coverage"
    case "estimated":
      return "Estimated"
    default:
      return "Unavailable"
    }
  }

  var statusColor: Color {
    switch status {
    case "full":
      return Color(hex: "34A853")
    case "estimated":
      return Color(hex: "FCC934")
    default:
      return .secondary
    }
  }

  var servingSummary: String {
    "\(servings) servings · \(totalWeightG.clean) g total"
  }

  var explanation: String {
    if status == "none" {
      return "No ingredient nutrition could be resolved."
    }
    return "Calculated from USDA-bound ingredients. Unavailable USDA nutrient observations are shown as —."
  }

  func values(for basis: RecipeNutritionBasis) -> [String: Double] {
    switch basis {
    case .perServing:
      return perServing
    case .per100g:
      return per100g
    }
  }
}

private struct RecipeNutrientDefinition: Identifiable {
  let key: String
  let label: String
  let defaultUnit: String

  var id: String { key }

  static let macronutrients = [
    RecipeNutrientDefinition(key: "energyKcal", label: "Energy", defaultUnit: "kcal"),
    RecipeNutrientDefinition(key: "carbohydrates", label: "Carbohydrates", defaultUnit: "g"),
    RecipeNutrientDefinition(key: "protein", label: "Protein", defaultUnit: "g"),
    RecipeNutrientDefinition(key: "fat", label: "Fat", defaultUnit: "g"),
    RecipeNutrientDefinition(key: "fiber", label: "Fiber", defaultUnit: "g"),
    RecipeNutrientDefinition(key: "totalSugars", label: "Total sugars", defaultUnit: "g"),
  ]

  static let vitamins = [
    RecipeNutrientDefinition(key: "vitaminA_RAE", label: "Vitamin A RAE", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "retinol", label: "Retinol", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "caroteneAlpha", label: "Alpha-carotene", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "caroteneBeta", label: "Beta-carotene", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "cryptoxanthinBeta", label: "Beta-cryptoxanthin", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "luteinZeaxanthin", label: "Lutein + zeaxanthin", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "lycopene", label: "Lycopene", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "vitaminB1_Thiamin", label: "Vitamin B1", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "vitaminB2_Riboflavin", label: "Vitamin B2", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "vitaminB3_Niacin", label: "Vitamin B3", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "vitaminB5_PantothenicAcid", label: "Vitamin B5", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "vitaminB6", label: "Vitamin B6", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "folateDFE", label: "Folate DFE", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "folateFood", label: "Food folate", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "folateTotal", label: "Total folate", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "folicAcid", label: "Folic acid", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "vitaminB12", label: "Vitamin B12", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "vitaminC", label: "Vitamin C", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "vitaminD", label: "Vitamin D", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "vitaminE", label: "Vitamin E", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "vitaminK", label: "Vitamin K", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "choline", label: "Choline", defaultUnit: "mg"),
  ]

  static let minerals = [
    RecipeNutrientDefinition(key: "calcium", label: "Calcium", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "iron", label: "Iron", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "magnesium", label: "Magnesium", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "phosphorus", label: "Phosphorus", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "potassium", label: "Potassium", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "sodium", label: "Sodium", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "selenium", label: "Selenium", defaultUnit: "µg"),
    RecipeNutrientDefinition(key: "zinc", label: "Zinc", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "copper", label: "Copper", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "manganese", label: "Manganese", defaultUnit: "mg"),
    RecipeNutrientDefinition(key: "fluoride", label: "Fluoride", defaultUnit: "µg"),
  ]
}

private struct RecipeNutrientValueChip: View {
  @ObservedObject private var effectManager = EffectManager.shared

  let definition: RecipeNutrientDefinition
  let value: Double?
  let unit: String
  let tint: Color

  var body: some View {
    HStack(spacing: 4) {
      Text(definition.label)
        .font(.caption)
        .foregroundStyle(effectManager.currentGlobalAccentColor)
      Text(formattedValue)
        .font(.caption.weight(.semibold))
        .foregroundStyle(effectManager.currentGlobalAccentColor)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(tint.opacity(0.25))
    .clipShape(Capsule())
    .accessibilityElement(children: .combine)
  }

  private var formattedValue: String {
    guard let value else {
      return "— \(unit)"
    }
    let scaled = scaledValue(value, unit: unit)
    return "\(scaled.value.clean) \(scaled.unit)"
  }

  private func scaledValue(_ value: Double, unit: String) -> (value: Double, unit: String) {
    if unit == "µg", value >= 1_000 {
      return (value / 1_000, "mg")
    }
    if unit == "mg", value >= 1_000 {
      return (value / 1_000, "g")
    }
    return (value, unit)
  }
}
