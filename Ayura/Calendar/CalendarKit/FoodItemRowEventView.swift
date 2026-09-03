import SwiftUI
import UIKit

struct FoodItemRowEventView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Inputs
    let item: FoodItem
    let amount: Double        // ← избраното количество в грамове

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Multiplier & basic helpers

    private var multiplier: Double {
        // multiplier-ът се използва за мащабиране на нутриентите спрямо избраното количество
        let referenceWeight = item.referenceWeightG
        guard referenceWeight > 0 else { return 1.0 }
        return amount / referenceWeight
    }

    private var displayWeightG: Double? { amount }

    // ----- 👇 НАЧАЛО НА ПРОМЯНАТА (НУТРИЕНТИ И КАЛОРИИ) 👇 -----
    // Вече използваме АГРЕГИРАНИТЕ стойности от FoodItem, които работят за всичко (храни, рецепти, менюта)
    private var scaledProtein: Double { (item.totalProtein?.value ?? 0) * multiplier }
    private var scaledFat: Double { (item.totalFat?.value ?? 0) * multiplier }
    private var scaledCarbs: Double { (item.totalCarbohydrates?.value ?? 0) * multiplier }

    private var displayKcal: Double? {
        // totalEnergyKcal също е рекурсивно и работи за всичко.
        if let kcalPerRef = item.totalEnergyKcal?.value {
             return kcalPerRef * multiplier
        }
        // Fallback, ако няма зададени калории, изчисляваме ги от макросите
        let tot = scaledProtein * 4 + scaledFat * 9 + scaledCarbs * 4
        return tot > 0 ? tot : nil
    }
    // ----- 👆 КРАЙ НА ПРОМЯНАТА (НУТРИЕНТИ И КАЛОРИИ) 👆 -----

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Donut-chart data

    private var chartDisplayInformation: ChartDisplayData {
        var segments: [NutrientProportionData] = []
        if scaledProtein > 0 { segments.append(.init(name: "Protein", value: scaledProtein, color: MacroNutrientPalette.protein)) }
        if scaledFat > 0 { segments.append(.init(name: "Fat", value: scaledFat, color: MacroNutrientPalette.fat)) }
        if scaledCarbs > 0 { segments.append(.init(name: "Carbs", value: scaledCarbs, color: MacroNutrientPalette.carbohydrates)) }

        return ChartDisplayData(
            proportions: segments.sorted { $0.value > $1.value },
            centralKcalDisplay: displayKcal,
            totalReferenceForChart: displayWeightG
        )
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Constants (layout)

    private let chartCentralContentSize: CGFloat = 40
    private let chartRingThickness:      CGFloat = 4
    private let chartCanalThickness:     CGFloat = 4
    private var chartTotalDiameter: CGFloat { chartCentralContentSize + 2 * chartCanalThickness + 2 * chartRingThickness }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Top vitamins / minerals (scaled)

    private var topVitamins: [DisplayableNutrient] {
        item.topVitamins(count: 2).map { .init(name: $0.name, value: $0.value * multiplier, unit:  $0.unit, valueMg: 0) }
    }
    private var topMinerals: [DisplayableNutrient] {
        item.topMinerals(count: 2).map { .init(name: $0.name, value: $0.value * multiplier, unit:  $0.unit, valueMg: 0) }
    }
    
    private var descriptionOrIngredientsText: String? {
        if item.isRecipe || item.isMenu { // Добавяме проверка и за isMenu
            guard let links = item.ingredients, !links.isEmpty else {
                return item.itemDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
            }
            let first = links.prefix(3).map { link -> String in
                let n = link.food?.name ?? "Ingredient"; let g = link.grams
                let s = g.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0fg", g) : String(format: "%.1fg", g)
                return "\(n) \(s)"
            }
            var txt = first.joined(separator: ", "); if links.count > 3 { txt += "…" }; return txt
        } else {
            return item.itemDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - View body

    var body: some View {
        let chartInfo = chartDisplayInformation

        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 10) {
                NutrientProportionDonutChartView(
                    proportions: chartInfo.proportions,
                    centralImageUIImage: item.foodImage(variant: "480"), // ← промяната тук
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
                        Text(item.name)
                            .font(.system(size: 10, weight: .bold)).lineLimit(1)
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

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Sub-views & helpers

    @ViewBuilder
    private func weightAndCaloriesText() -> some View {
        let kcalText: String? = {
            // Разширяваме проверката да включва и isMenu
            if item.photo != nil || item.isRecipe || item.isMenu {
                return displayKcal.map { formatted($0, unit: "kcal") }
            }
            return nil
        }()

        HStack(spacing: 4) {
            if let weightG = displayWeightG {
                let isImperial = GlobalState.measurementSystem == "Imperial"
                let displayValue = isImperial ? UnitConversion.gToOz_display(weightG) : weightG
                let unit = isImperial ? "oz" : "g"
                
                Text("\(UnitConversion.formatDecimal(displayValue)) \(unit)")
            }

            if let kcalText = kcalText {
                if displayWeightG != nil {
                    Text("/")
                }
                Text(kcalText)
            }
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
