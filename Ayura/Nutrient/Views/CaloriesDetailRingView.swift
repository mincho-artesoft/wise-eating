import SwiftUI

struct CaloriesDetailRingView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // Входни данни
    let totalCalories: Double
    let targetCalories: Double
    let onDismiss: () -> Void
    let allConsumedFoods: [FoodItem: Double]
    
    private var sortedFoods: [(food: FoodItem, grams: Double)] {
        return allConsumedFoods
            .map { (food: $0.key, grams: $0.value) }
            .sorted { (item1, item2) in
                let calories1 = item1.food.calories(for: item1.grams)
                let calories2 = item2.food.calories(for: item2.grams)
                return calories1 > calories2
            }
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
                Text("Calorie Breakdown").font(.headline).foregroundColor(effectManager.currentGlobalAccentColor)
                Spacer()
                Button("Close") {}.hidden().disabled(true).padding(.horizontal, 10).padding(.vertical, 5)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)

            // Външният VStack подрежда статичната карта и скролиращия се списък
            VStack(spacing: 16) {
                // 1. Статичната карта с общите калории
                VStack(spacing: 12) {
                    HStack { Text("Consumed:"); Spacer(); Text("\(totalCalories, specifier: "%.0f") kcal") }
                    HStack { Text("Target:"); Spacer(); Text("\(targetCalories, specifier: "%.0f") kcal") }
                    Divider()
                    HStack {
                        Text("Remaining:")
                        Spacer()
                        Text("\(targetCalories - totalCalories, specifier: "%.0f") kcal")
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                }
                .font(.headline)
                .padding()
                .glassCardStyle(cornerRadius: 15)
                .foregroundColor(effectManager.currentGlobalAccentColor)

                // 2. Секция със списъка с храни
                Text("Consumed Foods by Calories")
                    .font(.headline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .frame(maxWidth: .infinity, alignment: .leading) // Подравняваме го вляво

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
                                    grams: item.grams
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
}
