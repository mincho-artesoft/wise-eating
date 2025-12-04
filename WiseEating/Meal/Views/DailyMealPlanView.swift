import SwiftUI
import SwiftData

struct DailyMealPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared
    @ObservedObject private var aiManager = AIManager.shared

    // MARK: - Input
    let profile: Profile
    let planPreview: MealPlanPreview
    let sourceAIGenerationJobID: UUID?
    let onDismiss: () -> Void

    // MARK: - State
    @State private var day: MealPlanDay
    @State private var selectedMealID: MealPlanMeal.ID? = nil
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    // --- НАЧАЛО НА ПРОМЯНАТА (1/5): Добавяме състояние за confirmation dialog ---
    private enum MealAddMode { case append, overwrite }
    @State private var isShowingConfirmation = false
    // --- КРАЙ НА ПРОМЯНАТА (1/5) ---
    
    @State private var targetDate: Date = Date()
    
    private static let palette: [Color] = [
        .orange, .pink, .green, .indigo, .purple, .blue, .red, Color(hex: "#00ffff")
    ]

    // MARK: - Initializer
    init(
        profile: Profile,
        planPreview: MealPlanPreview,
        sourceAIGenerationJobID: UUID?,
        onDismiss: @escaping () -> Void
    ) {
        self.profile = profile
        self.planPreview = planPreview
        self.sourceAIGenerationJobID = sourceAIGenerationJobID
        self.onDismiss = onDismiss
        
        let firstPreviewDay = planPreview.days.first ?? MealPlanPreviewDay(dayIndex: 1, meals: [])
        let tempDay = MealPlanDay(dayIndex: 1)
        
        tempDay.meals = firstPreviewDay.meals.map { previewMeal in
            let newMeal = MealPlanMeal(mealName: previewMeal.name)
            
            newMeal.startTime = previewMeal.startTime
            
            newMeal.entries = previewMeal.items.compactMap { previewItem -> MealPlanEntry? in
                let desc = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.name == previewItem.name && !$0.isUserAdded })
                if let food = (try? GlobalState.modelContext?.fetch(desc))?.first {
                    return MealPlanEntry(food: food, grams: previewItem.grams)
                }
                return nil
            }
            return newMeal
        }
        _day = State(initialValue: tempDay)
    }

    private func daySection(for day: MealPlanDay, dayIndex: Int) -> some View {
        let mealsForColoring = day.meals.sorted { $0.mealName.localizedCompare($1.mealName) == .orderedAscending }
        let colorForThisDay: [String: Color] = Dictionary(uniqueKeysWithValues:
            mealsForColoring.enumerated().map { index, meal in
                (meal.mealName, Self.palette[index % Self.palette.count])
            }
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text("Suggested Meals")
                .font(.headline)
                .foregroundColor(effectManager.currentGlobalAccentColor)
            
            HStack {
                Text("Add to date:")
                    .font(.headline)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                Spacer()
                CustomDatePicker(
                    selection: $targetDate,
                    tintColor: UIColor(effectManager.currentGlobalAccentColor),
                    textColor: .label,
                    minimumDate: Date(), // От днес напред
                    maximumDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()) // Максимум 1 година напред
                )
                .frame(height: 40)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let sortedMealsByTime = day.meals.sorted {
                        ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture)
                    }
                    
                    ForEach(sortedMealsByTime) { meal in
                        mealTabButton(for: meal, in: day, colorMap: colorForThisDay)
                    }
                }
                .padding(.vertical, 4)
            }
            
            if let mealID = selectedMealID, let meal = day.meals.first(where: { $0.id == mealID }) {
                workoutContent(for: meal)
            } else if selectedMealID == day.id {
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

    var body: some View {
        ZStack {
            ThemeBackgroundView().ignoresSafeArea()
            VStack(spacing: 0) {
                toolbar
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        daySection(for: day, dayIndex: 1)
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
            }
            .blur(radius: isSaving ? 1.5 : 0)
            .disabled(isSaving)
            .alert("Error", isPresented: $showAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }
            .onAppear {
                if selectedMealID == nil, let firstMeal = day.meals.first {
                    selectedMealID = firstMeal.id
                }
            }
            // --- НАЧАЛО НА ПРОМЯНАТА (2/5): Добавяме confirmationDialog ---
            .confirmationDialog("Add Meals from Plan", isPresented: $isShowingConfirmation, titleVisibility: .visible) {
                Button("Add to Existing Meals") { processMealPlanAddition(mode: .append) }
                Button("Overwrite Existing Meals", role: .destructive) { processMealPlanAddition(mode: .overwrite) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will add meals for \(targetDate.formatted(date: .abbreviated, time: .omitted)). How should meals for a specific time slot be added?")
            }
            // --- КРАЙ НА ПРОМЯНАТА (2/5) ---
        }
    }

    private var toolbar: some View {
        HStack {
            Button("Cancel", action: onDismiss)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            Spacer()
            Text("Day Meal Plan").font(.headline)
            Spacer()
            // --- НАЧАЛО НА ПРОМЯНАТА (3/5): Бутонът вече показва диалога ---
            Button("Add to Day") {
                isShowingConfirmation = true
            }
            // --- КРАЙ НА ПРОМЯНАТА (3/5) ---
                .disabled(isSaving)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding()
    }

   
    // FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/Meal/Views/DailyMealPlanView.swift

    @ViewBuilder
    private func mealTabButton(for meal: MealPlanMeal, in day: MealPlanDay, colorMap: [String: Color]) -> some View {
        let isSelected = selectedMealID == meal.id
        let baseColor = colorMap[meal.mealName] ?? effectManager.currentGlobalAccentColor

        Button {
            withAnimation {
                selectedMealID = meal.id
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(meal.mealName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isSelected ? baseColor.opacity(0.8) : baseColor.opacity(0.3))
                    )
                    .glassCardStyle(cornerRadius: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(baseColor, lineWidth: isSelected ? 2 : 0)
                    )
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func workoutContent(for meal: MealPlanMeal) -> some View {
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

    // --- НАЧАЛО НА ПРОМЯНАТА (4/5): Новата функция за запис ---
    private func processMealPlanAddition(mode: MealAddMode) {
        Task {
            isSaving = true
            
            let dateToAddTo = targetDate
            let existingMealsForTargetDate = await CalendarViewModel.shared.meals(forProfile: profile, on: dateToAddTo)
            
            for planMeal in day.meals {
                print("   - Processing generated meal: '\(planMeal.mealName)'...")

                let mealTemplate: Meal?
                if let templateFromProfile = profile.meals.first(where: { $0.name == planMeal.mealName }) {
                    mealTemplate = templateFromProfile
                } else if let templateFromExistingEvent = existingMealsForTargetDate.first(where: { $0.name == planMeal.mealName }) {
                    mealTemplate = templateFromExistingEvent
                } else {
                    mealTemplate = planMeal.startTime.map { Meal(name: planMeal.mealName, startTime: $0, endTime: $0.addingTimeInterval(3600)) }
                }

                guard let finalTemplate = mealTemplate else {
                    print("     - ⚠️ Skipping meal '\(planMeal.mealName)', no template found to determine times.")
                    continue
                }
                
                let targetMeal = finalTemplate.detached(for: dateToAddTo)
                let existingMealEvent = existingMealsForTargetDate.first { $0.name == targetMeal.name }

                var finalFoods: [FoodItem: Double] = [:]
                if mode == .append, let existing = existingMealEvent {
                    finalFoods = existing.foods(using: modelContext)
                }
                
                for entry in planMeal.entries {
                    if let food = entry.food {
                        finalFoods[food, default: 0] += entry.grams
                    }
                }
                
                let payload = invisiblePayload(for: finalFoods)
                
                let (success, eventID) = await CalendarViewModel.shared.createEvent(
                    forProfile: profile,
                    startDate: targetMeal.startTime,
                    endDate: targetMeal.endTime,
                    title: targetMeal.name,
                    invisiblePayload: payload,
                    existingEventID: existingMealEvent?.calendarEventID
                )
                print("     - CalendarViewModel.createEvent finished. Success: \(success), Event ID: \(eventID ?? "N/A")")
            }
            
            if let jobID = sourceAIGenerationJobID {
                let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == jobID })
                if let jobToDelete = try? modelContext.fetch(descriptor).first {
                    await aiManager.deleteJob(jobToDelete)
                }
            }
            
            NotificationCenter.default.post(name: .mealTimeDidChange, object: nil)
            
            isSaving = false
            onDismiss()
        }
    }
    // --- КРАЙ НА ПРОМЯНАТА (4/5) ---
    
    // --- НАЧАЛО НА ПРОМЯНАТА (5/5): Премахваме старата функция ---
    // private func addPlanToSelectedDay() { ... } // Тази функция вече не е нужна.
    // --- КРАЙ НА ПРОМЯНАТА (5/5) ---
    
    private func invisiblePayload(for foods: [FoodItem: Double]) -> String? {
       let visible = foods
           .filter { $0.value > 0 }
           .sorted(by: { $0.key.name < $1.key.name })
           .map { "\($0.key.name)=\($0.value)" }
           .joined(separator: "|")
       guard !visible.isEmpty else { return nil }
       return OptimizedInvisibleCoder.encode(from: visible)
   }
}
