// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/Fitness/TrainingPlanPickerView.swift ====
import SwiftUI
import SwiftData

struct TrainingPlanPickerView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    let title: String
    let dismissButtonLabel: String
    let plans: [TrainingPlan]
    let onDismiss: () -> Void
    let onSelectPlan: (TrainingPlan) -> Void

    init(
        title: String,
        dismissButtonLabel: String = "Close",
        plans: [TrainingPlan],
        onDismiss: @escaping () -> Void,
        onSelectPlan: @escaping (TrainingPlan) -> Void
    ) {
        self.title = title
        self.dismissButtonLabel = dismissButtonLabel
        self.plans = plans
        self.onDismiss = onDismiss
        self.onSelectPlan = onSelectPlan
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(dismissButtonLabel, action: onDismiss)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)

                Spacer()
                Text(title).font(.headline)
                Spacer()

                Button(dismissButtonLabel) {}.hidden()
                    .padding(.horizontal, 10).padding(.vertical, 5)
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if plans.isEmpty {
                        ContentUnavailableView("No Training Plans", systemImage: "calendar.badge.clock")
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                    } else {
                        ForEach(plans) { plan in
                            Button(action: { onSelectPlan(plan) }) {
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
                Color.clear.frame(height: 150)
            }
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.01),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 0.95)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}
