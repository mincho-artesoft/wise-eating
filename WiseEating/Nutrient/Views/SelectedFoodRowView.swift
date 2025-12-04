import SwiftUI
import UIKit
import Combine

struct SelectedFoodRowView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: – Public
    let item: FoodItem
    let grams: Double
    let isStockSufficient: Bool
    var onGramsChanged: (Double) -> Void

    // MARK: – Internal State
    @FocusState.Binding var focusedField: FoodItem?
    @State private var textValue: String

    @Binding var expandedItemID: FoodItem.ID?
    
    @State private var showFullText: Bool

    private var isExpanded: Bool {
        expandedItemID == item.id
    }

    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var displayUnit: String { isImperial ? "oz" : "g" }
    
    private var isFocused: Bool { focusedField == item }

    // MARK: – Chart helper
    private struct ChartInfo {
        let slices: [NutrientProportionData]
        let kcalCenter: Double?
        let chartTotal: Double?
    }
    
    private var currentGrams: Double {
        guard let displayValue = GlobalState.double(from: textValue) else { return grams }
        return isImperial ? UnitConversion.ozToG(displayValue) : displayValue
    }

    private var chart: ChartInfo {
        let ref = item.referenceWeightG
        let factor = ref > 0 ? currentGrams / ref : 0
        let p = item.macro(\.protein)
        let f = item.macro(\.fat)
        let c = item.macro(\.carbohydrates)
        let kcalPerRef: Double = {
            if item.isRecipe || item.isMenu,
               let totKcal = item.totalEnergyKcal?.value,
               let totW = item.totalWeightG, totW > 0 {
                return totKcal / totW * ref
            }
            return item.other?.energyKcal?.value ?? 0
        }()
        var slices: [NutrientProportionData] = []
        if p > 0 { slices.append(.init(name: "Protein", value: p * factor, color: Color(hex: "E6E0F8").opacity(0.85))) }
        if f > 0 { slices.append(.init(name: "Fat", value: f * factor, color: Color(hex: "FFE5CC").opacity(0.85))) }
        if c > 0 { slices.append(.init(name: "Carbs", value: c * factor, color: Color(hex: "D6ECFF").opacity(0.85))) }
        return ChartInfo(
            slices:      slices.sorted { $0.value > $1.value },
            kcalCenter:  kcalPerRef > 0 ? kcalPerRef * factor : nil,
            chartTotal:  currentGrams > 0 ? currentGrams : nil
        )
    }
    
    private let central: CGFloat = 60
    private let ringT:   CGFloat = 6
    private let canalT:  CGFloat = 6
    private var donutD:  CGFloat { central + 2 * (ringT + canalT) }
    private var hasPhoto: Bool { item.foodImage(variant: "480") != nil }
    private var energy: Double {
        guard item.referenceWeightG > 0 else { return 0 }
        return chart.kcalCenter ?? 0
    }

    private var phValue: Double? {
        FoodItem.aggregatedNutrition(for: item).other?.alkalinityPH?.value
    }

    // MARK: – Init
    init(item: FoodItem,
         grams: Double,
         isStockSufficient: Bool,
         onGramsChanged: @escaping (Double) -> Void,
         focusedField: FocusState<FoodItem?>.Binding,
         expandedItemID: Binding<FoodItem.ID?>)
    {
        self.item = item
        self.grams = grams
        self.isStockSufficient = isStockSufficient
        self.onGramsChanged = onGramsChanged
        self._focusedField = focusedField
        self._expandedItemID = expandedItemID
        
        self._showFullText = State(initialValue: expandedItemID.wrappedValue == item.id)
        
        let isImperial = GlobalState.measurementSystem == "Imperial"
        let displayValue = isImperial ? UnitConversion.gToOz_display(grams) : grams
        _textValue = State(initialValue: UnitConversion.formatDecimal(displayValue))
    }

    // MARK: – Body
    var body: some View {
        HStack(spacing: 12) {
            NutrientProportionDonutChartView(
                proportions:             chart.slices,
                centralImageUIImage: item.foodImage(variant: "480"),
                imagePlaceholderSystemName: "photo.circle.fill",
                centralContentDiameter:  central,
                donutRingThickness:      ringT,
                canalRingThickness:      canalT,
                adaptiveTextColor:       effectManager.currentGlobalAccentColor,
                ringTrackColor:          effectManager.currentGlobalAccentColor.opacity(0.1),
                totalEnergyKcal:         chart.kcalCenter,
                totalReferenceValue:     chart.chartTotal
            )
            .frame(width: donutD, height: donutD)
            .foregroundStyle(effectManager.currentGlobalAccentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .if(showFullText) { view in
                        view.fixedSize(horizontal: false, vertical: true)
                    } else: { view in
                        view.lineLimit(2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isExpanded {
                            // СВИВАНЕ
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showFullText = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now()) {
                                 withAnimation(.easeInOut(duration: 0.3)) {
                                     expandedItemID = nil
                                 }
                            }
                        } else {
                            // РАЗГЪВАНЕ
                            withAnimation(.easeInOut(duration: 0.3)) {
                                expandedItemID = item.id
                            }
                        }
                    }
                    .onChange(of: isExpanded) { _, isNowExpanded in
                        if isNowExpanded {
                            DispatchQueue.main.asyncAfter(deadline: .now()) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showFullText = true
                                }
                            }
                        } else {
                            showFullText = false
                        }
                    }

                if !isStockSufficient {
                    HStack(alignment: .center, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text("Quantity exceeds stock")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                    .padding(.top, 1)
                }
                
                HStack(spacing: 16) {
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
                    }
                    
                    if let ph = phValue {
                        HStack(spacing: central * 0.08) {
                            Text(String(format: "pH %.1f", ph))
                                .font(.system(size: central * 0.22, weight: .semibold))
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                        }
                    }
                    
                    // +++ НАЧАЛО НА ПРОМЯНАТА +++
                    if let nodes = item.nodes, !nodes.isEmpty {
                        HStack(spacing: central * 0.08) {
                            Text("Nodes: \(nodes.count)")
                                .font(.system(size: central * 0.22, weight: .semibold))
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                        }
                    }
                    // +++ КРАЙ НА ПРОМЯНАТА +++
                }
                .padding(.top, isStockSufficient ? 4 : 2)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ConfigurableTextField(
                    title: displayUnit,
                    value: $textValue,
                    type: .decimal,
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    focused: $focusedField,
                    fieldIdentifier: item
                )
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .onChange(of: textValue) { _, newText in
                    processChange(newText: newText)
                }

                Text(displayUnit)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .glassCardStyle(cornerRadius: 20)
        .onChange(of: isFocused) { _, isNowFocused in
            if !isNowFocused {
                formatTextFinal()
            }
        }
        .onChange(of: grams) { _, newGrams in
            updateTextFromModel(newGrams: newGrams)
        }
    }
    
    private func processChange(newText: String) {
        if newText.isEmpty {
            onGramsChanged(0)
            return
        }
        
        guard let displayValue = GlobalState.double(from: newText) else { return }
        let grams = isImperial ? UnitConversion.ozToG(displayValue) : displayValue
        onGramsChanged(grams)
    }

    private func formatTextFinal() {
        let displayValue = isImperial ? UnitConversion.gToOz_display(grams) : grams
        let formattedText = UnitConversion.formatDecimal(displayValue)
        
        if textValue != formattedText {
            textValue = formattedText
        }
    }
    
    private func updateTextFromModel(newGrams: Double) {
        let currentTextAsGrams = currentGrams
        if abs(currentTextAsGrams - newGrams) > 0.01 {
            let newDisplayValue = isImperial ? UnitConversion.gToOz_display(newGrams) : newGrams
            let newFormattedText = UnitConversion.formatDecimal(newDisplayValue)
            if textValue != newFormattedText {
                textValue = newFormattedText
            }
        }
    }
}
