import SwiftUI
import SwiftData

struct AIPlanGenerationView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared
    
    @ObservedObject private var aiManager = AIManager.shared
    
    let profile: Profile
    let onDismiss: () -> Void
    
    @State private var numberOfDays: Int = 7
    @State private var selectedMealNames: Set<String>

    init(profile: Profile, onDismiss: @escaping () -> Void) {
        self.profile = profile
        self.onDismiss = onDismiss
        _selectedMealNames = State(initialValue: Set(profile.meals.map { $0.name }))
    }

    var body: some View {
        ZStack {
            ThemeBackgroundView().ignoresSafeArea()

            VStack(spacing: 20) {
                Text("AI Meal Plan Generator")
                    .font(.largeTitle.bold())
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)
                
                initialPrompt
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var initialPrompt: some View {
        VStack(spacing: 20) {
            Text("Ready to create a personalized meal plan based on your profile?")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.9))

            daySelector
            mealSelector

            Button(action: startJobAndDismiss) {
                Label("Generate Plan", systemImage: "sparkles")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .disabled(selectedMealNames.isEmpty)
            .glassCardStyle(cornerRadius: 20)
            .foregroundStyle(effectManager.currentGlobalAccentColor)

            Spacer()
            
            Button("Not Now", action: onDismiss)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
        }
    }

    @ViewBuilder
    private var daySelector: some View {
        VStack(spacing: 8) {
            Text("Select Plan Duration")
                .font(.caption)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            
            VStack(spacing: 10) {
                HStack() {
                    ForEach(1...3, id: \.self) { day in
                        Spacer()
                        dayButton(for: day)
                        Spacer()
                    }
                }
                HStack() {
                    ForEach(4...7, id: \.self) { day in
                        Spacer()
                        dayButton(for: day)
                        Spacer()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func dayButton(for day: Int) -> some View {
        Button(action: {
            withAnimation(.spring()) {
                numberOfDays = day
            }
        }) {
            Text("\(day)")
                .font(numberOfDays == day ? .headline.bold() : .body)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    ZStack {
                        if numberOfDays == day {
                            Circle().fill(effectManager.currentGlobalAccentColor.opacity(0.3))
                        }
                        Circle().stroke(effectManager.currentGlobalAccentColor.opacity(0.5))
                    }
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var mealSelector: some View {
        VStack(spacing: 8) {
            Text("Select Meals to Generate")
                .font(.caption)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            
            CustomFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(profile.meals.sorted { $0.startTime < $1.startTime }) { meal in
                    let isSelected = selectedMealNames.contains(meal.name)
                    Button(action: {
                        withAnimation(.spring()) {
                            if isSelected {
                                selectedMealNames.remove(meal.name)
                            } else {
                                selectedMealNames.insert(meal.name)
                            }
                        }
                    }) {
                        Text(meal.name)
                            .font(isSelected ? .caption.bold() : .caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                ZStack {
                                    if isSelected {
                                        Capsule().fill(effectManager.currentGlobalAccentColor.opacity(0.3))
                                    }
                                    Capsule().stroke(effectManager.currentGlobalAccentColor.opacity(0.5))
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func startJobAndDismiss() {
        let orderedMeals = profile.meals
            .sorted { $0.startTime < $1.startTime }
            .map { $0.name }
            .filter { selectedMealNames.contains($0) }
        let specificMealsArg: [String]? = orderedMeals.isEmpty ? nil : orderedMeals
        
        // --- START OF CHANGE ---
        aiManager.startPlanGeneration(
            for: profile,
            days: numberOfDays,
            meals: specificMealsArg,
            jobType: .mealPlan
        )
        // --- END OF CHANGE ---
        
        onDismiss()
    }
}
