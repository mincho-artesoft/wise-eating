// FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth/WiseEating/Nutrient/Views/PagedMealContentView.swift

import SwiftUI

struct PagedMealContentView: View {
    let meal: MealPlanMeal
    @ObservedObject private var effectManager = EffectManager.shared

    @StateObject private var pageState = PageState()

    private var rows: [(FoodItem, Double)] {
        meal.entries.compactMap { entry in
            guard let food = entry.food else { return nil }
            return (food, entry.grams)
        }
    }

    private var pageCount: Int {
        rows.count > 1 ? rows.count + 1 : rows.count
    }

    var body: some View {
        if rows.isEmpty {
            // --- НАЧАЛО НА ПРОМЯНАТА 1: Намаляваме височината за празно състояние ---
            Text("No items planned for this meal.")
                .font(.caption)
                .italic()
                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .center) // Намалено от 110 на 50
            // --- КРАЙ НА ПРОМЯНАТА 1 ---
        } else {
            // --- НАЧАЛО НА ПРОМЯНАТА 2: Намаляваме разстоянието и общата височина ---
            VStack(spacing: 4) { // Намалено от 6 на 4
                GeometryReader { geo in
                    TabView(selection: $pageState.pageIndex) {
                        if pageCount > 1 {
                            MealSummaryRowEventView(rows: rows)
                                .frame(maxWidth: geo.size.width, alignment: .leading)
                                .tag(0)
                        }
                        
                        ForEach(Array(rows.enumerated()), id: \.1.0.id) { idx, pair in
                            FoodItemRowEventView(item: pair.0, amount: pair.1)
                                .frame(maxWidth: geo.size.width, alignment: .leading)
                                .tag(pageCount > 1 ? idx + 1 : idx)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                .frame(height: 85) // Намалено от 95 на 85

                if pageCount > 1 {
                    PageIndicatorView(pageCount: pageCount, pageState: pageState)
                }
            }
            // --- КРАЙ НА ПРОМЯНАТА 2 ---
        }
    }
}
