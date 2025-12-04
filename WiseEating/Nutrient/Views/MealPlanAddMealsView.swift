import SwiftUI
import SwiftData
import Combine
import EventKit

// +++ START OF ADDITION: New views for the "Add to Plan" flow +++
struct MealPlanAddMealsView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    let sourceMeals: [Meal]
    let onBack: () -> Void
    let onCancel: () -> Void
    let onNext: ([Meal]) -> Void

    @State private var selectedMealIDs: Set<UUID>

    init(sourceMeals: [Meal], onBack: @escaping () -> Void, onCancel: @escaping () -> Void, onNext: @escaping ([Meal]) -> Void) {
        self.sourceMeals = sourceMeals
        self.onBack = onBack
        self.onCancel = onCancel
        self.onNext = onNext
        _selectedMealIDs = State(initialValue: Set(sourceMeals.map { $0.id }))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if sourceMeals.isEmpty {
                ContentUnavailableView("No Meals to Add", systemImage: "fork.knife.circle")
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            } else {
                List {
                    ForEach(sourceMeals) { meal in
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
            Button("Back", action: onBack)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)

            Spacer()
            Text("Select Meals to Add")
                .font(.headline)

            Spacer()

            Button("Next") {
                let selected = sourceMeals.filter { selectedMealIDs.contains($0.id) }
                onNext(selected)
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
            .contentShape(Rectangle())
            .glassCardStyle(cornerRadius: 15)
        }
        .buttonStyle(.plain)
    }
}
