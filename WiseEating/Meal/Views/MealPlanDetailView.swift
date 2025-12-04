import SwiftUI
import SwiftData

struct MealPlanDetailView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // --- НАЧАЛО НА ПРОМЯНАТА (1/3): Добавяме safeAreaInsets ---
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    
    let plan: MealPlan
    let profile: Profile
    let onDismiss: () -> Void
    
    @Binding var navBarIsHiden: Bool
    
    // MARK: - State for UI
    @State private var selectedDayID: MealPlanDay.ID? = nil
    @State private var selectedMealID: MealPlanMeal.ID? = nil
    
    init(plan: MealPlan, profile: Profile, onDismiss: @escaping () -> Void, navBarIsHiden: Binding<Bool>) {
        self.plan = plan
        self.profile = profile
        self.onDismiss = onDismiss
        self._navBarIsHiden = navBarIsHiden
    }

    private var sortedDays: [MealPlanDay] {
        plan.days.sorted { $0.dayIndex < $1.dayIndex }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                   
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // --- НАЧАЛО НА ПРОМЯНАТА ---
                    // Преместеното заглавие, вече е тук и е центрирано
                    Text(plan.name)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundColor(effectManager.currentGlobalAccentColor)


                    if plan.minAgeMonths > 0 {
                        HStack {
                            Text("Minimum Age:")
                                .font(.headline)
                            Spacer()
                            Text("\(plan.minAgeMonths) months")
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                        .padding()
                        .glassCardStyle(cornerRadius: 20)
                    }
                    // --- КРАЙ НА ПРОМЯНАТА ---
                    
                    ForEach(Array(sortedDays.enumerated()), id: \.element.id) { index, day in
                        daySection(for: day, dayIndex: index + 1)
                    }
                }
                .padding()
                
                Color.clear
                    .frame(height: 150)
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
        // --- НАЧАЛО НА ПРОМЯНАТА (3/3): Прилагаме отстоянието към целия изглед ---
        .background(ThemeBackgroundView().ignoresSafeArea())
        .onAppear {
            navBarIsHiden = true
            if selectedDayID == nil, let firstDay = sortedDays.first {
                selectedDayID = firstDay.id
                
                let sortedMealsOfFirstDay = firstDay.meals.sorted { m1, m2 in
                    let t1 = profile.meals.first { $0.name == m1.mealName }?.startTime ?? .distantFuture
                    let t2 = profile.meals.first { $0.name == m2.mealName }?.startTime ?? .distantFuture
                    return t1 < t2
                }
                
                if let firstMeal = sortedMealsOfFirstDay.first {
                    selectedMealID = firstMeal.id
                }
            }
        }
        .onDisappear { navBarIsHiden = false }
    }
    
    private var toolbar: some View {
        HStack {
            Button("Back", action: onDismiss)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            
            // --- НАЧАЛО НА ПРОМЯНАТА ---
            // Text(plan.name) беше премахнато от тук
            // --- КРАЙ НА ПРОМЯНАТА ---
            
            Spacer()
            
            Button("Back", action: {})
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
                .hidden()
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        // Премахваме .top и добавяме .bottom за по-добро разстояние
        .padding(.horizontal)
    }
    
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
    
    private func daySection(for day: MealPlanDay, dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Day \(dayIndex)")
                .font(.headline)
                .foregroundColor(effectManager.currentGlobalAccentColor)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let sortedMealTemplates = profile.meals.sorted { $0.startTime < $1.startTime }
                    
                    ForEach(sortedMealTemplates) { mealTemplate in
                        mealTabButton(for: mealTemplate, in: day)
                    }
                }
                .padding(.vertical, 4)
            }
            
            if let mealID = selectedMealID, let meal = day.meals.first(where: { $0.id == mealID }) {
                mealContent(for: meal)
            } else if selectedDayID == day.id {
                Text("No items planned for this meal.")
                    .font(.caption)
                    .italic()
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
            }
        }
        .animation(.default, value: selectedMealID)
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }
    
    @ViewBuilder
        private func mealTabButton(for mealTemplate: Meal, in day: MealPlanDay) -> some View {
            let meal = day.meals.first { $0.mealName == mealTemplate.name }
            
            let isSelected = selectedMealID == meal?.id && selectedDayID == day.id
            let baseColor = colorFor[mealTemplate.name] ?? effectManager.currentGlobalAccentColor

            Button {
                withAnimation {
                    selectedDayID = day.id
                    selectedMealID = meal?.id
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Text(mealTemplate.name)
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
                    
                    if let meal = meal, !meal.entries.isEmpty {
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
                // --- НАЧАЛО НА ПРОМЯНАТА ---
                // Добавяме padding, за да осигурим място за отместения индикатор
                .padding(.top, 10)
                .padding(.trailing, 10)
                // --- КРАЙ НА ПРОМЯНАТА ---
            }
            .buttonStyle(.plain)
        }
    
    @ViewBuilder
    private func mealContent(for meal: MealPlanMeal) -> some View {
        VStack {
            if !meal.entries.isEmpty {
                let sortedEntries = meal.entries.sorted { ($0.food?.name ?? "") < ($1.food?.name ?? "") }
                ForEach(sortedEntries) { entry in
                    MealPlanEntryDetailRowView(entry: entry)
                }
            } else {
                Text("No items planned for this meal.")
                    .font(.caption)
                    .italic()
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
            }
        }
        .contentShape(Rectangle())
    }
}
