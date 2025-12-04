import SwiftUI
import UIKit

// MARK: - MealSummaryRowEventView --------------------------------------------------
struct MealSummaryRowEventView: View {
    let rows: [(FoodItem, Double)]
    @ObservedObject private var effectManager = EffectManager.shared

    // ----- 👇 НАЧАЛО НА ПРОМЯНАТА (АГРЕГИРАЩИ ФУНКЦИИ) 👇 -----
    // Премахваме локалните изчисления и използваме вече агрегираните данни от FoodItem
    private func scaledNutrient(for item: FoodItem, grams: Double, keyPath: KeyPath<FoodItem, Nutrient?>) -> Double {
        guard let valuePerRef = item[keyPath: keyPath]?.value, item.referenceWeightG > 0 else {
            return 0
        }
        return valuePerRef * (grams / item.referenceWeightG)
    }
    
    private var totalWeightG: Double { rows.reduce(0) { $0 + $1.1 } }
    private var totalProtein: Double { rows.reduce(0) { $0 + scaledNutrient(for: $1.0, grams: $1.1, keyPath: \.totalProtein) } }
    private var totalFat: Double { rows.reduce(0) { $0 + scaledNutrient(for: $1.0, grams: $1.1, keyPath: \.totalFat) } }
    private var totalCarbs: Double { rows.reduce(0) { $0 + scaledNutrient(for: $1.0, grams: $1.1, keyPath: \.totalCarbohydrates) } }
    private var totalKcal: Double { rows.reduce(0) { $0 + scaledNutrient(for: $1.0, grams: $1.1, keyPath: \.totalEnergyKcal) } }

    private func aggregateTopNutrients(extractor: (FoodItem) -> [DisplayableNutrient]) -> [DisplayableNutrient] {
        struct Acc { var value: Double; var unit: String }
        var dict: [String: Acc] = [:]
        for (item, grams) in rows {
            let multiplier = grams / item.referenceWeightG
            guard multiplier.isFinite, multiplier > 0 else { continue }
            
            for nut in extractor(item) {
                let scaledVal = nut.value * multiplier
                if let existing = dict[nut.name] {
                    dict[nut.name] = .init(value: existing.value + scaledVal, unit: nut.unit)
                } else {
                    dict[nut.name] = .init(value: scaledVal, unit: nut.unit)
                }
            }
        }
        return dict.sorted { $0.value.value > $1.value.value }
                   .map { DisplayableNutrient(name:  $0.key, value: $0.value.value, unit:  $0.value.unit, valueMg: 0) }
    }
    // ----- 👆 КРАЙ НА ПРОМЯНАТА (АГРЕГИРАЩИ ФУНКЦИИ) 👆 -----
    
    private var topVitamins: [DisplayableNutrient] { aggregateTopNutrients(extractor: { $0.topVitamins(count:2) }) }
    private var topMinerals: [DisplayableNutrient] { aggregateTopNutrients(extractor: { $0.topMinerals(count:2) }) }

    private var chartDisplayInformation: ChartDisplayData {
        var segments: [NutrientProportionData] = []
        if totalProtein > 0 { segments.append(.init(name: "Protein", value: totalProtein, color: Color(hex: "E6E0F8"))) }
        if totalFat > 0 { segments.append(.init(name: "Fat", value: totalFat, color: Color(hex: "FFE5CC"))) }
        if totalCarbs > 0 { segments.append(.init(name: "Carbs", value: totalCarbs, color: Color(hex: "D6ECFF"))) }
        return ChartDisplayData(proportions: segments.sorted { $0.value > $1.value }, centralKcalDisplay: totalKcal, totalReferenceForChart: totalWeightG)
    }
    
    private let chartCentralContentSize: CGFloat = 40
    private let chartRingThickness:      CGFloat = 4
    private let chartCanalThickness:     CGFloat = 4
    private var chartTotalDiameter: CGFloat { chartCentralContentSize + 2 * chartCanalThickness + 2 * chartRingThickness }

    // MARK: - View body
    var body: some View {
        let chartInfo = chartDisplayInformation

        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 10) {
                NutrientProportionDonutChartView(
                    proportions: chartInfo.proportions,
                    centralImageUIImage: nil,
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
                    HStack {
                        Text("Meal")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)

                        Spacer()
                        
                        weightAndCaloriesText()
                            .font(.caption2)
                            .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                    nutrientChips()
                }
                .layoutPriority(1)
            }
        }
        
    }

    // MARK: - Sub-helpers
    @ViewBuilder
    private func weightAndCaloriesText() -> some View {
        let displayWeight = UnitConversion.formatGramsToFoodDisplay(totalWeightG)
        let kcalText = formatted(totalKcal, unit: "kcal")
        
        HStack(spacing: 4) {
            Text("\(displayWeight.value) \(displayWeight.unit)")
            Text("/")
            Text(kcalText)
        }
    }
    
    @ViewBuilder
    private func nutrientChips() -> some View {
        let list = topVitamins + topMinerals
        if !list.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(list) { nut in
                        HStack(spacing: 4) {
                            Text(nut.name)
                            Text(formatted(nut.value, unit: nut.unit)).fontWeight(.medium)
                        }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                        .clipShape(Capsule())
                        .glassCardStyle(cornerRadius: 20)
                    }
                }
            }
            .frame(height: 20)
        }
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
            case "ng": v /= 1000; u = "µg"; case "µg", "mcg": v /= 1000; u = "mg"; case "mg": v /= 1000; u = "g"; case "g": v /= 1000; u = "kg"; default: return (v, unit)
            }
        }
        return (v, u == unit.lowercased() ? unit : u)
    }
}
