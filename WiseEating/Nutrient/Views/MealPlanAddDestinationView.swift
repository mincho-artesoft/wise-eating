import SwiftUI

struct MealPlanAddDestinationView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    // MARK: - Input Properties
    @Bindable var targetPlan: MealPlan
    let selectedMeals: [Meal]
    let profile: Profile // Профилът е нужен за цветовете
    let onBack: () -> Void
    let onComplete: () -> Void

    // MARK: - State
    @State private var isReplacing = false
    @State private var selectedMealIDByDay: [MealPlanDay.ID: MealPlanMeal.ID?] = [:]
    
    // MARK: - Color Helpers
    private static let palette: [Color] = [
        .orange, .pink, .green, .indigo, .purple, .blue, .red, Color(hex: "#00ffff")
    ]

    private var colorFor: [String: Color] { // Keyed by Meal Name
        let sortedTemplates = profile.meals.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let n = Self.palette.count

        return Dictionary(uniqueKeysWithValues:
            sortedTemplates.enumerated().map { idx, mealTemplate in
                (mealTemplate.name, Self.palette[idx % n])
            })
    }

    // MARK: - Initializer
    init(targetPlan: MealPlan, selectedMeals: [Meal], profile: Profile, onBack: @escaping () -> Void, onComplete: @escaping () -> Void) {
        self.targetPlan = targetPlan
        self.selectedMeals = selectedMeals
        self.profile = profile
        self.onBack = onBack
        self.onComplete = onComplete
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    Button(action: addAsNewDay) {
                        Label("Add as New Day", systemImage: "plus.square.on.square")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                    Button(action: { withAnimation { isReplacing.toggle() } }) {
                        Label("Replace an Existing Day", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                    if isReplacing {
                        VStack(spacing: 16) {
                            ForEach(Array(targetPlan.days.sorted { $0.dayIndex < $1.dayIndex }.enumerated()), id: \.element.id) { index, day in
                                dayReplacementCard(for: day, dayIndex: index + 1)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding()
                
                Spacer(minLength: 150)
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
            Spacer()
        }
    }

    // MARK: - Subviews
    
    private var toolbar: some View {
        HStack {
            Button("Back", action: onBack)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            Text("Choose Destination")
                .font(.headline)
            Spacer()
            
            Button("Back", action: {})
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
                .hidden()
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding()
    }

    private func dayReplacementCard(for day: MealPlanDay, dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Day \(dayIndex)")
                    .font(.headline)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                
                Spacer()

                Button("Replace This Day") {
                    replace(day: day)
                }
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 15)
                .foregroundColor(effectManager.currentGlobalAccentColor)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let sortedMeals = day.meals.sorted { m1, m2 in
                        let t1 = profile.meals.first { $0.name == m1.mealName }?.startTime ?? .distantFuture
                        let t2 = profile.meals.first { $0.name == m2.mealName }?.startTime ?? .distantFuture
                        return t1 < t2
                    }
                    
                    ForEach(sortedMeals) { meal in
                        mealTabButton(for: meal, in: day)
                    }
                }
                .padding(.vertical, 4)
            }
            
            ForEach(day.meals) { meal in
                if meal.id == selectedMealIDByDay[day.id] {
                    mealContent(for: meal)
                }
            }
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
        .animation(.default, value: selectedMealIDByDay[day.id])
    }
    
    @ViewBuilder
    private func mealTabButton(for meal: MealPlanMeal, in day: MealPlanDay) -> some View {
        let isSelected = selectedMealIDByDay[day.id] == meal.id
        let baseColor = colorFor[meal.mealName] ?? effectManager.currentGlobalAccentColor

        Button {
            withAnimation {
                // Проверяваме дали текущият meal.id е вече избран за този ден
                if let selectedID = selectedMealIDByDay[day.id], selectedID == meal.id {
                    // Ако е, премахваме селекцията
                    selectedMealIDByDay[day.id] = nil
                } else {
                    // В противен случай, го избираме
                    selectedMealIDByDay[day.id] = meal.id
                }
            }
        } label: {
            // --- НАЧАЛО НА ПРОМЯНАТА ---
            ZStack(alignment: .topTrailing) {
                Text(meal.mealName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(isSelected ? baseColor.opacity(0.8) : baseColor.opacity(0.3))
                        }
                    )
                    .glassCardStyle(cornerRadius: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(baseColor, lineWidth: isSelected ? 2 : 0)
                    )
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                if !meal.entries.isEmpty {
                    ZStack {
                        Circle()
                            .fill(baseColor)
                        Text("\(meal.entries.count)")
                            .font(.system(size: 10, weight: .bold))
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .frame(width: 16, height: 16)
                    .offset(x: 6, y: -6)
                }else{
                    ZStack {
                        Circle()
                            .fill(baseColor)
                        Text("\(0)")
                            .font(.system(size: 10, weight: .bold))
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .frame(width: 16, height: 16)
                    .offset(x: 6, y: -6)
                }
            }
            // Добавяме padding, за да осигурим място за отместения индикатор
            .padding(.top, 10)
            .padding(.trailing, 10)
            // --- КРАЙ НА ПРОМЯНАТА ---
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func mealContent(for meal: MealPlanMeal) -> some View {
        PagedMealContentView(meal: meal)
    }

    // MARK: - Actions
    
    private func addAsNewDay() {
        let newIndex = (targetPlan.days.map { $0.dayIndex }.max() ?? 0) + 1
        let newDay = MealPlanDay(dayIndex: newIndex)
        
        for meal in selectedMeals {
            let newMeal = MealPlanMeal(mealName: meal.name)
            let foods = meal.foods(using: modelContext)
            for (foodItem, grams) in foods {
                let newEntry = MealPlanEntry(food: foodItem, grams: grams)
                newEntry.meal = newMeal
                newMeal.entries.append(newEntry)
            }
            newMeal.day = newDay
            newDay.meals.append(newMeal)
        }
        
        newDay.plan = targetPlan
        targetPlan.days.append(newDay)
        
        saveAndDismiss()
    }
    
    private func replace(day: MealPlanDay) {
        let mealNamesToReplace = Set(selectedMeals.map { $0.name })
        let mealsToDelete = day.meals.filter { mealNamesToReplace.contains($0.mealName) }
        
        for meal in mealsToDelete {
            meal.entries.forEach { modelContext.delete($0) }
            modelContext.delete(meal)
        }
        day.meals.removeAll { mealNamesToReplace.contains($0.mealName) }

        for meal in selectedMeals {
            let newMeal = MealPlanMeal(mealName: meal.name)
            let foods = meal.foods(using: modelContext)
            for (foodItem, grams) in foods {
                let newEntry = MealPlanEntry(food: foodItem, grams: grams)
                newEntry.meal = newMeal
                newMeal.entries.append(newEntry)
            }
            newMeal.day = day
            day.meals.append(newMeal)
        }
        
        saveAndDismiss()
    }
    
    private func saveAndDismiss() {
        do {
            try modelContext.save()
        } catch {
            print("Error saving meal plan: \(error)")
        }
        onComplete()
    }
}
