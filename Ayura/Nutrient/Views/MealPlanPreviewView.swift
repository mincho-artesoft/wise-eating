import SwiftUI
import SwiftData

struct MealPlanPreviewView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // ... (всички properties и init остават същите) ...
    let plan: MealPlan
    let profile: Profile
    let onDismiss: () -> Void
    let onAdd: ([MealPlanDay]) -> Void

    @State private var days: [MealPlanDay]
    @State private var selectedDayIDs: Set<MealPlanDay.ID>
    
    @State private var editMode: EditMode = .inactive
    
    @State private var selectedMealIDByDay: [MealPlanDay.ID: MealPlanMeal.ID?] = [:]

    init(plan: MealPlan, profile: Profile, onDismiss: @escaping () -> Void, onAdd: @escaping ([MealPlanDay]) -> Void) {
        self.plan = plan
        self.profile = profile
        self.onDismiss = onDismiss
        self.onAdd = onAdd
        
        let sortedInitialDays = plan.days.sorted { $0.dayIndex < $1.dayIndex }
        _days = State(initialValue: sortedInitialDays)
        _selectedDayIDs = State(initialValue: Set(sortedInitialDays.map { $0.id }))

        var initialSelections: [MealPlanDay.ID: MealPlanMeal.ID?] = [:]
        for day in sortedInitialDays {
            let sortedMeals = day.meals.sorted { m1, m2 in
                let t1 = profile.meals.first { $0.name == m1.mealName }?.startTime ?? .distantFuture
                let t2 = profile.meals.first { $0.name == m2.mealName }?.startTime ?? .distantFuture
                return t1 < t2
            }
            initialSelections[day.id] = sortedMeals.first?.id
        }
        _selectedMealIDByDay = State(initialValue: initialSelections)
    }
    
    private static let palette: [Color] = [
        .orange, .pink, .green, .indigo, .purple, .blue, .red, Color(hex: "#00ffff")
    ]

    private var colorFor: [MealPlanMeal.ID: Color] {
        let sortedTemplates = profile.meals.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let n = Self.palette.count

        let colorByName = Dictionary(uniqueKeysWithValues:
            sortedTemplates.enumerated().map { idx, mealTemplate in
                (mealTemplate.name, Self.palette[idx % n])
            })

        var finalMap: [MealPlanMeal.ID: Color] = [:]
        for day in days {
            for meal in day.meals {
                finalMap[meal.id] = colorByName[meal.mealName] ?? .gray
            }
        }
        return finalMap
    }
    
    private var sortedDaysForDisplay: [MealPlanDay] {
        let selected = days.filter { selectedDayIDs.contains($0.id) }.sorted { $0.dayIndex < $1.dayIndex }
        let deselected = days.filter { !selectedDayIDs.contains($0.id) }.sorted { $0.dayIndex < $1.dayIndex }
        return selected + deselected
    }
    
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            
            List {
                ForEach(Array(sortedDaysForDisplay.enumerated()), id: \.element.id) { visualIndex, day in
                    let isDraggable = selectedDayIDs.contains(day.id)
                    
                    daySection(for: day, dayIndex: visualIndex + 1)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .moveDisabled(!isDraggable)
                        .opacity(editMode.isEditing && !isDraggable ? 0.6 : 1.0)
                }
                .onMove(perform: moveDay)
                
                Color.clear
                    .frame(height: 150)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
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
    }
    
    private var toolbar: some View {
        HStack {
            Button("Back", action: onDismiss)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            
            if editMode.isEditing {
                EditButton()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
            } else {
                Button("Add to Meal") {
                    let selectedDays = sortedDaysForDisplay.filter { selectedDayIDs.contains($0.id) }
                    onAdd(selectedDays)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding([.horizontal, .top])
        .animation(.default, value: editMode)
    }
    
    private func daySection(for day: MealPlanDay, dayIndex: Int) -> some View {
        // --- НАЧАЛО НА ПРОМЯНАТА ---
        VStack(alignment: .leading, spacing: 10) { // Намалено от 12 на 10
            HStack {
                Text("Day \(dayIndex)")
                    .font(.headline)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        toggleSelection(for: day)
                    }
                }) {
                    Image(systemName: selectedDayIDs.contains(day.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
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
                .padding(.vertical, 2) // Намалено от 4 на 2
            }
            
            ForEach(day.meals) { meal in
                if meal.id == selectedMealIDByDay[day.id] {
                    mealContent(for: meal)
                }
            }
        }
        .padding(12) // Намалено от .padding() (което е 16) на 12
        .glassCardStyle(cornerRadius: 20)
        .animation(.default, value: selectedMealIDByDay[day.id])
        // --- КРАЙ НА ПРОМЯНАТА ---
    }

    @ViewBuilder
    private func mealTabButton(for meal: MealPlanMeal, in day: MealPlanDay) -> some View {
        let isSelected = selectedMealIDByDay[day.id] == meal.id
        let baseColor = colorFor[meal.id] ?? effectManager.currentGlobalAccentColor

        Button {
            withAnimation {
                selectedMealIDByDay[day.id] = meal.id
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
    
    private func toggleSelection(for day: MealPlanDay) {
        if selectedDayIDs.contains(day.id) {
            selectedDayIDs.remove(day.id)
        } else {
            let maxIndex = days
                .filter { selectedDayIDs.contains($0.id) }
                .map { $0.dayIndex }
                .max() ?? 0
            
            if let dayToUpdate = days.first(where: { $0.id == day.id }) {
                dayToUpdate.dayIndex = maxIndex + 1
            }
            
            selectedDayIDs.insert(day.id)
        }
    }
    
    private func moveDay(from source: IndexSet, to destination: Int) {
        var selectedDays = days.filter { selectedDayIDs.contains($0.id) }.sorted { $0.dayIndex < $1.dayIndex }
        selectedDays.move(fromOffsets: source, toOffset: destination)

        for (index, day) in selectedDays.enumerated() {
            if let dayInState = days.first(where: { $0.id == day.id }) {
                dayInState.dayIndex = index + 1
            }
        }
    }
}
