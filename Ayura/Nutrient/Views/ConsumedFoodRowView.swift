import SwiftUI
import UIKit

struct ConsumedFoodRowView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let item: FoodItem
    let grams: Double
    var highlightedNutrientID: String? = nil
    
    private var formattedWeight: String {
        let display = UnitConversion.formatGramsToFoodDisplay(grams)
        return "\(display.value) \(display.unit)"
    }
    
    private var chart: ChartDisplayData {
        let ref = item.referenceWeightG
        let factor = ref > 0 ? grams / ref : 0
        let p = item.macro(\.protein)
        let f = item.macro(\.fat)
        let c = item.macro(\.carbohydrates)
        let kcalPerRef: Double = {
            // ----- 👇 НАЧАЛО НА ПРОМЯНА 1 (Калории) 👇 -----
            if item.isRecipe || item.isMenu,
               let totKcal = item.totalEnergyKcal?.value,
               let totW = item.totalWeightG, totW > 0 {
                return totKcal / totW * ref
            }
            // ----- 👆 КРАЙ НА ПРОМЯНАТА 1 (Калории) 👆 -----
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
    
    private let central: CGFloat = 40
    private let ringT:   CGFloat = 4
    private let canalT:  CGFloat = 4
    private var donutD:  CGFloat { central + 2 * (ringT + canalT) }

    var body: some View {
        HStack(spacing: 12) {
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
                totalReferenceValue:  chart.totalReferenceForChart
            )
            .frame(width: donutD, height: donutD)
            .foregroundStyle(effectManager.currentGlobalAccentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                
                if let nutrientText = highlightedNutrientText() {
                    Text(nutrientText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
            }

            Spacer(minLength: 8)

            Text(formattedWeight)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.9))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .glassCardStyle(cornerRadius: 15)
    }
    
    // ----- 👇 НАЧАЛО НА ПРОМЯНА 2 (Маркиран нутриент) 👇 -----
    private func highlightedNutrientText() -> String? {
        guard let nutrientID = highlightedNutrientID else { return nil }

        var value: Double?
        var unit: String?

        if nutrientID.starts(with: "macro_") {
            let macroKey = nutrientID.replacingOccurrences(of: "macro_", with: "")
            
            // Използваме агрегираните стойности
            let macroValuePerRef: Double? = {
                switch macroKey {
                case "protein": return item.totalProtein?.value
                case "carbs": return item.totalCarbohydrates?.value
                case "fat": return item.totalFat?.value
                default: return nil
                }
            }()
            
            if let macroVal = macroValuePerRef, item.referenceWeightG > 0 {
                value = (macroVal / item.referenceWeightG) * grams
                unit = "g" // Макросите винаги са в грамове
            }
        } else if let (valuePerRef, unitPerRef) = item.value(of: nutrientID) {
            guard item.referenceWeightG > 0 else { return nil }
            value = (valuePerRef / item.referenceWeightG) * grams
            unit = unitPerRef
        }
        
        guard let finalValue = value, let finalUnit = unit, finalValue > 0.001 else {
            return nil
        }
        
        return formatNutrient(value: finalValue, unit: finalUnit)
    }
    // ----- 👆 КРАЙ НА ПРОМЯНАТА 2 (Маркиран нутриент) 👆 -----
    
    private func formatNutrient(value: Double, unit: String) -> String {
        let (scaledValue, scaledUnit) = autoScale(value, unit: unit)
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if scaledValue < 10 {
            formatter.maximumFractionDigits = 2
        } else if scaledValue < 100 {
            formatter.maximumFractionDigits = 1
        } else {
            formatter.maximumFractionDigits = 0
        }
        
        let numberString = formatter.string(from: NSNumber(value: scaledValue)) ?? "\(scaledValue)"
        return "\(numberString) \(scaledUnit)"
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
