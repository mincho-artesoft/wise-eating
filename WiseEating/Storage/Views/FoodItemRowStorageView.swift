import SwiftUI
import UIKit

struct FoodItemRowStorageView: View {

    @ObservedObject private var effectManager = EffectManager.shared

    // ПРОМЯНА: Променете типа на amount от Int на Double
    let item: FoodItem
    let amount: Double // << ПРОМЯНА ТУК

    private var referenceWeightG: Double { item.referenceWeightG }
    // ПРОМЯНА: selectedAmountG вече е директно amount
    private var selectedAmountG: Double { amount }
    private var referenceWeightGForChart: Double? {
        selectedAmountG > 0 ? selectedAmountG : nil
    }

    private var displayKcalPer100g: Double? {
        if let agg = item.totalEnergyKcal?.value { return agg }
        if let explicit = item.other?.energyKcal?.value, explicit > 0 { return explicit }
        let protein = item.totalProtein?.value ?? item.macronutrients?.protein?.value ?? 0
        let fat     = item.totalFat?.value ?? item.macronutrients?.fat?.value ?? 0
        let carbs   = item.totalCarbohydrates?.value ?? item.macronutrients?.carbohydrates?.value ?? 0
        let tot = protein * 4 + fat * 9 + carbs * 4
        return tot > 0 ? tot : nil
    }

    private var chartDisplayInformation: ChartDisplayData {
        var segments: [NutrientProportionData] = []
        let protein = item.totalProtein?.value ?? item.macronutrients?.protein?.value ?? 0
        let fat     = item.totalFat?.value ?? item.macronutrients?.fat?.value ?? 0
        let carbs   = item.totalCarbohydrates?.value ?? item.macronutrients?.carbohydrates?.value ?? 0
        if protein > 0 { segments.append(.init(name: "Protein", value: protein, color: Color(hex: "E6E0F8"))) }
        if fat     > 0 { segments.append(.init(name: "Fat",     value: fat,     color: Color(hex: "FFE5CC"))) }
        if carbs   > 0 { segments.append(.init(name: "Carbs",   value: carbs,   color: Color(hex: "D6ECFF"))) }
        return ChartDisplayData(
            proportions: segments.sorted { $0.value > $1.value },
            centralKcalDisplay: displayKcalPer100g,
            totalReferenceForChart: referenceWeightGForChart
        )
    }

    private let chartCentralContentSize: CGFloat = 60
    private let chartRingThickness:      CGFloat = 5
    private let chartCanalThickness:     CGFloat = 5
    private var chartTotalDiameter: CGFloat {
        chartCentralContentSize + 2*chartCanalThickness + 2*chartRingThickness
    }
    
    private var topVitamins: [DisplayableNutrient] { item.topVitamins(count: 2) }
    private var topMinerals: [DisplayableNutrient] { item.topMinerals(count: 2) }

    private var descriptionOrIngredientsText: String? {
        if item.isRecipe {
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
                    centralContentDiameter: chartCentralContentSize,
                    donutRingThickness: chartRingThickness,
                    canalRingThickness: chartCanalThickness,
                    adaptiveTextColor: effectManager.currentGlobalAccentColor,
                    ringTrackColor: effectManager.currentGlobalAccentColor.opacity(0.1),
                    totalEnergyKcal: chartInfo.centralKcalDisplay,
                    totalReferenceValue: chartInfo.totalReferenceForChart
                )
                .frame(width: chartTotalDiameter, height: chartTotalDiameter)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline.weight(.bold))
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                        .lineLimit(2)

                    if let txt = descriptionOrIngredientsText, !txt.isEmpty {
                        Text(txt)
                            .font(.caption)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                            .lineLimit(2)
                            .padding(.top, 1)
                    }
                    
                    if selectedAmountG > 0 {
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
                    if !nutrients.isEmpty {
                        ChipScrollView(title: "Top Nutrients (per 100g)", items: nutrients, textColor: effectManager.currentGlobalAccentColor)
                    }
                    if !allergens.isEmpty {
                        ChipScrollView(title: "Allergens", items: allergens, textColor: effectManager.currentGlobalAccentColor, isAlertSection: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }

    @ViewBuilder
    private func weightAndCaloriesText() -> some View {
        let displayWeight = UnitConversion.formatGramsToFoodDisplay(selectedAmountG)
        Text("In storage: \(displayWeight.value) \(displayWeight.unit)")
    }
    
    private func formatted(_ value: Double, unit: String) -> String {
        let (scaled, newUnit) = autoScale(value, unit: unit)
        let str: String
        if scaled.truncatingRemainder(dividingBy: 1) == 0 { str = String(format: "%.0f", scaled) }
        else if scaled < 0.1 && scaled > 0 && newUnit.lowercased() != "kcal" { str = String(format: "%.2f", scaled) }
        else { str = String(format: "%.1f", scaled) }
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
