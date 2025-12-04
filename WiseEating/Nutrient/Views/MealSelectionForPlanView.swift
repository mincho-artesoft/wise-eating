// FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth/WiseEating/Nutrient/Views/MealSelectionForPlanView.swift

import SwiftUI
import SwiftData

struct MealSelectionForPlanView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    // MARK: - Input
    let profile: Profile
    let meals: [Meal]
    let onBack: () -> Void
    let onCancel: () -> Void
    let onCreatePlan: ([Meal], String) -> Void

    // MARK: - State
    @State private var selectedMealIDs: Set<UUID>

    // MARK: - Initializer
    init(profile: Profile, meals: [Meal], onBack: @escaping () -> Void, onCancel: @escaping () -> Void, onCreatePlan: @escaping ([Meal], String) -> Void) {
        self.profile = profile
        self.meals = meals
        self.onBack = onBack
        self.onCancel = onCancel
        self.onCreatePlan = onCreatePlan
        _selectedMealIDs = State(initialValue: Set(meals.map { $0.id }))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if meals.isEmpty {
                ContentUnavailableView("No Meals to Copy", systemImage: "fork.knife.circle")
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            } else {
                List {
                    ForEach(meals) { meal in
                        mealRow(for: meal)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
    }

    private var toolbar: some View {
        HStack {
            Button(action: onBack) {
                HStack {
                    Text("Back")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)

            Spacer()
            
            Text("Select Meals")
                .font(.headline)

            Spacer()

            Button("Create") {
                handleCreateAction()
            }
            .disabled(selectedMealIDs.isEmpty)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            .foregroundStyle(selectedMealIDs.isEmpty ? effectManager.currentGlobalAccentColor.opacity(0.5) : effectManager.currentGlobalAccentColor)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding()
    }
    
    private func mealRow(for meal: Meal) -> some View {
        Button(action: {
            if selectedMealIDs.contains(meal.id) {
                selectedMealIDs.remove(meal.id)
            } else {
                selectedMealIDs.insert(meal.id)
            }
        }) {
            HStack {
                Image(systemName: selectedMealIDs.contains(meal.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                
                VStack(alignment: .leading) {
                    Text(meal.name)
                        .font(.headline)
                    Text("\(meal.foods(using: modelContext).count) items")
                        .font(.caption)
                        .opacity(0.8)
                }
                .foregroundColor(effectManager.currentGlobalAccentColor)
                
                Spacer()
            }
            .padding()
            // --- НАЧАЛО НА ПРОМЯНАТА ---
            .contentShape(Rectangle()) // Това прави цялата зона (включително празното място) кликаема
            // --- КРАЙ НА ПРОМЯНАТА ---
            .glassCardStyle(cornerRadius: 15)
        }
        .buttonStyle(.plain)
    }

    private func handleCreateAction() {
        guard !selectedMealIDs.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let dateString = formatter.string(from: Date())
        let defaultPlanName = "Meal Plan \(dateString)"

        let selected = meals.filter { selectedMealIDs.contains($0.id) }
        
        onCreatePlan(selected, defaultPlanName)
    }
}
