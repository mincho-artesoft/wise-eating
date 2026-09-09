import SwiftUI

struct TrainingSummaryView: View {
    // MARK: - Environment & Managers
    @ObservedObject private var effectManager = EffectManager.shared
    
    // MARK: - Input Properties
    let selectedWorkoutCaloriesBurned: Double
    let totalCaloriesBurnedToday: Double
    let targetCalories: Double
    let netCalorieBalance: Double
    let totalCaloriesConsumedToday: Double
    
    // --- НАЧАЛО НА ПРОМЯНАТА (1/2): Добавяме isPinned и onTap ---
    @Binding var isPinned: Bool
    let onTap: (TrainingView.TrainingRingDetailType) -> Void
    // --- КРАЙ НА ПРОМЯНАТА (1/2) ---

    // MARK: - Body
    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top) {
                Spacer()
                
                // --- НАЧАЛО НА ПРОМЯНАТА (2/2): Обвиваме всеки ринг в Button ---
                Button(action: { onTap(.workout) }) {
                    VStack(spacing: 4) {
                        CalorieBurnRingView(
                            value: selectedWorkoutCaloriesBurned,
                            target: nil,
                            color: .orange
                        )
                        .frame(width: 60, height: 60)

                        Text("Workout")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                .padding(10)
                .glassCardStyle(cornerRadius: 20)
                
                Spacer()

                Button(action: { onTap(.totalBurned) }) {
                    VStack(spacing: 4) {
                        CalorieBurnRingView(
                            value: totalCaloriesBurnedToday,
                            target: nil,
                            color: .red
                        )
                        .frame(width: 60, height: 60)
                    
                        Text("Total Burned")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                .padding(10)
                .glassCardStyle(cornerRadius: 20)

                Spacer()

                Button(action: { onTap(.netBalance) }) {
                    VStack(spacing: 4) {
                        NetBalanceRingView(
                            netCalorieBalance: netCalorieBalance,
                            totalCaloriesConsumed: totalCaloriesConsumedToday
                        )
                        .frame(width: 60, height: 60)
                        
                        Text("Net Balance")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                .padding(10)
                .glassCardStyle(cornerRadius: 20)
                // --- КРАЙ НА ПРОМЯНАТА (2/2) ---

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
            .padding(.trailing, 10)
        }
    }
}
