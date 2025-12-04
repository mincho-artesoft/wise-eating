import SwiftUI

struct RingsSummaryRow<CalorieRing: View, MacroRing: View>: View {
    @ObservedObject private var effectManager = EffectManager.shared

    // Съществуващи properties
    let goalsAchieved: Int
    let totalGoals: Int
    let onTap: (NutritionsDetailView.RingDetailType) -> Void
    @ViewBuilder let calorieRing: () -> CalorieRing
    @ViewBuilder let macroRing: () -> MacroRing
    @Binding var isPinned: Bool
    
    // Properties за водата
    @Binding var waterConsumed: Int
    @State var showGlassWaterTrackerView: Bool = false
    
    let waterGoal: Int
    let onIncrementWater: () -> Void
    let onDecrementWater: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top) {
                Spacer()

                VStack(spacing: 4) {
//                    if(showGlassWaterTrackerView) {
                        ZStack() {
                            GlassWaterTrackerView(
                                consumed: $waterConsumed,
                                goal: waterGoal,
                                onIncrement: onIncrementWater,
                                onDecrement: onDecrementWater
                            )
                            Text("\(waterConsumed) / \(waterGoal)")
                                .font(.caption)
                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        }
//                    } else {
//                        WaterTrackerView(
//                            consumed: $waterConsumed,
//                            goal: waterGoal,
//                            onIncrement: onIncrementWater,
//                            onDecrement: onDecrementWater
//                        )
//                    }

                    // 3) Етикетът
                    Text("Water")
                        .font(.caption)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        .padding(.top, -10)
                }
                .onAppear {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                        self.showGlassWaterTrackerView = true
                    }
                }
                .padding(.bottom, 10)
                .glassCardStyle(cornerRadius: 20)
                
                Button(action: { onTap(.goals) }) {
                    VStack(spacing: 4) {
                        GoalRingView(achieved: goalsAchieved, total: totalGoals, diameter: 60)
                            .frame(width: 60, height: 60)

                        Text("Goals")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                .padding(10)
                .glassCardStyle(cornerRadius: 20)


                Button(action: { onTap(.calories) }) {
                    VStack(spacing: 4) {
                        calorieRing()
                            .frame(width: 60, height: 60)
                        Text("Calories")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                .padding(10)
                .glassCardStyle(cornerRadius: 20)

                Button(action: { onTap(.macros) }) {
                    VStack(spacing: 4) {
                        macroRing()
                            .frame(width: 60, height: 60)
                        Text("Macros")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                .padding(10)
                .glassCardStyle(cornerRadius: 20)

             

                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 2)

            HStack {
                Spacer()
                Button(action: { isPinned.toggle() }) {
                    Image(systemName: isPinned ? "pin.fill" : "pin.slash")
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
            }
            .padding(.trailing, 30)
        }
    }
}
