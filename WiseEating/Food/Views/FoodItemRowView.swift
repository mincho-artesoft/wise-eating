import SwiftUI
import SwiftData
import UIKit

struct FoodItemRowView: View {
    let item: FoodItem
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    private var displayWeightG: Double? {
        if item.isRecipe || item.isMenu { return item.totalWeightG }
        let stored = item.other?.weightG?.value ?? 0
        if stored > 0 { return stored }
        let p = item.totalProtein?.value ?? 0
        let f = item.totalFat?.value ?? 0
        let c = item.totalCarbohydrates?.value ?? 0
        let fallback = p + f + c
        return fallback > 0 ? fallback : nil
    }

    private var displayKcal: Double? {
        if let agg = item.totalEnergyKcal?.value { return agg }
        if let explicit = item.other?.energyKcal?.value, explicit > 0 { return explicit }
        let protein = (item.totalProtein?.value ?? 0) * 4
        let fat     = (item.totalFat?.value ?? 0) * 9
        let carbs   = (item.totalCarbohydrates?.value ?? 0) * 4
        let tot = protein + fat + carbs
        return tot > 0 ? tot : nil
    }

    private var chartDisplayInformation: ChartDisplayData {
        var segments: [NutrientProportionData] = []
        var referenceWeight: Double? = nil
        let protein = item.totalProtein?.value ?? 0
        let fat     = item.totalFat?.value ?? 0
        let carbs   = item.totalCarbohydrates?.value ?? 0
        if let w = displayWeightG, w > 0 {
            if protein > 0 { segments.append(.init(name: "Protein", value: protein, color: Color(hex: "E6E0F8"))) }
            if fat     > 0 { segments.append(.init(name: "Fat",     value: fat,     color: Color(hex: "FFE5CC"))) }
            if carbs   > 0 { segments.append(.init(name: "Carbs",   value: carbs,   color: Color(hex: "D6ECFF"))) }
            referenceWeight = w
        } else {
            let pk = protein * 4; let fk = fat * 9; let ck = carbs * 4
            if pk > 0 { segments.append(.init(name: "Protein (kcal)", value: pk, color: Color(hex: "E6E0F8"))) }
            if fk > 0 { segments.append(.init(name: "Fat (kcal)",     value: fk, color: Color(hex: "FFE5CC"))) }
            if ck > 0 { segments.append(.init(name: "Carbs (kcal)",   value: ck, color: Color(hex: "D6ECFF"))) }
        }
        return ChartDisplayData(
            proportions: segments.sorted { $0.value > $1.value },
            centralKcalDisplay: displayKcal,
            totalReferenceForChart: referenceWeight
        )
    }

    private var topVitamins: [DisplayableNutrient] { item.topVitamins(count: 4) }
    private var topMinerals: [DisplayableNutrient] { item.topMinerals(count: 4) }

    private var descriptionOrIngredientsText: String? {
        if item.isRecipe || item.isMenu {
            guard let links = item.ingredients, !links.isEmpty else {
                return item.itemDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
            }
            let first = links.prefix(3).map { $0.food?.name ?? "Ingredient" }
            var txt = first.joined(separator: ", ")
            if links.count > 3 { txt += "..." }
            return txt
        } else {
            return item.itemDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
        }
    }

    var body: some View {
        let chartInfo = chartDisplayInformation

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                NutrientProportionDonutChartView(
                    proportions: chartInfo.proportions,
                    centralImageUIImage: item.foodImage(variant: "480"),
                    imagePlaceholderSystemName: "fork.knife.circle.fill",
                    centralContentDiameter: 60,
                    donutRingThickness: 5,
                    canalRingThickness: 5,
                    adaptiveTextColor: effectManager.currentGlobalAccentColor,
                    ringTrackColor: effectManager.currentGlobalAccentColor.opacity(0.1),
                    totalEnergyKcal: chartInfo.centralKcalDisplay,
                    totalReferenceValue: chartInfo.totalReferenceForChart
                )
                .frame(width: 80, height: 80)
                .padding(.top, 2)
               
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(item.name)
                            .font(.headline.weight(.bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                            .lineLimit(2)
                        
                        Spacer()

                        Button(action: {
                            withAnimation(.spring()) {
                                item.isFavorite.toggle()
                            }
                            // ✅ Запази и съобщи
                            try? modelContext.save()
                            SearchIndexStore.shared.updateFavoriteStatus(for: item.id, isFavorite: item.isFavorite)
                            NotificationCenter.default.post(name: .foodFavoriteToggled, object: item)
                        }) {
                            Image(systemName: item.isFavorite ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                                .font(.title3)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                    .animation(.spring(), value: item.isFavorite)

                    if let txt = descriptionOrIngredientsText, !txt.isEmpty {
                        Text(txt)
                            .font(.caption)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                            .lineLimit(2)
                    }

                    if displayWeightG != nil || displayKcal != nil {
                        weightAndCaloriesText()
                            .font(.caption2)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                            .padding(.top, 2)
                    }
                }
                .layoutPriority(1)
            }

            let nutrients = topVitamins + topMinerals
            let allergens = item.allergens ?? []
            
            if !nutrients.isEmpty || !allergens.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ChipScrollView(title: "Top Nutrients", items: nutrients, textColor: effectManager.currentGlobalAccentColor)
                    ChipScrollView(title: "Allergens", items: allergens, textColor: effectManager.currentGlobalAccentColor, isAlertSection: true)
                }
            }
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }
    
    @ViewBuilder
    private func weightAndCaloriesText() -> some View {
        let k = displayKcal.map { formatted($0, unit: "kcal") }

        HStack(spacing: 12) {
            if let weightInGrams = displayWeightG {
                let displayWeight = UnitConversion.formatGramsToFoodDisplay(weightInGrams)
                Text("\(displayWeight.value) \(displayWeight.unit)")
            }

            if displayWeightG != nil && k != nil {
                Circle().fill(effectManager.currentGlobalAccentColor.opacity(0.3)).frame(width: 3, height: 3)
            }
            if let k { Text(k) }
        }
    }
    
    private func formatted(_ value: Double, unit: String) -> String {
        let (scaled, newUnit) = autoScale(value, unit: unit)
        let str: String
        
        if scaled.truncatingRemainder(dividingBy: 1) == 0 {
            str = String(format: "%.0f", scaled)
        } else if scaled < 0.1 && scaled > 0 && newUnit.lowercased() != "kcal" {
            str = String(format: "%.2f", scaled)
        } else {
            str = String(format: "%.1f", scaled)
        }
        return "\(str) \(newUnit)"
    }
    
    private func autoScale(_ value: Double, unit: String) -> (Double, String) {
        var v = value, u = unit.lowercased()
        while v >= 1000 {
            switch u {
            case "ng": v /= 1000; u = "µg"
            case "µg", "mcg": v /= 1000; u = "mg"
            case "mg": v /= 1000; u = "g"
            case "g": v /= 1000; u = "kg"
            default: return (v, unit)
            }
        }
        return (v, u == unit.lowercased() ? unit : u)
    }
}
