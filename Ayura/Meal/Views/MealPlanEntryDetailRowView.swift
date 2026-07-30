import SwiftUI
import UIKit

struct MealPlanEntryDetailRowView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    // Dependencies
    let entry: MealPlanEntry

    // Computed Properties
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var ingredientUnit: String { isImperial ? "oz" : "g" }
    private var item: FoodItem? { entry.food }
    private var grams: Double { entry.grams }

    // Chart-related properties
    private var chart: ChartDisplayData {
        guard let item = item else { return ChartDisplayData(proportions: [], centralKcalDisplay: nil, totalReferenceForChart: nil) }
        
        let ref = item.referenceWeightG
        let factor = ref > 0 ? grams / ref : 0
        let p = item.totalProtein?.value ?? 0
        let f = item.totalFat?.value ?? 0
        let c = item.totalCarbohydrates?.value ?? 0
        
        let kcalPerRef: Double = {
            if item.isRecipe || item.isMenu, let totKcal = item.totalEnergyKcal?.value, let totW = item.totalWeightG, totW > 0 {
                return totKcal / totW * ref
            }
            return item.other?.energyKcal?.value ?? 0
        }()
        
        var slices: [NutrientProportionData] = []
        if p > 0 { slices.append(.init(name: "Protein", value: p * factor, color: Color(hex: "E6E0F8").opacity(0.85))) }
        if f > 0 { slices.append(.init(name: "Fat", value: f * factor, color: Color(hex: "FFE5CC").opacity(0.85))) }
        if c > 0 { slices.append(.init(name: "Carbs", value: c * factor, color: Color(hex: "D6ECFF").opacity(0.85))) }
        
        return ChartDisplayData(
            proportions: slices.sorted { $0.value > $1.value },
            centralKcalDisplay: kcalPerRef > 0 ? kcalPerRef * factor : nil,
            totalReferenceForChart: grams > 0 ? grams : nil
        )
    }

    private let central: CGFloat = 60
    private let ringT:   CGFloat = 6
    private let canalT:  CGFloat = 6
    private var donutD:  CGFloat { central + 2 * (ringT + canalT) }
    private var hasPhoto: Bool { item?.photo != nil }
    private var energy: Double {
        guard let item = item, item.referenceWeightG > 0 else { return 0 }
        return chart.centralKcalDisplay ?? 0
    }
    
    // Body
    var body: some View {
        HStack(spacing: 12) {
            if let item = item {
                NutrientProportionDonutChartView(
                    proportions:             chart.proportions,
                    centralImageUIImage: item.foodImage(variant: "480"),
                    imagePlaceholderSystemName: "fork.knife.circle.fill",
                    centralContentDiameter:  central,
                    donutRingThickness:      ringT,
                    canalRingThickness:      canalT,
                    adaptiveTextColor:       effectManager.currentGlobalAccentColor,
                    ringTrackColor:          effectManager.currentGlobalAccentColor.opacity(0.1),
                    totalEnergyKcal:         chart.centralKcalDisplay,
                    totalReferenceValue:     chart.totalReferenceForChart
                )
                .frame(width: donutD, height: donutD)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item?.name ?? "Unknown Item")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)

                if hasPhoto {
                    HStack(spacing: central * 0.08) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: central * 0.18))
                            .foregroundColor(.orange)

                        Text(String(format: "%.0f", energy))
                            .font(.system(size: central * 0.24, weight: .bold))
                            .foregroundStyle(effectManager.currentGlobalAccentColor)

                        Text("Kcal")
                            .font(.system(size: central * 0.16))
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 8)
            
            let display = UnitConversion.formatGramsToFoodDisplay(grams)
            Text("\(display.value) \(display.unit)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.9))
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .glassCardStyle(cornerRadius: 20)
    }
}
