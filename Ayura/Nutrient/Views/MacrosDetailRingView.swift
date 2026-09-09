import SwiftUI

enum SelectedMacro: String, Identifiable {
    case protein, carbs, fat
    var id: String { self.rawValue }
    
    var nutrientID: String { "macro_\(self.rawValue)" }
}

struct MacrosDetailRingView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // Входни данни
    let totalProteinGrams: Double
    let totalCarbsGrams: Double
    let totalFatGrams: Double
    let onDismiss: () -> Void
    let allConsumedFoods: [FoodItem: Double]
    
    @State private var selectedMacro: SelectedMacro? = nil
    
    private var sortedFoods: [(food: FoodItem, grams: Double)] {
        guard let macro = selectedMacro else {
            return allConsumedFoods
                .map { (food: $0.key, grams: $0.value) }
                .sorted { $0.food.name < $1.food.name }
        }
        
        return allConsumedFoods
            .map { (food: $0.key, grams: $0.value) }
            .sorted { (item1: (food: FoodItem, grams: Double), item2: (food: FoodItem, grams: Double)) -> Bool in
                let amount1 = item1.food.amount(of: macro, forGrams: item1.grams)
                let amount2 = item2.food.amount(of: macro, forGrams: item2.grams)
                return amount1 > amount2
            }
    }
    
    private var totalConsumedWeight: Double {
        allConsumedFoods.reduce(0) { $0 + $1.value }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Навигационна лента
            HStack {
                Button("Close") { onDismiss() }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                
                Spacer()
                Text("Macronutrient").font(.headline).foregroundColor(effectManager.currentGlobalAccentColor)
                Spacer()
                Button("Close") {}.hidden().disabled(true).padding(.horizontal, 10).padding(.vertical, 5)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            // Външният VStack подрежда статичната карта и скролиращия се списък
            VStack(spacing: 16) {
                // 1. Статична карта с MacroProportionBarView
                if totalConsumedWeight > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Daily Totals")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                        
                        MacroProportionBarView(
                            protein: totalProteinGrams,
                            carbs: totalCarbsGrams,
                            fat: totalFatGrams,
                            totalWeight: totalConsumedWeight,
                            selectedMacro: $selectedMacro
                        )
                    }
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                }
                
                // 2. Секция със скролиращия се списък с храни
                Text(selectedMacro == nil ? "All Consumed Foods" : "Foods by Selected Macronutrient")
                    .font(.headline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if sortedFoods.isEmpty {
                    // 3а. Placeholder, ако няма храни
                    ContentUnavailableView("No Foods to Display", systemImage: "fork.knife.circle")
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        .padding(.vertical, 40)
                        .glassCardStyle(cornerRadius: 15)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            Spacer(minLength: 10)
                            ForEach(sortedFoods, id: \.food.id) { item in
                                ConsumedFoodRowView(
                                    item: item.food,
                                    grams: item.grams,
                                    highlightedNutrientID: selectedMacro?.nutrientID
                                )
                            }
                            Spacer(minLength: 150)
                        }
                    }
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: effectManager.currentGlobalAccentColor, location: 0.01),
                                .init(color: effectManager.currentGlobalAccentColor, location: 0.9),
                                .init(color: .clear, location: 0.95)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                
                // 4. Spacer(), който разпъва VStack
                Spacer()
            }
            .padding(.horizontal)
        }
    }
    
    private struct MacroProportionBarView: View {
        @ObservedObject private var effectManager = EffectManager.shared
        
        let protein: Double, carbs: Double, fat: Double, totalWeight: Double
        @Binding var selectedMacro: SelectedMacro?
        
        init(protein: Double, carbs: Double, fat: Double, totalWeight: Double, selectedMacro: Binding<SelectedMacro?>) {
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
            self.totalWeight = totalWeight > 0 ? totalWeight : 1
            self._selectedMacro = selectedMacro
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                // Wrap the bar in a GeometryReader to get the available width
                GeometryReader { geo in
                    let availableWidth = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(effectManager.currentGlobalAccentColor.opacity(0.2))
                            .frame(height: 12)
                        
                        HStack(spacing: 0) {
                            // Calculate widths based on the available width, not the screen width
                            Rectangle().fill(MacroNutrientPalette.protein).frame(width: (protein / totalWeight) * availableWidth)
                            Rectangle().fill(MacroNutrientPalette.carbohydrates).frame(width: (carbs / totalWeight) * availableWidth)
                            Rectangle().fill(MacroNutrientPalette.fat).frame(width: (fat / totalWeight) * availableWidth)
                        }
                        .clipShape(Capsule())
                    }
                    .tubularBarDepth(height: 12)
                }
                .frame(height: 12) // Constrain the height of the GeometryReader
                
                HStack {
                    legendItem(label: "Protein", value: protein, color: MacroNutrientPalette.protein, macroType: .protein)
                    Spacer()
                    legendItem(label: "Carbs", value: carbs, color: MacroNutrientPalette.carbohydrates, macroType: .carbs)
                    Spacer()
                    legendItem(label: "Fat", value: fat, color: MacroNutrientPalette.fat, macroType: .fat)
                }
                .font(.caption)
            }
        }
        
        @ViewBuilder
        private func legendItem(label: String, value: Double, color: Color, macroType: SelectedMacro) -> some View {
            // This subview remains unchanged
            Button(action: {
                withAnimation {
                    if selectedMacro == macroType {
                        selectedMacro = nil
                    } else {
                        selectedMacro = macroType
                    }
                }
            }) {
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(label)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                    Text(value.clean + "g")
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
                .padding(6)
                .background(selectedMacro == macroType ? color.opacity(0.2) : Color.clear)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassCardStyle(cornerRadius: 20)
        }
    }
}

fileprivate extension FoodItem {
    // ----- 👇 НАЧАЛО НА ПРОМЯНАТА 👇 -----
    func amount(of macro: SelectedMacro, forGrams grams: Double) -> Double {
        // Използваме правилните, агрегирани изчисляеми свойства
        let macroValuePerRef: Double
        switch macro {
        case .protein:
            macroValuePerRef = self.totalProtein?.value ?? 0
        case .carbs:
            macroValuePerRef = self.totalCarbohydrates?.value ?? 0
        case .fat:
            macroValuePerRef = self.totalFat?.value ?? 0
        }
        
        // Логиката за мащабиране остава същата
        guard self.referenceWeightG > 0 else {
            return 0
        }
        
        return (macroValuePerRef / self.referenceWeightG) * grams
    }
    // ----- 👆 КРАЙ НА ПРОМЯНАТА 👆 -----
}
