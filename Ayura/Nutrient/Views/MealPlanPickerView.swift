import SwiftUI
import SwiftData

struct MealPlanPickerView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // --- NEW PARAMETERS ---
    let title: String
    let dismissButtonLabel: String
    
    // Входни данни
    let plans: [MealPlan]
    
    // Callbacks
    let onDismiss: () -> Void
    let onSelectPlan: (MealPlan) -> Void

    // --- UPDATED INIT ---
    init(
        title: String,
        dismissButtonLabel: String = "Close",
        plans: [MealPlan],
        onDismiss: @escaping () -> Void,
        onSelectPlan: @escaping (MealPlan) -> Void
    ) {
        self.title = title
        self.dismissButtonLabel = dismissButtonLabel
        self.plans = plans
        self.onDismiss = onDismiss
        self.onSelectPlan = onSelectPlan
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Toolbar
            HStack {
                Button(dismissButtonLabel, action: onDismiss) // Use parameter
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)

                Spacer()
                Text(title).font(.headline) // Use parameter
                Spacer()

                // Невидим бутон за симетрия
                Button(dismissButtonLabel) {}.hidden() // Use parameter
                    .padding(.horizontal, 10).padding(.vertical, 5)
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding()

            // MARK: - List of Plans
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if plans.isEmpty {
                        ContentUnavailableView("No Meal Plans", systemImage: "calendar.badge.clock")
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                    } else {
                        ForEach(plans) { plan in
                            Button(action: {
                                onSelectPlan(plan)
                            }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(plan.name)
                                        .font(.headline)
                                    
                                    HStack {
                                        Text("\(plan.days.count) day\(plan.days.count == 1 ? "" : "s")")
                                        Text("•")
                                        Text("Created: \(plan.creationDate.formatted(date: .abbreviated, time: .omitted))")
                                    }
                                    .font(.caption)
                                    .opacity(0.8)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .glassCardStyle(cornerRadius: 15)
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
                
                Color.clear
                    .frame(height: 150)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            // --- MASK ADDED HERE ---
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
