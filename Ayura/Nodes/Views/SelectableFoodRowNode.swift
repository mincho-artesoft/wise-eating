import SwiftUI

struct SelectableFoodRowNode: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    let food: FoodItem
    let isSelected: Bool
    
    // MARK: – Chart helper
    private struct ChartInfo {
        let slices: [NutrientProportionData]
        let kcalCenter: Double?
        let chartTotal: Double?
    }
    
    // Използваме референтното тегло като базово количество (аналогично на SelectedFoodRowView)
    private var currentGrams: Double {
        let ref = food.referenceWeightG
        return ref > 0 ? ref : (food.totalWeightG ?? 0)
    }
    
    private var chart: ChartInfo {
        let ref = food.referenceWeightG
        let baseGrams = currentGrams
        let factor = (ref > 0 && baseGrams > 0) ? baseGrams / ref : 0
        
        let p = food.macro(\.protein)
        let f = food.macro(\.fat)
        let c = food.macro(\.carbohydrates)
        
        let kcalPerRef: Double = {
            if food.isRecipe || food.isMenu,
               let totKcal = food.totalEnergyKcal?.value,
               let totW = food.totalWeightG, totW > 0 {
                return totKcal / totW * ref
            }
            return food.other?.energyKcal?.value ?? 0
        }()
        
        var slices: [NutrientProportionData] = []
        if p > 0 { slices.append(.init(name: "Protein", value: p * factor, color: MacroNutrientPalette.protein)) }
        if f > 0 { slices.append(.init(name: "Fat", value: f * factor, color: MacroNutrientPalette.fat)) }
        if c > 0 { slices.append(.init(name: "Carbs", value: c * factor, color: MacroNutrientPalette.carbohydrates)) }
        
        return ChartInfo(
            slices:      slices.sorted { $0.value > $1.value },
            kcalCenter:  kcalPerRef > 0 ? kcalPerRef * factor : nil,
            chartTotal:  baseGrams > 0 ? baseGrams : nil
        )
    }
    
    // MARK: – Layout constants (копирани от SelectedFoodRowView)
    private let central: CGFloat = 60
    private let ringT:   CGFloat = 6
    private let canalT:  CGFloat = 6
    private var donutD:  CGFloat { central + 2 * (ringT + canalT) }
    
    private var hasPhoto: Bool { food.photo != nil }
    private var energy: Double {
        chart.kcalCenter ?? 0
    }
    
    // MARK: – Допълнителни помощни (по желание за подзаглавие)
    private var displayWeightG: Double? {
        if food.isRecipe || food.isMenu { return food.totalWeightG }
        let stored = food.other?.weightG?.value ?? 0
        if stored > 0 { return stored }
        let p = food.totalProtein?.value ?? 0
        let f = food.totalFat?.value ?? 0
        let c = food.totalCarbohydrates?.value ?? 0
        let fallback = p + f + c
        return fallback > 0 ? fallback : nil
    }

    private var displayKcal: Double? {
        if let agg = food.totalEnergyKcal?.value { return agg }
        if let explicit = food.other?.energyKcal?.value, explicit > 0 { return explicit }
        let p = (food.totalProtein?.value ?? 0) * 4
        let f = (food.totalFat?.value ?? 0) * 9
        let c = (food.totalCarbohydrates?.value ?? 0) * 4
        return (p + f + c) > 0 ? (p + f + c) : nil
    }
    
    var body: some View {
        // --- НАЧАЛО НА ПРОМЯНАТА: Добавяме .frame(height: 95) за уеднаквяване ---
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            
            // Основно съдържание – същото усещане като SelectedFoodRowView
            HStack(spacing: 12) {
                NutrientProportionDonutChartView(
                    proportions:                 chart.slices,
                    centralImageUIImage:         food.foodImage(variant: "480"),
                    imagePlaceholderSystemName:  "photo.circle.fill",
                    centralContentDiameter:      central,
                    donutRingThickness:          ringT,
                    canalRingThickness:          canalT,
                    adaptiveTextColor:           effectManager.currentGlobalAccentColor,
                    ringTrackColor:              effectManager.currentGlobalAccentColor.opacity(0.1),
                    totalEnergyKcal:             chart.kcalCenter,
                    totalReferenceValue:         chart.chartTotal
                )
                .frame(width: donutD, height: donutD)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                    
                    // Подзаглавие kcal / тегло (по избор – можеш да махнеш, ако не ти трябва)
                    if let kcal = displayKcal, let weight = displayWeightG {
                        Text("\(kcal.clean) kcal / \(formattedWeight(weight))")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                    
                    // 🔥 kcal център – същата логика като в SelectedFoodRowView, показва се само при снимка
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
                        .padding(.top, 2)
                    }
                }
                
                Spacer(minLength: 8)
            }
        }
        .frame(height: 95)
        // --- КРАЙ НА ПРОМЯНАТА ---
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .glassCardStyle(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isSelected ? effectManager.currentGlobalAccentColor : Color.clear, lineWidth: 2)
        )
    }
    
    private func formattedWeight(_ grams: Double) -> String {
        let display = UnitConversion.formatGramsToFoodDisplay(grams)
        return "\(display.value) \(display.unit)"
    }
}
